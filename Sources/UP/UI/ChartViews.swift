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
