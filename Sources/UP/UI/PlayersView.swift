import SwiftUI

/// Profile of a player chosen from the search bar, or recent searches and friends when none is chosen.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Binding var riotId: String?
    @State private var profile: PlayerProfile?
    @State private var loading = false
    @State private var notFound = false

    var body: some View {
        Screen(title: riotId ?? tr("Player"), subtitle: tr("Searches the server you are logged in to")) {
            if loading { ProgressView().controlSize(.small) }
            if notFound { Label(tr("Player not found."), systemImage: "questionmark.circle.fill").foregroundStyle(Theme.warning) }
            if let profile {
                ProfileDetail(profile: profile)
            } else if riotId == nil {
                Panel(title: tr("Find a player"), symbol: "magnifyingglass") {
                    Text(tr("Type a Riot ID like Name#TAG in the search bar at the top (⌘K). Friends and recent searches are suggested as you type."))
                        .foregroundStyle(Theme.textSecondary)
                    let people = model.recentPlayers + model.friends.compactMap(\.riotId)
                    if !people.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(people.prefix(8)), id: \.self) { id in
                                Button(id) { riotId = id }.buttonStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: riotId) { await load() }
    }

    private func load() async {
        profile = nil
        notFound = false
        guard let riotId, riotId.contains("#") else { return }
        loading = true
        profile = await model.lookupPlayer(riotId: riotId)
        if let found = profile?.summoner?.riotId { model.rememberPlayer(found) }
        notFound = profile == nil
        loading = false
    }
}

/// Full profile: identity, ranks, averages, champions, mastery and match list.
struct ProfileDetail: View {
    @Environment(AppModel.self) private var model
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Panel {
                HStack(spacing: 16) {
                    LCUImage(path: profile.summoner?.profileIconId.map { "/lol-game-data/assets/v1/profile-icons/\($0).jpg" }, size: 64, corner: 32)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.summoner?.riotId ?? "").font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                        HStack(spacing: 6) {
                            Chip(text: tr("Level %d", profile.summoner?.summonerLevel ?? 0), tone: .neutral)
                            FlowTags(tags: profile.tags)
                        }
                    }
                    Spacer()
                    RankBlock(title: tr("Solo / Duo"), queue: profile.solo)
                    RankBlock(title: tr("Flex"), queue: profile.flex).padding(.leading, 20)
                }
            }
            let a = profile.averages, kda = profile.averageKDA
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                StatTile(label: tr("Win rate"), value: percent(profile.recentWinRate, digits: 0), sub: tr("%d countable games", profile.recentGames.count), valueColor: winRateColor(profile.recentWinRate))
                StatTile(label: "KDA", value: "\(decimal(kda.k)) / \(decimal(kda.d)) / \(decimal(kda.a))")
                StatTile(label: tr("CS / min"), value: decimal(a.csPerMin, 1))
                StatTile(label: tr("Dmg / min"), value: compact(a.damagePerMin))
                StatTile(label: tr("Vision / min"), value: decimal(a.visionPerMin, 2))
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Champions (last 20 games)"), symbol: "person.crop.square") {
                    ForEach(profile.champions.prefix(5)) { record in
                        HStack(spacing: 10) {
                            ChampionIcon(id: record.championId, size: 30)
                            Text(model.gameData.championName(record.championId)).foregroundStyle(Theme.text).frame(width: 120, alignment: .leading)
                            WinRateMeter(winRate: record.winRate, games: record.games)
                        }
                    }
                }
                Panel(title: tr("Top mastery"), symbol: "star.fill") {
                    ForEach(profile.masteries.prefix(5), id: \.championId) { mastery in
                        HStack(spacing: 10) {
                            ChampionIcon(id: mastery.championId, size: 30)
                            Text(model.gameData.championName(mastery.championId)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("M\(mastery.championLevel ?? 0)").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                            Text(compact(Double(mastery.championPoints ?? 0))).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .trailing)
                        }
                    }
                }
                .frame(width: 340)
            }
            MatchList(games: profile.recent)
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Screen(title: tr("Match history"), subtitle: tr("Click a match to see all 10 players")) {
            Button { Task { await model.refreshMyProfile() } } label: { Label(tr("Refresh"), systemImage: "arrow.clockwise") }.buttonStyle(.secondary)
        } content: {
            if let profile = model.myProfile {
                MatchList(games: profile.recent)
            } else {
                ProgressView()
            }
        }
    }
}

