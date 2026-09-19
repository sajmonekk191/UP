import Foundation

/// How well one player did in a match, scored 0–10 against everyone else in the lobby.
struct GamePerformance: Sendable, Hashable {
    enum Grade: String, Sendable {
        case sPlus = "S+", s = "S", a = "A", b = "B", c = "C", d = "D"

        init(score: Double) {
            switch score {
            case 8.5...: self = .sPlus
            case 7.5...: self = .s
            case 6.3...: self = .a
            case 5...: self = .b
            case 3.8...: self = .c
            default: self = .d
            }
        }
    }

    enum Badge: Sendable, Hashable {
        case mvp, ace, pentakill, quadraKill, tripleKill, perfectKDA, legendary, firstBlood
        case topDamage, teamPlayer, demolisher, frontline, topVision, mostCS
    }

    var score: Double?
    var rank: Int?
    var players = 1
    var killParticipation: Double?
    var badges: [Badge] = []

    var grade: Grade? { score.map(Grade.init(score:)) }

    /// Grades the player with `puuid` in a match; nil when they are not part of it.
    init?(game: HistoryGame, puuid: String?) {
        let everyone = game.participants ?? []
        let myId = game.participantIdentities?.first { $0.player.puuid == puuid }?.participantId
        guard let me = everyone.first(where: { $0.participantId == myId }) ?? (everyone.count == 1 ? everyone.first : nil) else { return nil }
        let lobby = Lobby(game: game)
        let team = everyone.filter { $0.teamId == me.teamId }
        let teamKills = team.reduce(0) { $0 + ($1.stats.kills ?? 0) }
        let s = me.stats
        players = everyone.count
        if team.count > 1, teamKills > 0 {
            killParticipation = Double((s.kills ?? 0) + (s.assists ?? 0)) / Double(teamKills)
        }

        if everyone.count > 1 {
            let scores = Self.rankedScores(lobby)
            let mine = scores.first { $0.id == me.participantId }?.score ?? 0
            score = mine
            rank = (scores.firstIndex { $0.id == me.participantId } ?? 0) + 1
            let bestOnTeam = !scores.contains { entry in entry.score > mine && team.contains { $0.participantId == entry.id } }
            if rank == 1, players >= 4 {
                badges.append(.mvp)
            } else if lobby.hasResult, s.win != true, team.count >= 3, bestOnTeam {
                badges.append(.ace)
            }
        }

        if (s.pentaKills ?? 0) > 0 {
            badges.append(.pentakill)
        } else if (s.quadraKills ?? 0) > 0 {
            badges.append(.quadraKill)
        } else if (s.tripleKills ?? 0) > 0 {
            badges.append(.tripleKill)
        }
        if (s.deaths ?? 0) == 0, (s.kills ?? 0) + (s.assists ?? 0) >= 3 { badges.append(.perfectKDA) }
        if (s.largestKillingSpree ?? 0) >= 8 { badges.append(.legendary) }
        if s.firstBloodKill == true { badges.append(.firstBlood) }
        if players >= 4, lobby.leads(me, in: .damage) { badges.append(.topDamage) }
        if let kp = killParticipation, kp >= 0.7, team.count >= 3, teamKills >= 10 { badges.append(.teamPlayer) }
        if (s.turretKills ?? 0) >= 3 { badges.append(.demolisher) }
        if players >= 6, lobby.leads(me, in: .tanking) { badges.append(.frontline) }
        if players >= 6, (s.visionScore ?? 0) >= 10, lobby.leads(me, in: .vision) { badges.append(.topVision) }
        if players >= 6, !lobby.isARAM, !lobby.isArena, lobby.leads(me, in: .cs) { badges.append(.mostCS) }
    }
}

