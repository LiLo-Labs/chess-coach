import SwiftUI
import ChessboardKit

/// User-selectable board color themes, mapping to ChessboardKit color schemes.
enum BoardTheme: String, CaseIterable, Identifiable, Sendable {
    case chessCom = "chessCom"
    case classic  = "classic"
    case dark     = "dark"
    case blue     = "blue"
    case green    = "green"
    case purple   = "purple"
    case orange   = "orange"
    case red      = "red"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chessCom: return "Chess.com"
        case .classic:  return "Classic"
        case .dark:     return "Dark"
        case .blue:     return "Blue"
        case .green:    return "Green"
        case .purple:   return "Purple"
        case .orange:   return "Orange"
        case .red:      return "Red"
        }
    }

    /// The ChessboardKit color scheme for this theme.
    var colorScheme: any ChessboardColorScheme {
        switch self {
        case .chessCom: return ChessComColorScheme()
        case .classic:  return ChessboardColorSchemes.Light()
        case .dark:     return ChessboardColorSchemes.Dark()
        case .blue:     return ChessboardColorSchemes.Blue()
        case .green:    return ChessboardColorSchemes.Green()
        case .purple:   return ChessboardColorSchemes.Purple()
        case .orange:   return ChessboardColorSchemes.Orange()
        case .red:      return ChessboardColorSchemes.Red()
        }
    }

    /// Light square color for preview swatches.
    var lightColor: Color {
        switch self {
        case .chessCom: return Color(red: 0.93, green: 0.87, blue: 0.73)
        case .classic:  return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .dark:     return Color(red: 0.20, green: 0.20, blue: 0.20)
        case .blue:     return Color(red: 0.85, green: 0.95, blue: 1.0)
        case .green:    return Color(red: 0.85, green: 1.0, blue: 0.85)
        case .purple:   return Color(red: 0.85, green: 0.85, blue: 1.0)
        case .orange:   return Color(red: 1.0, green: 0.85, blue: 0.60)
        case .red:      return Color(red: 1.0, green: 0.85, blue: 0.85)
        }
    }

    /// Dark square color for preview swatches.
    var darkColor: Color {
        switch self {
        case .chessCom: return Color(red: 0.46, green: 0.59, blue: 0.34)
        case .classic:  return Color(red: 0.85, green: 0.85, blue: 0.85)
        case .dark:     return Color(red: 0.10, green: 0.10, blue: 0.10)
        case .blue:     return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .green:    return Color(red: 0.55, green: 1.0, blue: 0.55)
        case .purple:   return Color(red: 0.55, green: 0.55, blue: 1.0)
        case .orange:   return Color(red: 1.0, green: 0.65, blue: 0.25)
        case .red:      return Color(red: 1.0, green: 0.55, blue: 0.55)
        }
    }
}

/// User-selectable piece style. Currently only Classic (USCF) is available.
/// Prepared for future expansion with additional piece art sets.
enum PieceStyle: String, CaseIterable, Identifiable, Sendable {
    case classic = "classic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        }
    }
}
