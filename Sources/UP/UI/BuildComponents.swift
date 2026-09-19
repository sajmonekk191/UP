import SwiftUI

func tierName(_ tier: Int?) -> String {
    switch tier {
    case 0: "OP"
    case 1: "S"
    case 2: "A"
    case 3: "B"
    case 4: "C"
    case nil: "—"
    default: "D"
    }
}

/// Full build breakdown: headline stats, runes, items, skills, charts, matchups and champion info.
struct BuildDetails: View {
    @Environment(AppModel.self) private var model
    let build: ChampionBuild?
    var extraRunes: [RuneSetup] = []
    let championId: Int
    var showChampionInfo = true
    var showRunes = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            if let build { BuildHeadline(build: build) }
            if let build, !build.augments.isEmpty {
                AugmentPanels(augments: build.augments)
            } else if showRunes {
                RunePanel(runes: (build?.runes ?? []) + extraRunes, championId: championId)
            }
            if let build {
                ItemPanels(build: build)
                if let skill = build.skillOrder { SkillOrderPanel(skill: skill) }
            }
            Deferred {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    if let build {
                        HStack(alignment: .top, spacing: Theme.gap) {
                            if !build.gameLengths.isEmpty {
                                Panel(title: tr("Win rate by game length"), symbol: "hourglass") { GameLengthChart(points: build.gameLengths) }
                            }
                            if build.patchTrend.count > 1 {
                                Panel(title: tr("Win rate across patches"), symbol: "chart.line.uptrend.xyaxis") { PatchTrendChart(points: build.patchTrend) }
                            }
                        }
                        if !build.counters.isEmpty {
                            HStack(alignment: .top, spacing: Theme.gap) {
                                MatchupList(title: tr("Hardest matchups"), symbol: "hand.thumbsdown.fill", matchups: Array(build.counters.sorted { $0.winRate < $1.winRate }.prefix(6)))
                                MatchupList(title: tr("Easiest matchups"), symbol: "hand.thumbsup.fill", matchups: Array(build.counters.sorted { $0.winRate > $1.winRate }.prefix(6)))
                            }
                        }
                        if !build.duoPartners.isEmpty {
                            HStack(alignment: .top, spacing: Theme.gap) {
                                MatchupList(title: tr("Best duo partners"), symbol: "person.2.fill", matchups: Array(build.duoPartners.sorted { $0.winRate > $1.winRate }.prefix(6)))
                                MatchupList(title: tr("Most played duo partners"), symbol: "person.2.circle.fill", matchups: Array(build.duoPartners.sorted { $0.play > $1.play }.prefix(6)))
                            }
                        }
                    }
                    if showChampionInfo { ChampionInfoPanel(championId: championId) }
                }
            }
        }
    }
}

struct BuildHeadline: View {
    let build: ChampionBuild

    var body: some View {
        if let place = build.averagePlace {
            HStack(spacing: 12) {
                StatTile(label: tr("Win rate"), value: percent(build.winRate), sub: tr("Top 4 finish"), valueColor: winRateColor(build.winRate))
                StatTile(label: tr("1st place"), value: percent(build.firstPlaceRate))
                StatTile(label: tr("Average place"), value: decimal(place, 2))
                StatTile(label: tr("Pick rate"), value: percent(build.pickRate))
                StatTile(label: tr("Tier"), value: tierName(build.tier), sub: build.rank.map { tr("#%d in Arena", $0) }, valueColor: (build.tier ?? 5) <= 1 ? Theme.gold : Theme.text)
            }
        } else {
            laneHeadline
        }
    }

    private var laneHeadline: some View {
        HStack(spacing: 12) {
            StatTile(label: tr("Win rate"), value: percent(build.winRate), valueColor: winRateColor(build.winRate), trend: build.patchTrend.map(\.winRate))
            StatTile(label: tr("Pick rate"), value: percent(build.pickRate))
            StatTile(label: tr("Ban rate"), value: percent(build.banRate))
            StatTile(label: tr("Tier"), value: tierName(build.tier), sub: build.rank.map { tr("#%d in role", $0) }, valueColor: (build.tier ?? 5) <= 1 ? Theme.gold : Theme.text)
            StatTile(label: "KDA", value: build.kda.map { decimal($0, 2) } ?? "—",
                     sub: build.laneShares.first.map { tr("%@ in %@ of games", $0.lane.title, percent($0.share, digits: 0)) })
        }
    }
}

struct RunePanel: View {
    @Environment(AppModel.self) private var model
    let runes: [RuneSetup]
    let championId: Int
    var limit = 8

