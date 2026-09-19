import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Dark navy design tokens; data colors validated for CVD separation on the panel surface.
enum Theme {
    static let background = Color(hex: 0x060A14)
    static let sidebar = Color(hex: 0x0A1020)
    static let surface = Color(hex: 0x0F1729)
    static let raised = Color(hex: 0x152039)
    static let hover = Color(hex: 0x1B2849)
    static let hairline = Color(hex: 0x21304F)
    static let hairlineStrong = Color(hex: 0x2E4270)
    static let skeleton = Color(hex: 0x19253F)

    static let text = Color(hex: 0xEAF1FF)
    static let textSecondary = Color(hex: 0x9AABCB)
    static let textMuted = Color(hex: 0x62739A)

    static let accent = Color(hex: 0x3987E5)
    static let accentBright = Color(hex: 0x6DB0FF)
    static let accentDeep = Color(hex: 0x184F95)
    static let accentTrack = Color(hex: 0x14294A)

    static let win = accent
    static let loss = Color(hex: 0xE66767)
    static let lossTrack = Color(hex: 0x3A1F2B)
    static let ally = accent
    static let enemy = loss

    static let gold = Color(hex: 0xD9A441)
    static let good = Color(hex: 0x2FBF71)
    static let warning = Color(hex: 0xFAB219)

    static let radius: CGFloat = 14
    static let gap: CGFloat = 16
    /// Bottom space that keeps scrolled content clear of the navigation dock.
    static let dockClearance: CGFloat = 104

    static let backdrop = LinearGradient(
        colors: [Color(hex: 0x0B1630), Color(hex: 0x060A14)],
        startPoint: .top, endPoint: .center)
}

extension Font {
    static let display = Font.system(size: 30, weight: .bold, design: .default)
    static let tileValue = Font.system(size: 22, weight: .semibold)
    static let label = Font.system(size: 10.5, weight: .semibold).width(.expanded)
}

extension View {
    /// Small uppercase section label.
    func eyebrow() -> some View {
        font(.label).textCase(.uppercase).tracking(0.8).foregroundStyle(Theme.textMuted)
    }

    func panelBackground(_ fill: Color = Theme.surface, radius: CGFloat = Theme.radius) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// Shows the pointing-hand cursor over this clickable view while it is enabled.
    func handCursor() -> some View { modifier(HandCursor()) }
}

private struct HandCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.pointerStyle(enabled ? .link : nil) } else { content }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1).fixedSize()
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [Theme.accentBright, Theme.accent], startPoint: .top, endPoint: .bottom)
                    .opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 2)
            .opacity(enabled ? 1 : 0.4)
            .handCursor()
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(Theme.text)
            .background(configuration.isPressed ? Theme.hover : Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .handCursor()
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Capsule segmented control styled for the dark theme.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(.snappy(duration: 0.2)) { selection = value } } label: {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(minWidth: 44)
                        .foregroundStyle(selection == value ? Theme.text : Theme.textSecondary)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accentDeep)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.accent.opacity(0.6)))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).handCursor()
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Switch that shows its state in the accent colour even when the window is inactive.
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.accent : Theme.raised)
                    .overlay(Capsule().strokeBorder(configuration.isOn ? Theme.accentBright.opacity(0.5) : Theme.hairlineStrong))
                Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .frame(width: 32, height: 18)
            .animation(.snappy(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain).handCursor()
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}
