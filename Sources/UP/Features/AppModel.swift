import AppKit
import Foundation

enum ConnectionState: Equatable {
    case searching
    case connected
}

struct LogEntry: Identifiable {
    enum Kind { case info, success, warning }
    let id = UUID()
    let date = Date()
    let text: String
    let kind: Kind
}

/// Central coordinator: connects to the client, reacts to events and runs the automations.
@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let gameData = GameData()
    let advisor = DraftAdvisor()
    private let scout = PlayerScout()

    private(set) var connection: ConnectionState = .searching
    private(set) var client: LCUClient?
    private(set) var me: Summoner?
    private(set) var myProfile: PlayerProfile?
    private(set) var myMasteries: [ChampionMastery] = []
    private(set) var phase = "None"
    private(set) var logs: [LogEntry] = []

    private(set) var champSelect: ChampSelectSession?
    private(set) var teamProfiles: [String: PlayerProfile] = [:]
    private(set) var gameSession: GameflowSession?
    private(set) var live: LiveGameSnapshot?
    private(set) var isPreview = false

    private var liveTask: Task<Void, Never>?
    private var lastImportKey: String?
    private var lastPickTurnActionId: Int?
    private var acceptScheduled = false

    var mapId: Int { gameSession?.map?.id ?? (gameSession?.gameData?.queue?.gameMode == "ARAM" ? 12 : 11) }
    var queueMode: QueueMode { mapId == 12 ? .aram : .ranked }
    var isInChampSelect: Bool { champSelect != nil && (phase == "ChampSelect" || isPreview) }

    // MARK: Connection

    func start() {
        Task { await connectionLoop() }
    }

    private func connectionLoop() async {
        while true {
            if let credentials = LockfileLocator.find() {
                await run(credentials)
                log(tr("Lost connection to the client, searching again…"), .warning)
            }
            connection = .searching
            client = nil
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func run(_ credentials: LCUCredentials) async {
        let client = LCUClient(credentials: credentials)
        guard let summoner: Summoner = try? await client.get("/lol-summoner/v1/current-summoner") else { return }

        self.client = client
        ImageCache.shared.client = client
        me = summoner
        connection = .connected
        log(tr("Connected as %@", summoner.riotId), .success)

        if !gameData.isLoaded { await gameData.load(using: client) }
        await refreshPhase()
        Task { await refreshMyProfile() }

        let socket = LCUWebSocket(credentials: credentials)
        do {
            for try await event in socket.events() { await handle(event) }
        } catch {
            log(tr("Client connection closed: %@", error.localizedDescription), .warning)
        }
        stopLiveTracking()
    }

    func refreshMyProfile() async {
        guard let client, let me else { return }
        await scout.invalidate()
        myProfile = await scout.profile(puuid: me.puuid, client: client, historyCount: 20)
        myMasteries = (try? await client.get("/lol-champion-mastery/v1/local-player/champion-mastery")) ?? []
    }

    private func refreshPhase() async {
        guard let client else { return }
        if let phase: String = try? await client.get("/lol-gameflow/v1/gameflow-phase") { await setPhase(phase) }
        if let session: ChampSelectSession = try? await client.get("/lol-champ-select/v1/session") {
            await handleChampSelect(session)
        }
    }

    // MARK: Events

    private func handle(_ event: LCUEvent) async {
        switch event.uri {
        case "/lol-gameflow/v1/gameflow-phase":
            if let phase = event.decode(String.self) { await setPhase(phase) }
        case "/lol-matchmaking/v1/ready-check":
            if let check = event.decode(ReadyCheck.self) { handleReadyCheck(check) }
        case "/lol-champ-select/v1/session":
            guard !isPreview else { return }
            if event.eventType == "Delete" { champSelect = nil } else if let session = event.decode(ChampSelectSession.self) {
                await handleChampSelect(session)
            }
        case "/lol-summoner/v1/current-summoner":
            if let summoner = event.decode(Summoner.self) { me = summoner }
        default:
            break
        }
    }

    private func setPhase(_ newPhase: String) async {
        guard newPhase != phase else { return }
        if isPreview { endPreview() }
        phase = newPhase
        log(tr("Phase: %@", phaseTitle))

        switch newPhase {
        case "ChampSelect":
            lastImportKey = nil
            lastPickTurnActionId = nil
            teamProfiles = [:]
            advisor.reset()
            gameSession = try? await client?.get("/lol-gameflow/v1/session")
        case "InProgress", "Reconnect":
            gameSession = try? await client?.get("/lol-gameflow/v1/session")
            startLiveTracking()
        case "EndOfGame", "WaitingForStats", "PreEndOfGame":
            stopLiveTracking()
            if newPhase == "EndOfGame" {
                Task { await refreshMyProfile() }
                if settings.autoPlayAgain {
                    try? await Task.sleep(for: .seconds(2))
                    await perform(tr("Returned to lobby")) { try await $0.post("/lol-lobby/v2/play-again") }
                }
            }
        case "None", "Lobby":
            stopLiveTracking()
            champSelect = nil
        default:
            break
        }
    }

    var phaseTitle: String {
        switch phase {
        case "None": tr("In client")
        case "Lobby": tr("Lobby")
        case "Matchmaking": tr("In queue")
        case "ReadyCheck": tr("Match found")
        case "ChampSelect": tr("Champ select")
        case "GameStart", "InProgress": tr("In game")
        case "Reconnect": tr("Reconnect")
        case "WaitingForStats", "PreEndOfGame": tr("Game over")
        case "EndOfGame": tr("Post-game")
        default: phase
        }
    }

    // MARK: Ready check

    private func handleReadyCheck(_ check: ReadyCheck) {
        guard check.state == "InProgress", check.playerResponse == "None" else {
            acceptScheduled = false
            return
        }
        if settings.soundAlerts { NSSound(named: "Glass")?.play(); NSApp.requestUserAttention(.criticalRequest) }
        guard settings.autoAccept, !acceptScheduled else { return }
        acceptScheduled = true
        let delay = settings.acceptDelay
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard acceptScheduled, settings.autoAccept else { return }
            await perform(tr("Match accepted")) { try await $0.post("/lol-matchmaking/v1/ready-check/accept") }
            acceptScheduled = false
        }
    }

    // MARK: Champ select

    private func handleChampSelect(_ session: ChampSelectSession) async {
        let previous = champSelect
        champSelect = session

        if let action = session.myActiveAction, action.id != lastPickTurnActionId {
            lastPickTurnActionId = action.id
            if settings.soundAlerts { NSSound(named: "Ping")?.play() }
            log(action.type == "ban" ? tr("Your turn to ban") : tr("Your turn to pick"))
        }

        if settings.scoutTeam, previous?.myTeam.map(\.puuid) != session.myTeam.map(\.puuid) || teamProfiles.isEmpty {
            Task { await scoutTeam(session.myTeam.compactMap(\.puuid).filter { !$0.isEmpty }) }
        }
        advisor.update(session, model: self)

        guard !isPreview, let me = session.me else { return }
        let locked = isLocked(session)
        let championId = (me.championId ?? 0) != 0 ? me.championId! : (settings.importOnHover ? (me.championPickIntent ?? 0) : 0)
        guard championId > 0, locked || settings.importOnHover else { return }

        let lane = Lane(clientPosition: me.assignedPosition)
        let key = "\(championId)-\(lane?.rawValue ?? "-")"
        guard key != lastImportKey else { return }
        lastImportKey = key
        await applyBuild(championId: championId, lane: lane)
    }

    private func isLocked(_ session: ChampSelectSession) -> Bool {
        let picks = session.actions?.joined().filter { $0.actorCellId == session.localPlayerCellId && $0.type == "pick" } ?? []
        if picks.isEmpty { return (session.me?.championId ?? 0) != 0 }
        return picks.contains { $0.completed == true }
    }

    /// Writes runes, spells and the item set for a champion into the client.
    func applyBuild(championId: Int, lane: Lane?) async {
        guard let client else { return }
        let mode = queueMode
        let tier: EloTier = settings.runeSource == .highElo ? .masterPlus : .emeraldPlus
        let build = try? await BuildService.opggBuild(championId: championId, lane: lane, mode: mode, tier: tier)
        let riot = (try? await BuildService.riotRecommended(client: client, championId: championId, lane: lane, mapId: mode.mapId)) ?? []
        let name = gameData.championName(championId)
        let preferred = settings.runeSource == .riot ? (riot.first ?? build?.runes.first) : (build?.runes.first ?? riot.first)

        if settings.autoRunes, let setup = preferred {
            await applyRunes(setup, championId: championId)
        }
        if settings.autoSpells, phase == "ChampSelect", let spells = build?.spells.first?.ids ?? preferred?.spells {
            await perform(tr("Summoner spells set")) { try await ClientActions.setSpells(spells, flashOnF: self.settings.flashOnF, client: $0) }
        }
        if settings.autoItemSets, let build, let summonerId = me?.summonerId {
            await perform(tr("Item set for %@ saved", name)) {
                try await ClientActions.importItemSet(build, championName: name, summonerId: summonerId, mapId: mode.mapId, client: $0)
            }
        }
    }

    func applyRunes(_ setup: RuneSetup, championId: Int) async {
        let name = gameData.championName(championId)
        await perform(tr("Runes for %@ (%@) imported", name, setup.source)) {
            try await ClientActions.importRunes(setup, championName: name, client: $0, allowOverwrite: self.settings.allowOverwritePage)
        }
    }

    private func scoutTeam(_ puuids: [String]) async {
        guard let client else { return }
        await withTaskGroup(of: PlayerProfile.self) { group in
            for puuid in puuids where teamProfiles[puuid] == nil {
                group.addTask { await self.scout.profile(puuid: puuid, client: client) }
            }
            for await profile in group { teamProfiles[profile.puuid] = profile }
        }
    }

    func profile(for puuid: String?) -> PlayerProfile? {
        puuid.flatMap { teamProfiles[$0] }
    }

    func lookupPlayer(riotId: String) async -> PlayerProfile? {
        guard let client else { return nil }
        let parts = riotId.split(separator: "#", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        guard let data = try? await client.request("POST", "/lol-summoner/v1/summoners/aliases",
                                                   json: [["gameName": parts[0], "tagLine": parts[1]]]),
              let found = try? jsonDecoder.decode([Summoner].self, from: data).first else {
            let encoded = riotId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? riotId
            guard let summoner: Summoner = try? await client.get("/lol-summoner/v1/summoners?name=\(encoded)") else { return nil }
            return await scout.profile(puuid: summoner.puuid, client: client)
        }
        return await scout.profile(puuid: found.puuid, client: client)
    }

    // MARK: Preview

    /// Opens the champ select window with a sample draft so it can be explored outside a game.
    func startPreview() {
        guard let me else { return log(tr("Connect to the client first"), .warning) }
        isPreview = true
        advisor.reset()
        let enemies = [238, 64, 51, 57, 25]
        let allies = [(266, "TOP"), (0, "MIDDLE"), (0, "JUNGLE"), (0, "BOTTOM"), (0, "UTILITY")]
        let myTeam = allies.enumerated().map { index, pair in
            ChampSelectPlayer(cellId: index, championId: pair.0, championPickIntent: nil, assignedPosition: pair.1,
                              puuid: index == 1 ? me.puuid : nil, gameName: index == 1 ? me.gameName : nil, tagLine: me.tagLine)
        }
        let theirTeam = enemies.enumerated().map { index, id in
            ChampSelectPlayer(cellId: 5 + index, championId: index < 3 ? id : 0, championPickIntent: nil, assignedPosition: nil)
        }
        let actions: [[ChampSelectAction]] = [
            [ChampSelectAction(id: 1, actorCellId: 5, championId: 157, completed: true, isInProgress: false, type: "ban"),
             ChampSelectAction(id: 2, actorCellId: 0, championId: 122, completed: true, isInProgress: false, type: "ban")],
            [ChampSelectAction(id: 3, actorCellId: 1, championId: 103, completed: false, isInProgress: true, type: "pick")],
        ]
        let session = ChampSelectSession(localPlayerCellId: 1, myTeam: myTeam, theirTeam: theirTeam, actions: actions,
                                         timer: ChampSelectTimer(phase: "BAN_PICK", adjustedTimeLeftInPhase: 90_000,
                                                                 internalNowInEpochMs: Date().timeIntervalSince1970 * 1000))
        champSelect = session
        teamProfiles = [:]
        Task { await scoutTeam([me.puuid]) }
        advisor.update(session, model: self)
    }

    /// Hovers the top suggestion in the preview draft.
    func previewHover() {
        guard isPreview, var session = champSelect else { return }
        let pick = advisor.suggestions.first?.championId ?? 103
        session.myTeam = session.myTeam.map { var p = $0; if p.cellId == 1 { p.championPickIntent = pick }; return p }
        champSelect = session
        advisor.update(session, model: self)
    }

    /// Locks the previewed champion to show the expanded build view.
    func previewLock() {
        guard isPreview, var session = champSelect else { return }
        let pick = session.me?.championPickIntent ?? advisor.suggestions.first?.championId ?? 103
        session.actions = session.actions?.map { $0.map { var a = $0; if a.id == 3 { a.completed = true; a.isInProgress = false; a.championId = pick }; return a } }
        session.myTeam = session.myTeam.map { var p = $0; if p.cellId == 1 { p.championId = pick }; return p }
        champSelect = session
        advisor.update(session, model: self)
    }

    func endPreview() {
        isPreview = false
        champSelect = nil
        advisor.reset()
    }

    // MARK: Live game

    private func startLiveTracking() {
        guard liveTask == nil else { return }
        liveTask = Task {
            while !Task.isCancelled {
                if let data = try? await LiveClient.allGameData() {
                    live = LiveGameAnalyzer.analyze(data, items: gameData.items)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopLiveTracking() {
        liveTask?.cancel()
        liveTask = nil
        live = nil
    }

    // MARK: Tools

    /// Runs a client call and logs its outcome.
    func perform(_ success: String, _ action: @escaping (LCUClient) async throws -> Void) async {
        guard let client else { return log(tr("Client is not connected"), .warning) }
        do {
            try await action(client)
            log(success, .success)
        } catch {
            log(tr("%@ failed: %@", success, error.localizedDescription), .warning)
        }
    }

    func log(_ text: String, _ kind: LogEntry.Kind = .info) {
        logs.insert(LogEntry(text: text, kind: kind), at: 0)
        if logs.count > 200 { logs.removeLast() }
    }
}
