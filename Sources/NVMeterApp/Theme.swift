import SwiftUI
import NVMeterCore

/// Single source of truth for brand color + spacing tokens.
/// Mirrors `design/tokens.md`. Update both together.
enum Theme {
    enum Brand {
        static let primary = Color(red: 0x2B / 255, green: 0xB1 / 255, blue: 0xB8 / 255)
        static let primaryDim = Color(red: 0x1F / 255, green: 0x83 / 255, blue: 0x88 / 255)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Layout {
        static let windowWidth: CGFloat = 420
        static let maxHeight: CGFloat = 640
        static let cardRadius: CGFloat = 10
        static let cardPadding: CGFloat = 12
    }

    static func color(for level: HealthLevel) -> Color {
        switch level {
        case .good: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }

    static func systemImage(for level: HealthLevel) -> String {
        switch level {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }
}
