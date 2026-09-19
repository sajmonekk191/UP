import Foundation

/// League server, named the way op.gg addresses it.
enum Region: String, CaseIterable, Identifiable, Sendable {
    case eune, euw, na, kr, br, lan, las, oce, turkey = "tr", ru, jp, me, sg, ph, th, tw, vn

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }

    var title: String {
        switch self {
        case .eune: tr("Europe Nordic & East")
        case .euw: tr("Europe West")
        case .na: tr("North America")
        case .kr: tr("Korea")
        case .br: tr("Brazil")
        case .lan: tr("Latin America North")
        case .las: tr("Latin America South")
        case .oce: tr("Oceania")
        case .turkey: tr("Turkey")
        case .ru: tr("Russia")
        case .jp: tr("Japan")
        case .me: tr("Middle East")
        case .sg: tr("Singapore")
        case .ph: tr("Philippines")
        case .th: tr("Thailand")
        case .tw: tr("Taiwan")
        case .vn: tr("Vietnam")
        }
    }
}

/// A player to open: their Riot ID and the server they play on.
struct PlayerQuery: Hashable, Sendable {
    var riotId: String
    var region: Region

    /// Parses "eune|Name#TAG"; entries saved before regions existed fall back to `region`.
    init?(stored: String, fallback region: Region) {
        let parts = stored.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let saved = Region(rawValue: parts[0]) {
            self.init(riotId: parts[1], region: saved)
        } else if !stored.isEmpty {
            self.init(riotId: stored, region: region)
        } else {
            return nil
        }
    }

    init(riotId: String, region: Region) {
        self.riotId = riotId
        self.region = region
    }

    var stored: String { "\(region.rawValue)|\(riotId)" }
}

/// Account found by name on a server, with its level, solo rank and pro identity.
struct AccountHit: Identifiable, Hashable, Sendable {
    var puuid: String
    var gameName: String
    var tagLine: String
    var level: Int?
    var iconURL: String?
    var tier: String?
    var rank: String?
    var pro: String?

    var id: String { puuid }
    var riotId: String { "\(gameName)#\(tagLine)" }
}

/// Account search and full profiles on any server through op.gg's public summoner API.
enum OpggAccounts {
    private static let base = "https://lol-api-summoner.op.gg/api/v3"

    /// Accounts named `name` on the server, ten per page; `Name#TAG` finds that one account.
    static func search(_ name: String, region: Region, page: Int = 1) async throws -> [AccountHit] {
        var components = URLComponents(string: "\(base)/\(region.rawValue)/summoners")!
        components.queryItems = [.init(name: "riot_id", value: name), .init(name: "hl", value: "en_US"), .init(name: "page", value: String(page))]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return try jsonDecoder.decode(OpggEnvelope<[OpggSummoner]>.self, from: data).data.compactMap(\.hit)
    }

    /// Rank, recent form and the last 20 games with every player, shaped like a client profile.
    static func profile(_ query: PlayerQuery) async throws -> PlayerProfile? {
        guard let account = try await search(query.riotId, region: query.region).first else { return nil }
        async let summary: OpggEnvelope<OpggSummary> = get("\(account.puuid)/summary", region: query.region)
        async let games: OpggEnvelope<[OpggGame]> = get("\(account.puuid)/games?limit=20&hl=en_US&game_type=total", region: query.region)
        let owner = try await summary.data.summoner
        let recent = try await games.data.compactMap { $0.history(focus: account.puuid) }
        let league = Dictionary((owner.league_stats ?? []).map { ($0.game_type ?? "", $0) }, uniquingKeysWith: { a, _ in a })
        let previous = owner.previous_seasons?.first?.tier_info
        var profile = PlayerProfile(
            puuid: account.puuid,
            summoner: .init(puuid: account.puuid, gameName: owner.game_name ?? account.gameName, tagLine: owner.tagline ?? account.tagLine,
                            summonerLevel: owner.level ?? account.level, profileIconId: iconId(owner.profile_image_url)),
            solo: league["SOLORANKED"].map { $0.queue(previous: previous) },
            flex: league["FLEXRANKED"].map { $0.queue(previous: nil) },
            recent: recent,
            champions: PlayerScout.championRecords(recent.contains(where: \.isCountable) ? recent.filter(\.isCountable) : recent))
        profile.region = query.region
        profile.seasonChampions = (owner.most_champions?.champion_stats ?? []).map {
            .init(championId: $0.id, games: $0.play ?? 0, wins: $0.win ?? 0, kills: $0.kill ?? 0, deaths: $0.death ?? 0, assists: $0.assist ?? 0)
        }
        profile.tags = PlayerScout.tags(for: profile)
        return profile
    }

