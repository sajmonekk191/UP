import Foundation

/// Read-only smoke test of every data source, run with `--selftest`.
@MainActor
enum SelfTest {
    static func run() async -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print(ok ? "✅" : "❌", name, detail)
            if !ok { failures += 1 }
        }

        guard let credentials = LockfileLocator.find() else {
            check("Client found", false)
            return 1
        }
        check("Client found", true, "port \(credentials.port)")
        let client = LCUClient(credentials: credentials)

        let me: Summoner? = try? await client.get("/lol-summoner/v1/current-summoner")
        check("Current summoner", me != nil, me?.riotId ?? "")

        let data = GameData()
        await data.load(using: client)
        check("Game data", data.isLoaded, "\(data.champions.count) champs, \(data.perks.count) runes, \(data.items.count) items, \(data.spells.count) spells")

        let phase: String? = try? await client.get("/lol-gameflow/v1/gameflow-phase")
        check("Gameflow phase", phase != nil, phase ?? "")

        if let me {
            let profile = await PlayerScout().profile(puuid: me.puuid, client: client)
            check("Player profile", profile.summoner != nil, "\(profile.solo?.label ?? "-"), \(profile.recent.count) games, tags: \(profile.tags.map(\.text))")

            let aliases = try? await client.request("POST", "/lol-summoner/v1/summoners/aliases",
                                                    json: [["gameName": me.gameName ?? "", "tagLine": me.tagLine ?? ""]])
            let found = aliases.flatMap { try? jsonDecoder.decode([Summoner].self, from: $0) }?.first
            check("Lookup by Riot ID", found?.puuid == me.puuid, found?.riotId ?? "")
            let masteries: [ChampionMastery]? = try? await client.get("/lol-champion-mastery/v1/local-player/champion-mastery")
            check("Mastery", masteries != nil, "\(masteries?.count ?? 0) champions")
            check("Mastery by PUUID", !profile.masteries.isEmpty, "top: \(data.championName(profile.masteries.first?.championId))")
            let a = profile.averages
            check("Player averages", true, String(format: "CS/min %.1f, dmg/min %.0f, role %@", a.csPerMin, a.damagePerMin, profile.roleShares.map(\.lane.title).description))
            if let gameId = profile.recent.first?.gameId {
                let game = await PlayerScout().game(gameId, client: client)
                check("Match detail", (game?.participants?.count ?? 0) > 1, "\(game?.participants?.count ?? 0) players, \(game?.teams?.count ?? 0) teams")
            }
        }

        do {
            let build = try await BuildService.opggBuild(championId: 103, lane: .middle, mode: .ranked)
            check("op.gg build (Ahri mid)", !build.runes.isEmpty,
                  "WR \(percent(build.winRate)), \(build.runes.count) rune sets, core \(build.coreItems.first?.ids ?? []), skill \(build.skillOrder?.priority ?? [])")
            let aram = try await BuildService.opggBuild(championId: 103, lane: nil, mode: .aram)
            check("op.gg build (ARAM)", !aram.runes.isEmpty, "\(aram.runes.count) rune sets")
            let arena = try await BuildService.opggBuild(championId: 103, lane: nil, mode: .arena)
            check("op.gg build (Arena)", !arena.augments.isEmpty, "\(arena.augments.count) augments, top 4 \(percent(arena.winRate)), avg place \(arena.averagePlace.map { decimal($0, 2) } ?? "-")")
            let urf = try await BuildService.opggBuild(championId: 103, lane: nil, mode: .urf)
            check("op.gg build (URF)", !urf.runes.isEmpty, "\(urf.runes.count) rune sets, patch \(urf.patch ?? "-")")
        } catch {
            check("op.gg build", false, error.localizedDescription)
        }

        do {
            let main = try await BuildService.opggBuild(championId: 103, lane: nil, mode: .ranked)
            check("op.gg main lane", main.lane == .middle, "\(main.lane?.title ?? "-"), trend \(main.patchTrend.count) patches, lengths \(main.gameLengths.count)")
        } catch {
            check("op.gg main lane", false, error.localizedDescription)
        }
        let detail = await data.detail(103, client: client)
        check("Champion detail", detail?.spells.count == 4, "\(detail?.title ?? ""), splash \(detail?.splashPath != nil)")

        let riot = try? await BuildService.riotRecommended(client: client, championId: 103, lane: .middle, mapId: 11)
        check("Riot recommended runes", !(riot ?? []).isEmpty, riot?.first.map { "\($0.title) \($0.perkIds)" } ?? "")

        let tiers = try? await BuildService.tierList()
        check("Tier list", (tiers?.count ?? 0) > 100, "\(tiers?.count ?? 0) entries")
        for query in [TierListQuery(flex: true, region: .eune, rank: .masterPlus), TierListQuery(mode: .aram), TierListQuery(mode: .arena), TierListQuery(mode: .urf)] {
            let list = try? await BuildService.tierList(for: query)
            let name = "\(query.mode.title)\(query.flex ? " Flex" : "")\(query.region.map { " \($0.code)" } ?? "")"
            check("Tier list (\(name))", (list?.entries.count ?? 0) > 100, "\(list?.entries.count ?? 0) entries, patch \(list?.patch ?? "-")")
        }

        let accounts = try? await OpggAccounts.search("faker", region: .euw)
        check("op.gg account search", !(accounts ?? []).isEmpty, "\(accounts?.count ?? 0) accounts named faker on EUW")
        let remote = try? await OpggAccounts.profile(PlayerQuery(riotId: "Hide on bush#KR1", region: .kr))
        check("op.gg profile (KR)", (remote?.recent.count ?? 0) > 0, "\(remote?.solo?.label ?? "-"), \(remote?.recent.count ?? 0) games")

        let socket = LCUWebSocket(credentials: credentials)
        let connected = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    for try await _ in socket.events(for: ["/lol-gameflow/v1/gameflow-phase"]) { return true }
                    return true
                } catch { return false }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return true
            }
            let result = await group.next() ?? false
            group.cancelAll()
            socket.close()
            return result
        }
        check("WebSocket", connected)

        if let live = try? await LiveClient.allGameData() {
            let snapshot = LiveGameAnalyzer.analyze(live, items: data.items)
            check("Live Client", true, "time \(formatTime(snapshot.gameTime)), \(snapshot.players.count) players")
        } else {
            print("ℹ️  Live Client: no game running (fine)")
        }

        print(failures == 0 ? "\nAll OK" : "\n\(failures) failures")
        return failures == 0 ? 0 : 1
    }
}
