import SwiftUI

extension QuotaHealth {
    var progressColor: Color {
        switch self {
        case .healthy: Color(red: 0.08, green: 0.50, blue: 0.96)
        case .warning: Color(red: 0.96, green: 0.61, blue: 0.13)
        case .critical: Color(red: 0.96, green: 0.29, blue: 0.25)
        case .unknown: .gray
        }
    }

    var backgroundColors: [Color] {
        return switch self {
        case .healthy: [Color(red: 0.91, green: 0.96, blue: 0.95), Color(red: 0.96, green: 0.94, blue: 0.82), Color(red: 0.86, green: 0.92, blue: 0.98)]
        case .warning: [Color(red: 0.94, green: 0.96, blue: 0.88), Color(red: 0.98, green: 0.91, blue: 0.68), Color(red: 0.92, green: 0.90, blue: 0.82)]
        case .critical: [Color(red: 0.96, green: 0.90, blue: 0.84), Color(red: 0.96, green: 0.78, blue: 0.72), Color(red: 0.88, green: 0.84, blue: 0.84)]
        case .unknown: [Color.gray.opacity(0.18), Color.gray.opacity(0.10)]
        }
    }

    var shadowColor: Color {
        switch self { case .healthy: .blue.opacity(0.13); case .warning: .yellow.opacity(0.18); case .critical: .red.opacity(0.18); case .unknown: .black.opacity(0.10) }
    }
    var color: Color {
        switch self {
        case .healthy: .mint
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }

}

extension ProviderUsage {
    var accent: Color { Color(red: 0.20, green: 0.48, blue: 0.96) }
}

extension View {
    @ViewBuilder
    func quotaLiquidGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func quotaCompactGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