    /// The player's games that ended before `endedBefore` (ISO 8601), newest first, twenty at most.
    static func games(puuid: String, region: Region, endedBefore: String) async throws -> [HistoryGame] {
        let date = endedBefore.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? endedBefore
        let page: OpggEnvelope<[OpggGame]> = try await get("\(puuid)/games?limit=20&hl=en_US&game_type=total&ended_at=\(date)", region: region)
        return page.data.compactMap { $0.history(focus: puuid) }
    }

    private static func get<T: Decodable>(_ path: String, region: Region) async throws -> T {
        let url = URL(string: "\(base)/\(region.rawValue)/summoners/\(path)\(path.contains("?") ? "" : "?hl=en_US")")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try jsonDecoder.decode(T.self, from: data)
    }

    static func iconId(_ url: String?) -> Int? {
        guard let url, let range = url.range(of: #"profileIcon(\d+)"#, options: .regularExpression) else { return nil }
        return Int(url[range].dropFirst("profileIcon".count))
    }

    static func division(_ number: Int?) -> String? {
        guard let number, (1...4).contains(number) else { return nil }
        return ["I", "II", "III", "IV"][number - 1]
    }
}

// MARK: - op.gg payload

private struct OpggEnvelope<T: Decodable>: Decodable { var data: T }

private struct OpggTierInfo: Decodable { var tier: String?; var division: Int?; var lp: Int? }

private struct OpggSummoner: Decodable {
    struct Player: Decodable {
        struct Career: Decodable { struct Team: Decodable { var acronym: String? }; var pro_team: Team? }
        var nickname: String?
        var current_pro_team: Career?
    }
    var puuid: String?
    var game_name: String?
    var tagline: String?
    var level: Int?
    var profile_image_url: String?
    var solo_tier_info: OpggTierInfo?
    var player: Player?

    var hit: AccountHit? {
        guard let puuid, let game_name, let tagline else { return nil }
        let tier = solo_tier_info?.tier
        let rank = tier.map { tier in
            let name = tier.prefix(1) + tier.dropFirst().lowercased()
            let division = ["MASTER", "GRANDMASTER", "CHALLENGER"].contains(tier) ? "" : OpggAccounts.division(solo_tier_info?.division).map { " \($0)" } ?? ""
            return "\(name)\(division) · \(solo_tier_info?.lp ?? 0) LP"
        }
        let pro = player?.nickname.map { nickname in [player?.current_pro_team?.pro_team?.acronym, nickname].compactMap { $0 }.joined(separator: " ") }
        return AccountHit(puuid: puuid, gameName: game_name, tagLine: tagline, level: level, iconURL: profile_image_url,
                          tier: tier, rank: rank, pro: pro)
    }
}

private struct OpggSummary: Decodable {
    struct Owner: Decodable {
        struct League: Decodable {
            var game_type: String?
            var tier_info: OpggTierInfo?
            var win: Int?
            var lose: Int?

            func queue(previous: OpggTierInfo?) -> RankedQueue {
                RankedQueue(tier: tier_info?.tier, division: OpggAccounts.division(tier_info?.division), leaguePoints: tier_info?.lp,
                            wins: win, losses: lose, previousSeasonEndTier: previous?.tier,
                            previousSeasonEndDivision: OpggAccounts.division(previous?.division))
            }
        }
        struct Season: Decodable { var tier_info: OpggTierInfo? }
        struct Champions: Decodable {
            struct Stat: Decodable { var id: Int; var play: Int?; var win: Int?; var kill: Int?; var death: Int?; var assist: Int? }
            var champion_stats: [Stat]?
        }
        var game_name: String?
        var tagline: String?
        var level: Int?
        var profile_image_url: String?
        var league_stats: [League]?
        var previous_seasons: [Season]?
        var most_champions: Champions?
    }
    var summoner: Owner
}

private struct OpggGame: Decodable {
    struct Team: Decodable {
        struct Stat: Decodable {
            var is_win: Bool?
            var tower_kill: Int?, dragon_kill: Int?, horde_kill: Int?, rift_herald_kill: Int?, baron_kill: Int?
        }
        var key: String
        var game_stat: Stat?
    }
    struct Participant: Decodable {
        struct Account: Decodable { var puuid: String?; var game_name: String?; var tagline: String? }
        struct Rune: Decodable { var primary_rune_id: Int?; var secondary_page_id: Int? }
        struct Stats: Decodable {
            var kill: Int?, death: Int?, assist: Int?, champion_level: Int?, minion_kill: Int?, neutral_minion_kill: Int?
            var gold_earned: Int?, total_damage_dealt_to_champions: Int?, total_damage_taken: Int?, damage_self_mitigated: Int?
            var damage_dealt_to_objectives: Int?, vision_score: Int?, largest_killing_spree: Int?, largest_multi_kill: Int?, turret_kill: Int?
            var result: String?
        }
        var participant_id: Int?
        var champion_id: Int
        var team_key: String?
        var position: String?
        var items: [Int]?
        var trinket_item: Int?
        var spells: [Int]?
        var rune: Rune?
        var stats: Stats?
        var summoner: Account?
    }
    var id: String
    var created_at: String?
    var game_length_second: Int?
    var game_type: String?
    var game_map: String?
    var queue_id: Int?
    var participants: [Participant]
    var teams: [Team]?