struct MatchList: View {
    @Environment(AppModel.self) private var model
    let games: [HistoryGame]
    @State private var expanded: Int?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(games) { game in
                if let me = game.me {
                    VStack(spacing: 0) {
                        Button { withAnimation(.snappy) { expanded = expanded == game.id ? nil : game.id } } label: { row(game, me) }
                            .buttonStyle(.plain)
                        if expanded == game.id { MatchDetail(gameId: game.id, focusPuuid: game.identity(for: me.participantId)?.puuid) }
                    }
                    .panelBackground()
                }
            }
        }
    }

    private func row(_ game: HistoryGame, _ me: HistoryParticipant) -> some View {
        let tint: Color = !game.isCountable ? Theme.textMuted : (me.stats.win == true ? Theme.win : Theme.loss)
        return HStack(spacing: 14) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.radius, bottomLeadingRadius: Theme.radius).fill(tint).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.isRemake ? tr("Remake") : !game.isCountable ? tr("Custom") : me.stats.win == true ? tr("Victory") : tr("Defeat"))
                    .font(.callout.weight(.bold)).foregroundStyle(tint)
                Text(queueName(game)).font(.caption).foregroundStyle(Theme.textSecondary)
                if let date = game.date { Text(date, style: .relative).font(.caption2).foregroundStyle(Theme.textMuted) }
            }
            .frame(width: 110, alignment: .leading)
            ChampionIcon(id: me.championId, size: 46)
            VStack(spacing: 3) {
                SpellIcon(id: me.spell1Id ?? 0, size: 20)
                SpellIcon(id: me.spell2Id ?? 0, size: 20)
            }
            VStack(spacing: 3) {
                PerkIcon(id: me.stats.perk0 ?? 0, size: 22)
                PerkIcon(id: me.stats.perkSubStyle ?? 0, size: 16)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(me.stats.kills ?? 0) / \(me.stats.deaths ?? 0) / \(me.stats.assists ?? 0)").font(.headline.monospacedDigit()).foregroundStyle(Theme.text)
                Text("\(decimal(me.stats.kda, 2)) KDA").font(.caption).foregroundStyle(Theme.textSecondary)
                if let multi = me.stats.multiKillLabel { Chip(text: multi, tone: .gold) }
            }
            .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(me.stats.cs) CS · \(decimal(Double(me.stats.cs) / game.minutes, 1))/min").font(.caption).foregroundStyle(Theme.text)
                Text(tr("%@ dmg · %d vision", compact(Double(me.stats.totalDamageDealtToChampions ?? 0)), me.stats.visionScore ?? 0)).font(.caption).foregroundStyle(Theme.textSecondary)
                Text("\(formatTime(Double(game.gameDuration ?? 0))) · \(compact(Double(me.stats.goldEarned ?? 0))) gold").font(.caption).foregroundStyle(Theme.textMuted)
            }
            .frame(width: 170, alignment: .leading)
            HStack(spacing: 2) { ForEach(Array(me.stats.items.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 28) } }
            Spacer()
            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.textMuted).padding(.trailing, 14)
        }
        .frame(height: 72)
        .contentShape(Rectangle())
    }

    private func queueName(_ game: HistoryGame) -> String {
        switch game.queueId {
        case 420: "Ranked Solo"
        case 440: "Ranked Flex"
        case 400: "Normal Draft"
        case 430, 490: "Quickplay"
        case 450: "ARAM"
        case 1700, 1710: "Arena"
        default: game.gameMode?.capitalized ?? ""
        }
    }
}