    var body: some View {
        Panel(title: tr("Runes"), symbol: "circle.hexagongrid.fill") {
            if runes.isEmpty { Text(tr("No data.")).foregroundStyle(Theme.textSecondary) }
            ForEach(Array(runes.prefix(limit).enumerated()), id: \.element.id) { index, setup in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                RuneRow(setup: setup, recommended: index == 0) { Task { await model.applyRunes(setup, championId: championId) } }
            }
        }
    }
}

struct ItemPanels: View {
    @Environment(AppModel.self) private var model
    let build: ChampionBuild

    var body: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
            if !build.spells.isEmpty {
                statList(tr("Summoner spells"), "sparkles", build.spells.prefix(3)) { ids in HStack(spacing: 4) { ForEach(ids, id: \.self) { SpellIcon(id: $0, size: 28) } } }
            }
            if !build.starterItems.isEmpty {
                statList(tr("Starting items"), "bag.fill", build.starterItems.prefix(3)) { ids in HStack(spacing: 3) { ForEach(Array(ids.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 28) } } }
            }
            if !build.prismItems.isEmpty {
                statList(tr("Prismatic items"), "diamond.fill", build.prismItems.prefix(3)) { ids in HStack { ForEach(ids, id: \.self) { ItemIcon(id: $0, size: 28) } } }
            }
            statList(tr("Boots"), "shoeprints.fill", build.boots.prefix(3)) { ids in HStack { ForEach(ids, id: \.self) { ItemIcon(id: $0, size: 28) } } }
        }
        Panel(title: tr("Core build"), symbol: "shield.lefthalf.filled") {
            ForEach(Array(build.coreItems.prefix(5).enumerated()), id: \.element.id) { index, stat in
                HStack(spacing: 8) {
                    ForEach(Array(stat.ids.enumerated()), id: \.offset) { i, id in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMuted) }
                        ItemIcon(id: id, size: index == 0 ? 40 : 32)
                    }
                    Spacer()
                    WinRateMeter(winRate: stat.winRate, games: stat.play).frame(width: 200)
                }
            }
            if !build.lastItems.isEmpty {
                Text(tr("Situational and late items")).eyebrow().padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(build.lastItems.prefix(12)) { stat in
                        VStack(spacing: 3) {
                            ItemIcon(id: stat.ids[0], size: 34)
                            Text(percent(stat.winRate, digits: 0)).font(.caption2.monospacedDigit()).foregroundStyle(winRateColor(stat.winRate))
                        }
                    }
                }
            }
        }
    }

    private func statList<S: Sequence<ChampionBuild.Stat>, Icons: View>(_ title: String, _ symbol: String, _ stats: S,
                                                                           @ViewBuilder icons: @escaping ([Int]) -> Icons) -> some View {
        Panel(title: title, symbol: symbol) {
            ForEach(Array(stats), id: \.id) { stat in
                VStack(alignment: .leading, spacing: 6) {
                    icons(stat.ids)
                    WinRateMeter(winRate: stat.winRate, games: stat.play)
                }
            }
        }
    }
}

/// Best Arena augments of each rarity with how often they end in the top four.
struct AugmentPanels: View {
    @Environment(AppModel.self) private var model
    let augments: [ChampionBuild.Augment]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
            column(tr("Silver augments"), Theme.textSecondary, rarity: 1)
            column(tr("Gold augments"), Theme.gold, rarity: 4)
            column(tr("Prismatic augments"), Theme.accentBright, rarity: 8)
        }
    }

    private func column(_ title: String, _ tint: Color, rarity: Int) -> some View {
        Panel(title: title, symbol: "sparkles.rectangle.stack.fill") {
            let shown = augments.filter { $0.rarity == rarity }.prefix(6)
            if shown.isEmpty { Text(tr("No data.")).foregroundStyle(Theme.textSecondary) }
            ForEach(Array(shown)) { augment in
                let info = model.gameData.augments[augment.id]
                HStack(spacing: 10) {
                    LCUImage(path: info?.augmentSmallIconPath, size: 34, corner: 8)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.7)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info?.nameTRA ?? "#\(augment.id)").font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        WinRateMeter(winRate: augment.winRate, games: augment.play)
                    }
                }
            }
        }
    }
}

struct SkillOrderPanel: View {
    let skill: ChampionBuild.SkillOrder

