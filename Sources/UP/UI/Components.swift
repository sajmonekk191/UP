import Charts
import SwiftUI

func percent(_ value: Double?, digits: Int = 1) -> String {
    guard let value else { return "—" }
    return value.formatted(.percent.precision(.fractionLength(digits)).locale(Localizer.shared.language.locale))
}

/// Locale-aware decimal with a fixed number of fraction digits.
func decimal(_ value: Double, _ digits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).locale(Localizer.shared.language.locale))
}

func compact(_ value: Double) -> String {
    switch abs(value) {
    case 1_000_000...: decimal(value / 1_000_000) + "M"
    case 10_000...: decimal(value / 1000) + "k"
    default: Int(value.rounded()).formatted(.number.locale(Localizer.shared.language.locale))
    }
}

func gamesLabel(_ count: Int) -> String {
    count == 1 ? tr("1 game") : tr("%@ games", count.formatted(.number.locale(Localizer.shared.language.locale)))
}

func winRateColor(_ value: Double?) -> Color {
    guard let value else { return Theme.textSecondary }
    if value >= 0.52 { return Theme.win }
    if value <= 0.48 { return Theme.loss }
    return Theme.text
}

// MARK: - Layout

/// Screen with a title row and scrolling content on the navy backdrop.
struct Screen<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.display).foregroundStyle(Theme.text)
                        if let subtitle { Text(subtitle).font(.callout).foregroundStyle(Theme.textSecondary) }
                    }
                    Spacer()
                    trailing
                }
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 1280, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

extension Screen where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

extension EnvironmentValues {
    @Entry var panelFillsHeight = false
}

struct Panel<Accessory: View, Content: View>: View {
    @Environment(\.panelFillsHeight) private var fillsHeight
    var title: String?
    var symbol: String?
    var padding: CGFloat = 16
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(spacing: 7) {
                    if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.accentBright) }
                    if let title { Text(title).eyebrow() }
                    Spacer()
                    accessory
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .panelBackground()
    }
}

extension Panel where Accessory == EmptyView {
    init(title: String? = nil, symbol: String? = nil, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, padding: padding, accessory: { EmptyView() }, content: content)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentDeep.opacity(0.35)).frame(width: 84, height: 84)
                Circle().strokeBorder(Theme.accent.opacity(0.5)).frame(width: 84, height: 84)
                Image(systemName: symbol).font(.system(size: 32, weight: .medium)).foregroundStyle(Theme.accentBright)
            }
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            Text(message).font(.callout).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Data display

/// Label, value, optional sub-line and trend sparkline.
struct StatTile: View {
    let label: String
    let value: String
    var sub: String?
    var valueColor: Color = Theme.text
    var trend: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow().lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(value).font(.tileValue).foregroundStyle(valueColor).lineLimit(1).fixedSize()
                if let trend, trend.count > 1 { Sparkline(values: trend).frame(maxWidth: 56).frame(height: 18) }
            }
            if let sub { Text(sub).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(Theme.surface, radius: 12)
    }
}

/// Horizontal fill meter whose track is a darker step of the fill ramp.
struct Meter: View {
    let value: Double
    var tint: Color = Theme.accent
    var track: Color = Theme.accentTrack
    var height: CGFloat = 6
    var marker: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(geo.size.width * min(max(value, 0), 1), height))
                if let marker {
                    Rectangle().fill(Theme.textMuted).frame(width: 1.5, height: height + 6)
                        .offset(x: geo.size.width * marker - 0.75)
                }
            }
        }
        .frame(height: height)
    }
}

/// Win rate value with a meter centered on 50 %.
struct WinRateMeter: View {
    let winRate: Double?
    var games: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(percent(winRate)).font(.callout.weight(.semibold)).foregroundStyle(winRateColor(winRate))
                Spacer()
                if let games { Text(gamesLabel(games)).font(.caption).foregroundStyle(Theme.textMuted) }
            }
            let ahead = (winRate ?? 0) >= 0.495
            Meter(value: winRate ?? 0, tint: ahead ? Theme.win : Theme.loss, track: ahead ? Theme.accentTrack : Theme.lossTrack, marker: 0.5)
        }
    }
}

/// Two-sided ally vs enemy bar with a 2px gap between the fills.
struct VersusBar: View {
    let label: String
    let ally: Double
    let enemy: Double
    var format: (Double) -> String = { compact($0) }

