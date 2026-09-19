import AppKit
import Foundation

enum ConnectionState: Equatable {
    case searching
    case connected
}

/// Short message shown in the main window after an action or a connection change.
struct Notice: Identifiable, Equatable {
    enum Kind { case info, success, warning }
    let id = UUID()
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
    let hud = HUDState()
    private let scout = PlayerScout()
    private let archive = MatchArchive()

    private(set) var connection: ConnectionState = .searching
    private(set) var client: LCUClient?
    private(set) var me: Summoner?
    private(set) var clientRegion: Region?
    private(set) var myProfile: PlayerProfile?
    private(set) var myMasteries: [ChampionMastery] = []
    private(set) var myPerformance: [Int: GamePerformance] = [:]
    private(set) var isGrading = false
    private(set) var olderMatches: [HistoryGame] = []
    private(set) var isLoadingOlder = false
    private(set) var olderExhausted = false
    @ObservationIgnored private var opggPuuids: [String: String] = [:]
    @ObservationIgnored private var detailCache: [Int: HistoryGame] = [:]
    private var refreshes = 0
    private(set) var phase = "None"
    private(set) var notices: [Notice] = []

    private(set) var champSelect: ChampSelectSession?
    private(set) var teamProfiles: [String: PlayerProfile] = [:]
    private(set) var gameSession: GameflowSession?
    private(set) var live: LiveGameSnapshot?
    private(set) var isPreview = false
    private(set) var isHUDPreview = false
    private(set) var friends: [Friend] = []
    private var recentPlayerKeys: [String] = UserDefaults.standard.stringArray(forKey: "recentPlayers") ?? []
    var hudMode: HUDMode = .hud
    var hudClosed = false

    private var liveTask: Task<Void, Never>?
    private var lastImportKey: String?
    private var lastPickTurnActionId: Int?
    private var acceptScheduled = false

    var mapId: Int { gameSession?.map?.id ?? (gameSession?.gameData?.queue?.gameMode == "ARAM" ? 12 : 11) }
    var queueMode: QueueMode { mapId == 12 ? .aram : .ranked }
    var isInChampSelect: Bool { champSelect != nil && (phase == "ChampSelect" || isPreview) }
    /// Server the search bar looks up accounts on: the one picked in the search bar, else the client's.
    var searchRegion: Region { settings.searchRegion ?? clientRegion ?? .euw }
    var recentPlayers: [PlayerQuery] { recentPlayerKeys.compactMap { PlayerQuery(stored: $0, fallback: clientRegion ?? .eune) } }
    var myQuery: PlayerQuery? { me.map { PlayerQuery(riotId: $0.riotId, region: clientRegion ?? .eune) } }
    var isRefreshing: Bool { refreshes > 0 }

    // MARK: Connection

    func start() {
        Task { await connectionLoop() }
    }