    /// The game in the client's match-history shape, with the focused player first.
    func history(focus puuid: String) -> HistoryGame? {
        let teamIds = Dictionary((teams ?? []).enumerated().map { index, team in
            (team.key, team.key == "BLUE" ? 100 : team.key == "RED" ? 200 : 100 * (index + 1))
        }, uniquingKeysWith: { a, _ in a })
        let ordered = participants.sorted { a, b in a.summoner?.puuid == puuid && b.summoner?.puuid != puuid }
        guard ordered.first?.summoner?.puuid == puuid else { return nil }
        let mode = game_map == "HOWLING_ABYSS" ? "ARAM" : (game_map ?? "").hasPrefix("ARENA") || game_type == "ARENA" ? "CHERRY" : "CLASSIC"
        let ended = created_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        return HistoryGame(
            gameId: Self.stableId(id), gameCreation: ended.map { ($0.timeIntervalSince1970 - Double(game_length_second ?? 0)) * 1000 }, gameDuration: game_length_second,
            gameMode: mode, gameType: "MATCHED_GAME", queueId: queue_id,
            participants: ordered.enumerated().map { index, p in
                let s = p.stats
                let multi = s?.largest_multi_kill ?? 0
                let items = (p.items ?? []) + [p.trinket_item ?? 0]
                func item(_ slot: Int) -> Int? { items.indices.contains(slot) ? items[slot] : nil }
                return HistoryParticipant(
                    participantId: p.participant_id ?? index + 1, teamId: teamIds[p.team_key ?? ""],
                    championId: p.champion_id, spell1Id: p.spells?.first, spell2Id: p.spells?.dropFirst().first,
                    stats: HistoryStats(win: s?.result == "WIN", kills: s?.kill, deaths: s?.death, assists: s?.assist,
                                        champLevel: s?.champion_level, totalMinionsKilled: s?.minion_kill, neutralMinionsKilled: s?.neutral_minion_kill,
                                        goldEarned: s?.gold_earned, totalDamageDealtToChampions: s?.total_damage_dealt_to_champions,
                                        visionScore: s?.vision_score, totalDamageTaken: s?.total_damage_taken, damageSelfMitigated: s?.damage_self_mitigated,
                                        damageDealtToObjectives: s?.damage_dealt_to_objectives, largestKillingSpree: s?.largest_killing_spree,
                                        tripleKills: multi == 3 ? 1 : 0, quadraKills: multi == 4 ? 1 : 0, pentaKills: multi >= 5 ? 1 : 0,
                                        turretKills: s?.turret_kill,
                                        item0: item(0), item1: item(1), item2: item(2), item3: item(3), item4: item(4), item5: item(5), item6: item(6),
                                        perk0: p.rune?.primary_rune_id, perkSubStyle: p.rune?.secondary_page_id),
                    timeline: Self.timeline(p.position))
            },
            participantIdentities: ordered.enumerated().map { index, p in
                ParticipantIdentity(participantId: p.participant_id ?? index + 1,
                                    player: .init(puuid: p.summoner?.puuid, gameName: p.summoner?.game_name, tagLine: p.summoner?.tagline))
            },
            teams: (teams ?? []).map { team in
                HistoryTeam(teamId: teamIds[team.key] ?? 0, win: team.game_stat?.is_win == true ? "Win" : "Fail",
                            baronKills: team.game_stat?.baron_kill, dragonKills: team.game_stat?.dragon_kill, towerKills: team.game_stat?.tower_kill,
                            riftHeraldKills: team.game_stat?.rift_herald_kill, hordeKills: team.game_stat?.horde_kill)
            })
    }

    private static func timeline(_ position: String?) -> HistoryParticipant.Timeline? {
        switch position {
        case "TOP": .init(lane: "TOP", role: "SOLO")
        case "JUNGLE": .init(lane: "JUNGLE", role: "NONE")
        case "MID": .init(lane: "MIDDLE", role: "SOLO")
        case "ADC": .init(lane: "BOTTOM", role: "CARRY")
        case "SUPPORT": .init(lane: "BOTTOM", role: "SUPPORT")
        default: nil
        }
    }

    /// Same number for the same op.gg game id on every launch.
    private static func stableId(_ id: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: hash & 0x3FFF_FFFF_FFFF_FFFF)
    }
}