    var body: some View {
        let total = max(ally + enemy, 1)
        VStack(spacing: 5) {
            HStack {
                Text(format(ally)).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
                Spacer()
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(enemy)).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                if ally + enemy <= 0 {
                    Capsule().fill(Theme.raised)
                } else {
                    HStack(spacing: 2) {
                        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3).fill(Theme.ally)
                            .frame(width: max((geo.size.width - 2) * ally / total, 2))
                        UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3).fill(Theme.enemy)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.accentBright

    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let points = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat((v - lo) / span)))
            }
            ZStack {
                Path { p in p.addLines(points) }
                    .stroke(Theme.textMuted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(tint).frame(width: 5, height: 5).position(last)
                }
            }
        }
    }
}

/// Recent results as labelled squares (identity is never color alone).
struct FormStrip: View {
    let form: [Bool]
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(form.enumerated()), id: \.offset) { _, win in
                Text(win ? tr("W") : tr("L"))
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(win ? Theme.accentBright : Theme.loss)
                    .frame(width: size, height: size)
                    .background((win ? Theme.win : Theme.loss).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .help(tr("Last %d games, newest on the left", form.count))
    }
}

struct Chip: View {
    enum Tone { case accent, good, bad, gold, neutral }
    let text: String
    var tone: Tone = .neutral
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3)))
    }

    private var color: Color {
        switch tone {
        case .accent: Theme.accentBright
        case .good: Theme.good
        case .bad: Theme.loss
        case .gold: Theme.gold
        case .neutral: Theme.textSecondary
        }
    }
}

struct TagChip: View {
    let tag: PlayerProfile.Tag

    var body: some View {
        let tone: Chip.Tone = switch tag.tone {
        case .good: .accent
        case .bad: .bad
        case .info: .gold
        }
        Chip(text: tag.text, tone: tone).help(tag.help)
    }
}

struct FlowTags: View {
    let tags: [PlayerProfile.Tag]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) { ForEach(tags) { TagChip(tag: $0) } }
        }
    }
}

/// Small key/value column.
struct KeyValue: View {
    let key: String
    let value: String
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(.caption2).foregroundStyle(Theme.textMuted)
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }
}

// MARK: - Game assets

struct ChampionIcon: View {
    @Environment(AppModel.self) private var model
    let id: Int?
    var size: CGFloat = 36
    var ring: Color? = nil

    var body: some View {
        LCUImage(path: model.gameData.championIcon(id), size: size, corner: size * 0.24)
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(ring ?? Theme.hairlineStrong, lineWidth: ring == nil ? 1 : 2))
            .help(model.gameData.championName(id))
    }
}

struct ItemIcon: View {
    @Environment(AppModel.self) private var model
    let id: Int
    var size: CGFloat = 28

    var body: some View {
        LCUImage(path: id > 0 ? model.gameData.items[id]?.iconPath : nil, size: size, corner: 5)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
            .help(model.gameData.items[id].map { "\($0.name) · \($0.priceTotal ?? 0) g" } ?? "")
    }
}

struct PerkIcon: View {
    @Environment(AppModel.self) private var model
    let id: Int
    var size: CGFloat = 26

    var body: some View {
        let path = model.gameData.perks[id]?.iconPath ?? model.gameData.styles[id]?.iconPath
        LCUImage(path: path, size: size, corner: size / 2, fill: .clear)
            .help(model.gameData.perks[id].map { "\($0.name)\n\($0.shortDesc?.strippingTags ?? "")" } ?? model.gameData.styles[id]?.name ?? "")
    }
}

struct SpellIcon: View {
    @Environment(AppModel.self) private var model
    let id: Int
    var size: CGFloat = 24

    var body: some View {
        LCUImage(path: model.gameData.spells[id]?.iconPath, size: size, corner: 5)
            .help(model.gameData.spells[id]?.name ?? "")
    }
}

struct RankEmblem: View {
    let tier: String?
    var size: CGFloat = 44

    var body: some View {
        if let url = GameData.rankEmblemURL(tier) {
            LCUImage(path: url, size: size, corner: 0, fill: .clear, crop: CGRect(x: 0.38, y: 0.31, width: 0.24, height: 0.32))
        } else {
            Image(systemName: "shield")
                .font(.system(size: size * 0.5, weight: .light))
                .foregroundStyle(Theme.textMuted)
                .frame(width: size, height: size)
        }
    }
}

/// Rank emblem, tier label, record and win-rate meter.
struct RankBlock: View {
    let title: String
    let queue: RankedQueue?