    private func connectionLoop() async {
        while true {
            if let credentials = LockfileLocator.find() {
                await run(credentials)
                notify(tr("Lost connection to the client, searching again…"), .warning)
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
        notify(tr("Connected as %@", summoner.riotId), .success)

        Task { await refreshMyProfile() }
        clientRegion = (try? await client.get("/riotclient/region-locale") as RegionLocale)?.webRegion.flatMap(Region.init(rawValue:))
        if !gameData.isLoaded { await gameData.load(using: client) }
        await refreshPhase()
        Task { friends = (try? await client.get("/lol-chat/v1/friends")) ?? [] }

        let socket = LCUWebSocket(credentials: credentials)
        do {
            for try await event in socket.events(for: Self.eventURIs) { await handle(event) }
        } catch {}
        stopLiveTracking()
    }

    func refreshMyProfile() async {
        guard let client, let me else { return }
        refreshes += 1
        defer { refreshes -= 1 }
        await scout.invalidate()
        async let masteries: [ChampionMastery]? = try? client.get("/lol-champion-mastery/v1/local-player/champion-mastery")
        myProfile = await scout.profile(puuid: me.puuid, client: client, historyCount: 20)
        myMasteries = await masteries ?? []
        olderMatches = []
        olderExhausted = false
        if let recent = myProfile?.recent, !recent.isEmpty { await archive.add(recent, puuid: me.puuid) }
        isGrading = true
        myPerformance = await scout.performances(of: myProfile?.recent ?? [], puuid: me.puuid, client: client)
        await cacheDetails(of: myProfile?.recent ?? [])
        isGrading = false
    }

    /// Full match already loaded for this game, so its details can open without waiting.
    func cachedMatchDetail(_ gameId: Int) -> HistoryGame? { detailCache[gameId] }

    private func cacheDetails(of games: [HistoryGame]) async {
        detailCache.merge(await scout.details(for: games.map(\.gameId))) { _, new in new }
    }

    /// Adds the next twenty older matches of the signed-in player, from UP!'s own archive and op.gg, graded like the recent ones.
    func loadOlderMatches() async {
        guard let client, let me, let recent = myProfile?.recent, !isLoadingOlder, !olderExhausted else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        let shown = recent + olderMatches
        let oldest = shown.compactMap(\.gameCreation).min() ?? Date().timeIntervalSince1970 * 1000
        let archived = await archive.games(before: oldest, puuid: me.puuid, limit: 20)
        let remote = await opggGames(before: oldest, riotId: me.riotId).filter { game in !(shown + archived).contains { $0.isSame(as: game) } }
        let page = Array((archived + remote).sorted { ($0.gameCreation ?? 0) > ($1.gameCreation ?? 0) }.prefix(20))
        guard !page.isEmpty else { olderExhausted = true; return }
        var graded = await scout.performances(of: page.filter { $0.participants?.count == 1 }, puuid: me.puuid, client: client)
        await cacheDetails(of: page)
        for game in page where graded[game.id] == nil {
            graded[game.id] = GamePerformance(game: game, puuid: game.identity(for: game.me?.participantId)?.puuid)
        }
        olderMatches += page
        myPerformance.merge(graded) { current, _ in current }
    }

    /// Matches of the signed-in player that op.gg saw end before `time`; empty when op.gg does not know the account.
    private func opggGames(before time: Double, riotId: String) async -> [HistoryGame] {
        guard let region = clientRegion else { return [] }
        let key = "\(region.rawValue)|\(riotId)"
        if opggPuuids[key] == nil { opggPuuids[key] = try? await OpggAccounts.search(riotId, region: region).first?.puuid }
        guard let opggPuuid = opggPuuids[key] else { return [] }
        let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: time / 1000))
        return (try? await OpggAccounts.games(puuid: opggPuuid, region: region, endedBefore: date)) ?? []
    }

    private func refreshPhase() async {
        guard let client else { return }
        if let phase: String = try? await client.get("/lol-gameflow/v1/gameflow-phase") { await setPhase(phase) }
        if let session: ChampSelectSession = try? await client.get("/lol-champ-select/v1/session") {
            await handleChampSelect(session)
        }
    }

    // MARK: Events

    private static let eventURIs = ["/lol-gameflow/v1/gameflow-phase", "/lol-matchmaking/v1/ready-check",
                                    "/lol-champ-select/v1/session", "/lol-summoner/v1/current-summoner"]

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
            Task { await scoutGamePlayers() }
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

    private func scoutGamePlayers() async {
        let players = (gameSession?.gameData?.teamOne ?? []) + (gameSession?.gameData?.teamTwo ?? [])
        await scoutTeam(players.compactMap(\.puuid).filter { !$0.isEmpty })
    }

    func profile(for puuid: String?) -> PlayerProfile? {
        puuid.flatMap { teamProfiles[$0] }
    }

    /// Remembers a successfully looked-up player for search suggestions.
    func rememberPlayer(_ query: PlayerQuery) {
        var list = recentPlayers.filter { $0.region != query.region || $0.riotId.caseInsensitiveCompare(query.riotId) != .orderedSame }
        list.insert(query, at: 0)
        recentPlayerKeys = list.prefix(12).map(\.stored)
        UserDefaults.standard.set(recentPlayerKeys, forKey: "recentPlayers")
    }