extension GamePerformance {
    /// Grades of a profile whose games already include every player, keyed by game id.
    static func all(in profile: PlayerProfile) -> [Int: GamePerformance] {
        Dictionary(profile.recent.compactMap { game in GamePerformance(game: game, puuid: profile.puuid).map { (game.gameId, $0) } },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Score of every participant of a full match, keyed by participant id.
    static func scores(in game: HistoryGame) -> [Int: Double] {
        guard (game.participants?.count ?? 0) > 1 else { return [:] }
        return Dictionary(rankedScores(Lobby(game: game)).compactMap { entry in entry.id.map { ($0, entry.score) } },
                          uniquingKeysWith: { a, _ in a })
    }

    fileprivate static func rankedScores(_ lobby: Lobby) -> [(id: Int?, score: Double)] {
        lobby.players.map { (id: $0.participantId, score: (lobby.score($0) * 10).rounded() / 10) }.sorted { $0.score > $1.score }
    }
}

extension HistoryParticipant {
    private static let supportItems: Set<Int> = [3850, 3854, 3858, 3862, 3864, 3865, 3866, 3867, 3869, 3870, 3871, 3876, 3877]

    var isSupport: Bool { lane == .utility || !Self.supportItems.isDisjoint(with: stats.items) }
}

/// Lobby averages that each player's stats are measured against.
private struct Lobby {
    enum Metric: CaseIterable {
        case damage, tanking, cs, vision, objectives, deaths

        func value(_ p: HistoryParticipant) -> Double {
            let s = p.stats
            return switch self {
            case .damage: Double(s.totalDamageDealtToChampions ?? 0)
            case .tanking: Double((s.totalDamageTaken ?? 0) + (s.damageSelfMitigated ?? 0))
            case .cs: Double(s.cs)
            case .vision: Double(s.visionScore ?? 0)
            case .objectives: Double(s.damageDealtToObjectives ?? 0)
            case .deaths: Double(s.deaths ?? 0)
            }
        }
    }

    struct Weights {
        var kda, kp, damage, deaths, cs, vision, objectives: Double

        static let carry = Weights(kda: 0.22, kp: 0.15, damage: 0.25, deaths: 0.13, cs: 0.15, vision: 0.05, objectives: 0.05)
        static let support = Weights(kda: 0.22, kp: 0.22, damage: 0.14, deaths: 0.15, cs: 0, vision: 0.22, objectives: 0.05)
        static let aram = Weights(kda: 0.25, kp: 0.2, damage: 0.3, deaths: 0.15, cs: 0.05, vision: 0, objectives: 0.05)
        static let arena = Weights(kda: 0.35, kp: 0, damage: 0.45, deaths: 0.2, cs: 0, vision: 0, objectives: 0)
    }

    let players: [HistoryParticipant]
    let hasResult: Bool
    let isARAM: Bool
    let isArena: Bool
    let kda: Double
    let means: [Metric: Double]

    init(game: HistoryGame) {
        let everyone = game.participants ?? []
        players = everyone
        isARAM = game.gameMode == "ARAM"
        isArena = game.gameMode == "CHERRY"
        hasResult = game.isCountable && game.gameMode != "CHERRY"
        let takedowns = everyone.reduce(0) { $0 + ($1.stats.kills ?? 0) + ($1.stats.assists ?? 0) }
        kda = Double(takedowns) / Double(max(everyone.reduce(0) { $0 + ($1.stats.deaths ?? 0) }, 1))
        let count = Double(max(everyone.count, 1))
        means = Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
            (metric, everyone.reduce(0) { $0 + metric.value($1) } / count)
        })
    }

    /// Maps a ratio to the lobby average onto 0…1, where 0.5 is exactly average.
    private func curve(_ ratio: Double) -> Double {
        min(max(0.5 + log2(max(ratio, 0.01)) / 3.5, 0), 1)
    }

    private func relative(_ p: HistoryParticipant, _ metric: Metric) -> Double {
        let mean = means[metric] ?? 0
        return mean > 0 ? metric.value(p) / mean : 1
    }

    func leads(_ p: HistoryParticipant, in metric: Metric) -> Bool {
        let value = metric.value(p)
        return value > 0 && !players.contains { $0.participantId != p.participantId && metric.value($0) > value }
    }

    func score(_ p: HistoryParticipant) -> Double {
        let s = p.stats
        let support = p.isSupport
        let w: Weights = isARAM ? .aram : isArena ? .arena : support ? .support : .carry
        let takedowns = Double((s.kills ?? 0) + (s.assists ?? 0))
        let deaths = Metric.deaths.value(p)
        let team = players.filter { $0.teamId == p.teamId }
        let teamKills = Double(team.reduce(0) { $0 + ($1.stats.kills ?? 0) })
        var parts: [(weight: Double, value: Double)] = [
            (w.kda, curve(kda > 0 ? takedowns / max(deaths, 1) / kda : 1)),
            (w.deaths, curve(((means[.deaths] ?? 0) + 1) / (deaths + 1))),
            (w.damage, max(curve(relative(p, .damage) / (support ? 0.55 : 1)), 0.85 * curve(relative(p, .tanking)))),
            (w.cs, curve(relative(p, .cs))),
            (w.vision, curve(relative(p, .vision) / (support ? 2.2 : 1))),
            (w.objectives, curve(relative(p, .objectives))),
        ]
        if team.count >= 3, teamKills >= 3 {
            parts.append((w.kp, min(max((takedowns / teamKills - 0.3) / 0.45, 0), 1)))
        }
        let weight = parts.reduce(0) { $0 + $1.weight }
        var total = weight > 0 ? parts.reduce(0) { $0 + $1.weight * $1.value } / weight * 10 : 5
        if hasResult, s.win == true { total += 0.5 }
        return min(max(total, 0), 10)
    }
}