    var body: some View {
        Panel(title: tr("Skill order"), symbol: "list.number") {
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(Array(skill.priority.enumerated()), id: \.offset) { index, key in
                        if index > 0 { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textMuted) }
                        Text(key).font(.headline).foregroundStyle(Theme.text).frame(width: 32, height: 32)
                            .background(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                WinRateMeter(winRate: skill.winRate).frame(width: 180)
                Text(tr("%@ of players", percent(skill.pickRate, digits: 0))).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 3) {
                ForEach(Array(skill.order.enumerated()), id: \.offset) { index, key in
                    VStack(spacing: 2) {
                        Text("\(index + 1)").font(.system(size: 8.5)).foregroundStyle(Theme.textMuted)
                        Text(key).font(.caption.weight(.bold)).frame(width: 24, height: 24)
                            .foregroundStyle(key == "R" ? Theme.background : Theme.text)
                            .background(key == "R" ? Theme.gold : Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
                    }
                }
            }
        }
    }
}

struct RuneRow: View {
    @Environment(AppModel.self) private var model
    let setup: RuneSetup
    var recommended = false
    var compact = false
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            PerkIcon(id: setup.perkIds.first ?? 0, size: compact ? 34 : 42)
                .background(Circle().fill(Theme.raised))
                .overlay(Circle().strokeBorder(recommended ? Theme.gold : Theme.hairlineStrong, lineWidth: recommended ? 2 : 1))
            HStack(spacing: 4) { ForEach(setup.perkIds.dropFirst().prefix(3), id: \.self) { PerkIcon(id: $0, size: compact ? 22 : 26) } }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)
            PerkIcon(id: setup.subStyleId, size: 18).opacity(0.8)
            HStack(spacing: 4) { ForEach(Array(setup.perkIds.dropFirst(4).prefix(2)), id: \.self) { PerkIcon(id: $0, size: compact ? 20 : 24) } }
            if !compact {
                HStack(spacing: 2) { ForEach(Array(setup.perkIds.dropFirst(6).enumerated()), id: \.offset) { PerkIcon(id: $0.element, size: 16) } }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.gameData.perks[setup.perkIds.first ?? 0]?.name ?? setup.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Chip(text: setup.source, tone: setup.source == "Riot" ? .neutral : setup.source == "op.gg" ? .accent : .gold)
                }
                if let wr = setup.winRate {
                    WinRateMeter(winRate: wr, games: setup.games).frame(width: compact ? 150 : 190)
                } else {
                    Text(tr("Client recommendation")).font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.leading, 6)
            Spacer()
            Button(tr("Import"), action: onImport).buttonStyle(.secondary).disabled(model.connection != .connected)
        }
        .padding(.vertical, 4)
    }
}

struct MatchupList: View {
    @Environment(AppModel.self) private var model
    let title: String
    let symbol: String
    let matchups: [ChampionBuild.Matchup]

    var body: some View {
        Panel(title: title, symbol: symbol) {
            ForEach(matchups) { matchup in
                HStack(spacing: 10) {
                    ChampionIcon(id: matchup.championId, size: 28)
                    Text(model.gameData.championName(matchup.championId)).foregroundStyle(Theme.text).frame(width: 110, alignment: .leading)
                    WinRateMeter(winRate: matchup.winRate, games: matchup.play)
                }
            }
        }
    }
}

/// Champion identity, playstyle ratings and abilities with cooldowns from client data.
struct ChampionInfoPanel: View {
    @Environment(AppModel.self) private var model
    let championId: Int

