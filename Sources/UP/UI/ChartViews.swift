import Charts
import SwiftUI

/// Win rate by game length as columns around a 50 % reference line.
struct GameLengthChart: View {
    let points: [(minute: Int, winRate: Double)]
    @State private var selected: String?

    private func bucket(_ minute: Int) -> String { minute == 0 ? "<25 min" : "\(minute)+ min" }

    var body: some View {
        Chart {
            RuleMark(y: .value("Average", 0.5))
                .foregroundStyle(Theme.textMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(points, id: \.minute) { point in
                BarMark(x: .value("Length", bucket(point.minute)), yStart: .value("Min", yDomain.lowerBound), yEnd: .value("Winrate", point.winRate), width: .ratio(0.55))
                    .foregroundStyle(point.winRate >= 0.5 ? Theme.win : Theme.loss)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .opacity(selected == nil || selected == bucket(point.minute) ? 1 : 0.45)
                    .annotation(position: .top, spacing: 4) {
                        if selected == bucket(point.minute) {
                            Text(percent(point.winRate)).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                        }
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text(percent(value.as(Double.self), digits: 0)).foregroundStyle(Theme.textMuted) }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) { Text(value.as(String.self) ?? "").foregroundStyle(Theme.textSecondary) }
            }
        }
        .chartXSelection(value: $selected)
        .chartPlotStyle { $0.clipped() }
        .frame(height: 150)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.winRate) + [0.5]
        return ((values.min() ?? 0.4) - 0.03)...((values.max() ?? 0.6) + 0.03)
    }
}

/// Win rate across recent patches with a hover crosshair.
struct PatchTrendChart: View {
    let points: [(patch: String, winRate: Double, rank: Int)]
    @State private var selected: String?

    var body: some View {
        Chart {
            ForEach(points, id: \.patch) { point in
                AreaMark(x: .value("Patch", point.patch), yStart: .value("Min", yDomain.lowerBound), yEnd: .value("Winrate", point.winRate))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Patch", point.patch), y: .value("Winrate", point.winRate))
                    .foregroundStyle(Theme.accentBright)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            if let selected, let point = points.first(where: { $0.patch == selected }) {
                RuleMark(x: .value("Patch", selected)).foregroundStyle(Theme.hairlineStrong)
                PointMark(x: .value("Patch", selected), y: .value("Winrate", point.winRate))
                    .foregroundStyle(Theme.accentBright).symbolSize(70)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 2) {
                            Text("Patch \(point.patch)").font(.caption2).foregroundStyle(Theme.textSecondary)
                            Text(percent(point.winRate)).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                            if point.rank > 0 { Text(tr("#%d in role", point.rank)).font(.caption2).foregroundStyle(Theme.textMuted) }
                        }
                        .padding(6).panelBackground(Theme.raised, radius: 8)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text(percent(value.as(Double.self), digits: 0)).foregroundStyle(Theme.textMuted) }
            }
        }
        .chartXAxis {
            AxisMarks { value in AxisValueLabel { Text(value.as(String.self) ?? "").foregroundStyle(Theme.textSecondary) } }
        }
        .chartXSelection(value: $selected)
        .chartPlotStyle { $0.clipped() }
        .frame(height: 150)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.winRate)
        return ((values.min() ?? 0.45) - 0.01)...((values.max() ?? 0.55) + 0.01)
    }
}

/// LP across the recorded ranked readings, with the rank named on the axis and each step coloured by gain or loss.
struct LPChart: View {
    let snapshots: [RankSnapshot]
    @State private var selected: Int?

    var body: some View {
        let points = Array(snapshots.suffix(30))
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                AreaMark(x: .value("Game", index), yStart: .value("Min", yDomain.lowerBound), yEnd: .value("LP", point.score))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Game", index), y: .value("LP", point.score))
                    .foregroundStyle(Theme.accentBright)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Game", index), y: .value("LP", point.score))
                    .foregroundStyle(index == 0 || point.score >= points[index - 1].score ? Theme.win : Theme.loss)
                    .symbolSize(26)
            }
            if let selected, points.indices.contains(selected) {
                let point = points[selected]
                RuleMark(x: .value("Game", selected)).foregroundStyle(Theme.hairlineStrong)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(point.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.textSecondary)
                            Text(point.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                            if selected > 0 {
                                let change = point.score - points[selected - 1].score
                                Text(signedLP(change)).font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(change >= 0 ? Theme.win : Theme.loss)
                            }
                        }
                        .padding(6).panelBackground(Theme.raised, radius: 8)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text(RankSnapshot.label(for: value.as(Int.self) ?? 0)).foregroundStyle(Theme.textMuted) }
            }
        }
        .chartXAxis(.hidden)
        .chartXSelection(value: $selected)
        .chartPlotStyle { $0.clipped() }
        .frame(height: 150)
    }

    private var yDomain: ClosedRange<Int> {
        let scores = snapshots.suffix(30).map(\.score)
        return ((scores.min() ?? 0) - 30)...((scores.max() ?? 100) + 30)
    }

    /// Division lines, or tier lines when the history spans more than a few divisions.
    private var ticks: [Int] {
        let step = yDomain.upperBound - yDomain.lowerBound > 500 ? 400 : 100
        let first = Int((Double(yDomain.lowerBound) / Double(step)).rounded(.up)) * step
        return Array(stride(from: first, through: yDomain.upperBound, by: step))
    }
}

/// One horizontal bar per player, colored by team, with the value labelled.
struct PlayerBarChart: View {
    struct Row: Identifiable {
        var id: String
        var label: String
        var value: Double
        var ally: Bool
    }
    let rows: [Row]

    var body: some View {
        let peak = max(rows.map(\.value).max() ?? 1, 1)
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.label).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 110, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(row.ally ? Theme.ally : Theme.enemy)
                            .frame(width: max(geo.size.width * row.value / peak, 3))
                    }
                    .frame(height: 10)
                    Text(compact(row.value)).font(.caption.monospacedDigit()).foregroundStyle(Theme.text).frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}