/// All players of one match with damage and gold charts, loaded on demand.
struct MatchDetail: View {
    @Environment(AppModel.self) private var model
    let gameId: Int
    let focusPuuid: String?
    @State private var game: HistoryGame?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if let game {
                let teams = Dictionary(grouping: game.participants ?? [], by: { $0.teamId ?? 0 }).sorted { $0.key < $1.key }
                ForEach(teams, id: \.key) { teamId, players in
                    teamBlock(game, teamId, players)
                }
                HStack(alignment: .top, spacing: Theme.gap) {
                    Panel(title: tr("Damage to champions"), symbol: "flame.fill") { PlayerBarChart(rows: rows(game) { Double($0.totalDamageDealtToChampions ?? 0) }) }
                    Panel(title: tr("Gold earned"), symbol: "dollarsign.circle.fill") { PlayerBarChart(rows: rows(game) { Double($0.goldEarned ?? 0) }) }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding()
            }
        }
        .padding([.horizontal, .bottom], 14)
        .task {
            guard let client = model.client else { return }
            game = try? await client.get("/lol-match-history/v1/games/\(gameId)")
        }
    }

    private func focusTeam(_ game: HistoryGame) -> Int? {
        let pid = game.participantIdentities?.first { $0.player.puuid == focusPuuid }?.participantId
        return game.participants?.first { $0.participantId == pid }?.teamId
    }

    private func rows(_ game: HistoryGame, _ value: (HistoryStats) -> Double) -> [PlayerBarChart.Row] {
        let myTeam = focusTeam(game)
        return (game.participants ?? []).map { p in
            .init(id: "\(p.participantId ?? 0)", label: model.gameData.championName(p.championId), value: value(p.stats), ally: p.teamId == myTeam)
        }
        .sorted { $0.value > $1.value }
    }

    private func teamBlock(_ game: HistoryGame, _ teamId: Int, _ players: [HistoryParticipant]) -> some View {
        let team = game.teams?.first { $0.teamId == teamId }
        let won = team?.win == "Win"
        let isMine = teamId == focusTeam(game)
        let teamKills = max(players.compactMap(\.stats.kills).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(won ? tr("Victory") : tr("Defeat")).font(.callout.weight(.bold)).foregroundStyle(won ? Theme.win : Theme.loss)
                Text(isMine ? tr("Your team") : tr("Opponents")).eyebrow()
                Spacer()
                if let team {
                    objective("building.2.fill", team.towerKills)
                    objective("flame.fill", team.dragonKills)
                    objective("ant.fill", team.hordeKills)
                    objective("eye.fill", team.riftHeraldKills)
                    objective("crown.fill", team.baronKills)
                    HStack(spacing: 2) {
                        ForEach(Array((team.bans ?? []).filter { $0.championId > 0 }.enumerated()), id: \.offset) { ChampionIcon(id: $0.element.championId, size: 20).opacity(0.6) }
                    }
                    .help(tr("Bans"))
                }
            }
            ForEach(players, id: \.participantId) { p in
                let identity = game.identity(for: p.participantId)
                let focused = identity?.puuid == focusPuuid
                HStack(spacing: 10) {
                    ChampionIcon(id: p.championId, size: 30, ring: focused ? Theme.gold : nil)
                    HStack(spacing: 2) { SpellIcon(id: p.spell1Id ?? 0, size: 16); SpellIcon(id: p.spell2Id ?? 0, size: 16) }
                    PerkIcon(id: p.stats.perk0 ?? 0, size: 18)
                    Text(identity?.riotId ?? "?").font(.callout.weight(focused ? .semibold : .regular)).foregroundStyle(focused ? Theme.gold : Theme.text)
                        .lineLimit(1).frame(width: 170, alignment: .leading)
                    Text("\(p.stats.kills ?? 0)/\(p.stats.deaths ?? 0)/\(p.stats.assists ?? 0)").font(.callout.monospacedDigit()).foregroundStyle(Theme.text).frame(width: 70, alignment: .leading)
                    Text("KP \(percent(Double((p.stats.kills ?? 0) + (p.stats.assists ?? 0)) / Double(teamKills), digits: 0))")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .leading)
                    Text("\(p.stats.cs) CS").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .leading)
                    Text("\(compact(Double(p.stats.totalDamageDealtToChampions ?? 0))) dmg").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 70, alignment: .leading)
                    Text("\(p.stats.visionScore ?? 0) vis").font(.caption.monospacedDigit()).foregroundStyle(Theme.textMuted).frame(width: 50, alignment: .leading)
                    HStack(spacing: 2) { ForEach(Array(p.stats.items.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 22) } }
                    Spacer()
                }
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(focused ? Theme.gold.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background((isMine ? Theme.ally : Theme.enemy).opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func objective(_ symbol: String, _ count: Int?) -> some View {
        Label("\(count ?? 0)", systemImage: symbol).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
    }
}