    var body: some View {
        if let detail = model.gameData.details[championId] {
            HStack(alignment: .top, spacing: Theme.gap) {
                Panel(title: tr("Champion profile"), symbol: "person.text.rectangle") {
                    Text(detail.title?.capitalized ?? "").font(.callout).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(detail.roles ?? [], id: \.self) { Chip(text: $0.capitalized, tone: .accent) }
                        if let type = detail.tacticalInfo?.damageType { Chip(text: type == "kMagic" ? tr("Magic") : type == "kPhysical" ? tr("Physical") : tr("Mixed"), tone: .neutral) }
                        if let attack = detail.tacticalInfo?.attackType { Chip(text: attack == "melee" ? tr("Melee") : tr("Ranged"), tone: .neutral) }
                    }
                    let style = detail.playstyleInfo
                    rating(tr("Damage"), style?.damage)
                    rating(tr("Toughness"), style?.durability)
                    rating(tr("Crowd control"), style?.crowdControl)
                    rating(tr("Mobility"), style?.mobility)
                    rating(tr("Utility"), style?.utility)
                    rating(tr("Difficulty"), detail.tacticalInfo?.difficulty)
                }
                .frame(width: 320)
                Panel(title: tr("Abilities"), symbol: "wand.and.stars") {
                    if let passive = detail.passive {
                        ability(icon: passive.abilityIconPath, key: "P", name: passive.name, description: passive.description, cooldowns: nil, costs: nil)
                    }
                    ForEach(detail.spells) { spell in
                        ability(icon: spell.abilityIconPath, key: spell.spellKey.uppercased(), name: spell.name, description: spell.description,
                                cooldowns: spell.cooldownCoefficients.map { ranks($0, spell) },
                                costs: spell.costCoefficients.map { ranks($0, spell) })
                    }
                }
            }
        }
    }

    /// Values per rank, collapsed to one when every rank is equal.
    private func ranks(_ values: [Double], _ spell: ChampionDetail.Spell) -> [Double] {
        let count = (spell.maxLevel ?? 0) > 0 ? spell.maxLevel! : (spell.spellKey.lowercased() == "r" ? 3 : 5)
        let levels = Array(values.prefix(count))
        return Set(levels).count == 1 ? [levels[0]] : levels
    }

    private func rating(_ title: String, _ value: Int?) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 100, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Capsule().fill(i < (value ?? 0) ? Theme.accent : Theme.accentTrack).frame(height: 6)
                }
            }
        }
    }

    private func ability(icon: String?, key: String, name: String, description: String?, cooldowns: [Double]?, costs: [Double]?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LCUImage(path: icon, size: 38, corner: 8)
                .overlay(alignment: .bottomTrailing) {
                    Text(key).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text)
                        .padding(3).background(Theme.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    if let cooldowns, cooldowns.contains(where: { $0 > 0 }) {
                        Label(cooldowns.map { $0.formatted(.number.precision(.fractionLength(0...1))) }.joined(separator: " / ") + " s", systemImage: "clock")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.accentBright)
                    }
                }
                Text(description?.strippingTags ?? "").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
                if let costs, costs.contains(where: { $0 > 0 }) {
                    Text(tr("Cost: %@", costs.map { $0.formatted(.number.precision(.fractionLength(0))) }.joined(separator: " / ")))
                        .font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }
}

/// Placeholder in the shape of the build breakdown while it loads.
struct BuildSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in StatTileSkeleton() }
            }
            Panel(title: tr("Runes"), symbol: "circle.hexagongrid.fill") {
                ForEach(0..<3, id: \.self) { index in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    RuneRowSkeleton()
                }
            }
            HStack(alignment: .top, spacing: Theme.gap) {
                itemList(tr("Summoner spells"), "sparkles", icons: 2)
                itemList(tr("Starting items"), "bag.fill", icons: 2)
                itemList(tr("Boots"), "shoeprints.fill", icons: 1)
            }
            Panel(title: tr("Core build"), symbol: "shield.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { _ in Bone(width: row == 0 ? 40 : 32, height: row == 0 ? 40 : 32, radius: 5) }
                            Spacer()
                            MeterSkeleton().frame(width: 200)
                        }
                    }
                }
                .shimmering()
            }
        }
    }

    private func itemList(_ title: String, _ symbol: String, icons: Int) -> some View {
        Panel(title: title, symbol: symbol) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            ForEach(0..<icons, id: \.self) { _ in Bone(width: 28, height: 28, radius: 5) }
                        }
                        MeterSkeleton()
                    }
                }
            }
            .shimmering()
        }
    }
}

/// Placeholder in the shape of a rune page row.
struct RuneRowSkeleton: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Bone(width: compact ? 34 : 42, height: compact ? 34 : 42, radius: compact ? 17 : 21)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Bone(width: compact ? 22 : 26, height: compact ? 22 : 26, radius: compact ? 11 : 13) }
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)
            Bone(width: 18, height: 18, radius: 9)
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { _ in Bone(width: compact ? 20 : 24, height: compact ? 20 : 24, radius: compact ? 10 : 12) }
            }
            if !compact {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in Bone(width: 16, height: 16, radius: 8) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Bone(width: 104, height: 10, line: 15)
                    Bone(width: 40, height: 16, radius: 8)
                }
                MeterSkeleton().frame(width: compact ? 150 : 190)
            }
            .padding(.leading, 6)
            Spacer()
            Bone(width: 62, height: 28, radius: 9)
        }
        .padding(.vertical, 4)
        .shimmering()
    }
}

/// Placeholder in the shape of a win-rate meter with its labels.
struct MeterSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Bone(width: 40, height: 10, line: 15)
                Spacer()
                Bone(width: 46, height: 7)
            }
            Bone(height: 6, radius: 3)
        }
    }
}