    /// Profile of a player on any server, from op.gg.
    func remoteProfile(_ query: PlayerQuery) async -> PlayerProfile? {
        await scout.remoteProfile(query)
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
        guard let me else { return notify(tr("Connect to the client first"), .warning) }
        isPreview = true
        advisor.reset()
        let enemies = [238, 64, 51, 57, 25]
        let allies = [(266, "TOP"), (0, "MIDDLE"), (0, "JUNGLE"), (0, "BOTTOM"), (0, "UTILITY")]
        let myTeam = allies.enumerated().map { index, pair in
            ChampSelectPlayer(cellId: index, championId: pair.0, championPickIntent: nil, assignedPosition: pair.1,
                              puuid: index == 1 ? me.puuid : nil, gameName: index == 1 ? me.gameName : nil)
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
                                         timer: ChampSelectTimer(adjustedTimeLeftInPhase: 90_000,
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
        hud.reset()
        hudClosed = false
        hudMode = .hud
        liveTask = Task {
            var lastError: String?
            while !Task.isCancelled {
                do {
                    let data = try await LiveClient.allGameData()
                    lastError = nil
                    if data.gameData.gameTime > 1 {
                        let snapshot = LiveGameAnalyzer.analyze(data, items: gameData.items)
                        live = snapshot
                        hud.ingest(snapshot, model: self)
                    }
                } catch is DecodingError {
                    let message = tr("Game data could not be read, the HUD is paused")
                    if lastError != message { notify(message, .warning); lastError = message }
                } catch {}
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopLiveTracking() {
        liveTask?.cancel()
        liveTask = nil
        live = nil
        isHUDPreview = false
        hud.reset()
    }

    /// Runs a scripted sample game through the in-game HUD for about a minute.
    func startHUDPreview() {
        guard liveTask == nil || isHUDPreview else { return notify(tr("A game is running, the HUD is already live"), .info) }
        liveTask?.cancel()
        isHUDPreview = true
        hudMode = .hud
        hud.reset()
        liveTask = Task {
            for elapsed in 0..<75 {
                guard !Task.isCancelled else { return }
                let snapshot = LiveGameAnalyzer.analyze(HUDPreview.data(elapsed: Double(elapsed)), items: gameData.items)
                live = snapshot
                hud.ingest(snapshot, model: self)
                try? await Task.sleep(for: .seconds(1))
            }
            stopLiveTracking()
        }
    }

    func endHUDPreview() {
        guard isHUDPreview else { return }
        stopLiveTracking()
    }

    // MARK: Tools

    /// Runs a client call and reports its outcome.
    func perform(_ success: String, _ action: @escaping (LCUClient) async throws -> Void) async {
        guard let client else { return notify(tr("Client is not connected"), .warning) }
        do {
            try await action(client)
            notify(success, .success)
        } catch {
            notify(tr("%@ failed: %@", success, error.localizedDescription), .warning)
        }
    }

    /// Shows a message in the main window for a few seconds.
    func notify(_ text: String, _ kind: Notice.Kind = .info) {
        notices.removeAll { $0.text == text }
        let notice = Notice(text: text, kind: kind)
        notices.append(notice)
        if notices.count > 3 { notices.removeFirst(notices.count - 3) }
        Task {
            try? await Task.sleep(for: .seconds(kind == .warning ? 6 : 4))
            notices.removeAll { $0.id == notice.id }
        }
    }

    /// Full details of one match, cached after the first load.
    func matchDetail(_ gameId: Int) async -> HistoryGame? {
        guard let client else { return nil }
        let game = await scout.game(gameId, client: client)
        detailCache[gameId] = game
        return game
    }

    /// Grades another player's recent games against everyone in each match.
    func performances(for profile: PlayerProfile) async -> [Int: GamePerformance] {
        guard let client else { return [:] }
        let graded = await scout.performances(of: profile.recent, puuid: profile.puuid, client: client)
        await cacheDetails(of: profile.recent)
        return graded
    }
}

private extension HistoryGame {
    /// Whether two records from different sources describe the same match.
    func isSame(as other: HistoryGame) -> Bool {
        guard let start = gameCreation, let otherStart = other.gameCreation, me?.championId == other.me?.championId else { return false }
        return abs(start - otherStart) < 180_000 && abs((gameDuration ?? 0) - (other.gameDuration ?? 0)) < 60
    }
}