    var body: some View {
        HStack(spacing: 12) {
            RankEmblem(tier: queue?.isRanked == true ? queue?.tier : nil, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).eyebrow()
                Text(queue?.label ?? tr("Unranked")).font(.headline).foregroundStyle(queue?.isRanked == true ? Theme.text : Theme.textSecondary)
                if let queue, queue.games > 0 {
                    Text(tr("%dW %dL", queue.wins ?? 0, queue.losses ?? 0)).font(.caption).foregroundStyle(Theme.textSecondary)
                    WinRateMeter(winRate: queue.winRate).frame(width: 150)
                } else if let prev = queue?.previousSeasonEndTier, !prev.isEmpty, prev != "NONE" {
                    Text(tr("Last season: %@", "\(prev.capitalized) \(queue?.previousSeasonEndDivision ?? "")")).font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }
}

/// Splash-art banner that fades into the page background.
struct HeroBanner<Content: View>: View {
    let splashPath: String?
    var height: CGFloat = 220
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let imageHeight = geo.size.width * 9 / 16
                let focus = min(max(geo.size.height / 2 - imageHeight * 0.36, geo.size.height - imageHeight), 0)
                LCUImage(path: splashPath, size: nil, corner: 0, fill: Theme.surface, contentMode: .fill)
                    .frame(width: geo.size.width, height: imageHeight)
                    .offset(y: focus)
            }
            .clipped()
            LinearGradient(colors: [Theme.background.opacity(0.1), Theme.background.opacity(0.75), Theme.background],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Theme.background.opacity(0.85), .clear], startPoint: .leading, endPoint: .center)
            content.padding(24)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous).strokeBorder(Theme.hairline))
    }
}

extension String {
    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// MARK: - Player card

/// Porofessor-style player row used in champ select, loading screen and lookup.
struct PlayerCard: View {
    @Environment(AppModel.self) private var model
    let profile: PlayerProfile?
    let championId: Int?
    var lane: Lane?
    var fallbackName: String?
    var side: Color = Theme.ally
    var isMe = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ChampionIcon(id: championId, size: 52, ring: isMe ? Theme.gold : nil)
                if let lane {
                    Image(systemName: lane.symbol).font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.text).padding(4)
                        .background(Theme.raised, in: Circle()).overlay(Circle().strokeBorder(Theme.hairlineStrong))
                        .offset(x: 5, y: 5)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile?.summoner?.riotId ?? fallbackName ?? tr("Hidden player"))
                        .font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    if let level = profile?.summoner?.summonerLevel {
                        Text("\(level)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.raised, in: Capsule())
                    }
                    if isMe { Chip(text: tr("YOU"), tone: .gold) }
                }
                if let profile {
                    FlowTags(tags: profile.tags)
                } else if fallbackName == nil {
                    Text(tr("Name hidden in ranked champ select")).font(.caption).foregroundStyle(Theme.textMuted)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(minWidth: 170, alignment: .leading)
            Spacer(minLength: 8)
            if let profile {
                let queue = profile.solo?.isRanked == true ? profile.solo : profile.flex
                HStack(spacing: 8) {
                    RankEmblem(tier: queue?.isRanked == true ? queue?.tier : nil, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(queue?.label ?? tr("Unranked")).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(queue.flatMap { $0.games > 0 ? tr("%@ · %d games", percent($0.winRate, digits: 0), $0.games) : nil } ?? "—")
                            .font(.caption2).foregroundStyle(winRateColor(queue?.winRate))
                    }
                }
                .frame(width: 150, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    FormStrip(form: Array(profile.form.prefix(8)), size: 13)
                    let kda = profile.averageKDA
                    Text("\(decimal(kda.k)) / \(decimal(kda.d)) / \(decimal(kda.a))")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 130, alignment: .leading)
                championStat(profile).frame(width: 110, alignment: .leading)
                HStack(spacing: 3) {
                    ForEach(profile.champions.prefix(3)) { record in
                        ChampionIcon(id: record.championId, size: 22)
                            .help(tr("%@: %d games, %@", model.gameData.championName(record.championId), record.games, percent(record.winRate, digits: 0)))
                    }
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12).fill(side).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isMe ? Theme.gold.opacity(0.5) : Theme.hairline))
    }

    @ViewBuilder
    private func championStat(_ profile: PlayerProfile) -> some View {
        if let championId, championId > 0 {
            if let record = profile.record(for: championId) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("ON CHAMPION")).font(.system(size: 8.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textMuted)
                    Text("\(record.games)× · \(percent(record.winRate, digits: 0))").font(.caption.weight(.semibold))
                        .foregroundStyle(winRateColor(record.winRate))
                }
            } else if let mastery = profile.masteries.first(where: { $0.championId == championId }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MASTERY").font(.system(size: 8.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textMuted)
                    Text("M\(mastery.championLevel ?? 0) · \(compact(Double(mastery.championPoints ?? 0)))").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                }
            } else if profile.recentGames.count >= 10 {
                Chip(text: tr("New champion"), tone: .gold)
            }
        }
    }
}
