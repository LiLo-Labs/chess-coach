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
    // Pro themes (require premium tier)
    case walnut   = "walnut"
    case marble   = "marble"
    case tournament = "tournament"

    var id: String { rawValue }

    /// Whether this theme requires a paid tier.
    var isPro: Bool {
        switch self {
        case .walnut, .marble, .tournament: return true
        default: return false
        }
    }

    /// Free themes only.
    static var freeThemes: [BoardTheme] {
        allCases.filter { !$0.isPro }
    }

    /// Pro-only themes.
    static var proThemes: [BoardTheme] {
        allCases.filter { $0.isPro }
    }

    var displayName: String {
        switch self {
        case .chessCom:    return "Chess.com"
        case .classic:     return "Classic"
        case .dark:        return "Dark"
        case .blue:        return "Blue"
        case .green:       return "Green"
        case .purple:      return "Purple"
        case .orange:      return "Orange"
        case .red:         return "Red"
        case .walnut:      return "Walnut"
        case .marble:      return "Marble"
        case .tournament:  return "Tournament"
        }
    }

    /// The ChessboardKit color scheme for this theme.
    var colorScheme: any ChessboardColorScheme {
        switch self {
        case .chessCom:    return ChessComColorScheme()
        case .classic:     return ChessboardColorSchemes.Light()
        case .dark:        return ChessboardColorSchemes.Dark()
        case .blue:        return ChessboardColorSchemes.Blue()
        case .green:       return ChessboardColorSchemes.Green()
        case .purple:      return ChessboardColorSchemes.Purple()
        case .orange:      return ChessboardColorSchemes.Orange()
        case .red:         return ChessboardColorSchemes.Red()
        case .walnut:      return WalnutColorScheme()
        case .marble:      return MarbleColorScheme()
        case .tournament:  return TournamentColorScheme()
        }
    }

    /// Light square color for preview swatches.
    var lightColor: Color {
        switch self {
        case .chessCom:    return Color(red: 0.93, green: 0.87, blue: 0.73)
        case .classic:     return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .dark:        return Color(red: 0.20, green: 0.20, blue: 0.20)
        case .blue:        return Color(red: 0.85, green: 0.95, blue: 1.0)
        case .green:       return Color(red: 0.85, green: 1.0, blue: 0.85)
        case .purple:      return Color(red: 0.85, green: 0.85, blue: 1.0)
        case .orange:      return Color(red: 1.0, green: 0.85, blue: 0.60)
        case .red:         return Color(red: 1.0, green: 0.85, blue: 0.85)
        case .walnut:      return Color(red: 0.87, green: 0.76, blue: 0.60)
        case .marble:      return Color(red: 0.92, green: 0.92, blue: 0.90)
        case .tournament:  return Color(red: 0.85, green: 0.92, blue: 0.85)
        }
    }

    /// Dark square color for preview swatches.
    var darkColor: Color {
        switch self {
        case .chessCom:    return Color(red: 0.46, green: 0.59, blue: 0.34)
        case .classic:     return Color(red: 0.85, green: 0.85, blue: 0.85)
        case .dark:        return Color(red: 0.10, green: 0.10, blue: 0.10)
        case .blue:        return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .green:       return Color(red: 0.55, green: 1.0, blue: 0.55)
        case .purple:      return Color(red: 0.55, green: 0.55, blue: 1.0)
        case .orange:      return Color(red: 1.0, green: 0.65, blue: 0.25)
        case .red:         return Color(red: 1.0, green: 0.55, blue: 0.55)
        case .walnut:      return Color(red: 0.55, green: 0.38, blue: 0.22)
        case .marble:      return Color(red: 0.60, green: 0.62, blue: 0.58)
        case .tournament:  return Color(red: 0.30, green: 0.52, blue: 0.30)
        }
    }
}

/// User-selectable piece style.
/// All styles use free open-source assets (Lichess, GPLv2+).
enum PieceStyle: String, CaseIterable, Identifiable, Sendable {
    case classic    = "classic"     // USCF-style (bundled)
    case cburnett   = "cburnett"    // Lichess default (Colin M.L. Burnett, GPLv2+)
    case merida     = "merida"      // Traditional Staunton-like (GPLv2+)
    case staunty    = "staunty"     // Modern clean Staunton
    case california = "california"  // Rounded friendly style

    var id: String { rawValue }

    /// Whether this style requires a paid tier.
    var isPro: Bool {
        switch self {
        case .classic, .cburnett: return false
        default: return true
        }
    }

    static var freeStyles: [PieceStyle] { allCases.filter { !$0.isPro } }
    static var proStyles: [PieceStyle] { allCases.filter { $0.isPro } }

    var displayName: String {
        switch self {
        case .classic:    return "Classic"
        case .cburnett:   return "Lichess"
        case .merida:     return "Merida"
        case .staunty:    return "Staunty"
        case .california: return "California"
        }
    }

    /// Asset folder name within ChessboardKit/Assets/Pieces/
    var assetFolder: String {
        switch self {
        case .classic:    return "uscf"
        case .cburnett:   return "cburnett"
        case .merida:     return "merida"
        case .staunty:    return "staunty"
        case .california: return "california"
        }
    }
}

// MARK: - Pro Board Color Schemes

/// Walnut wood grain feel — warm browns.
struct WalnutColorScheme: ChessboardColorScheme {
    public var light: Color { Color(red: 0.87, green: 0.76, blue: 0.60) }
    public var dark: Color { Color(red: 0.55, green: 0.38, blue: 0.22) }
    public var label: Color { Color(red: 0.3, green: 0.2, blue: 0.1) }
    public var selected: Color { Color(red: 0.93, green: 0.75, blue: 0.30) }
    public var hinted: Color { Color(red: 0.80, green: 0.60, blue: 0.20, opacity: 0.5) }
    public var legalMove: Color { Color(red: 0.3, green: 0.2, blue: 0.1, opacity: 0.3) }
}

/// Cool marble look — grays and off-whites.
struct MarbleColorScheme: ChessboardColorScheme {
    public var light: Color { Color(red: 0.92, green: 0.92, blue: 0.90) }
    public var dark: Color { Color(red: 0.60, green: 0.62, blue: 0.58) }
    public var label: Color { Color(red: 0.3, green: 0.3, blue: 0.3) }
    public var selected: Color { Color(red: 0.65, green: 0.78, blue: 0.90) }
    public var hinted: Color { Color(red: 0.50, green: 0.65, blue: 0.80, opacity: 0.5) }
    public var legalMove: Color { Color(red: 0.3, green: 0.3, blue: 0.3, opacity: 0.3) }
}

/// Tournament green — the classic competition board.
struct TournamentColorScheme: ChessboardColorScheme {
    public var light: Color { Color(red: 0.85, green: 0.92, blue: 0.85) }
    public var dark: Color { Color(red: 0.30, green: 0.52, blue: 0.30) }
    public var label: Color { Color(red: 0.1, green: 0.3, blue: 0.1) }
    public var selected: Color { Color(red: 0.95, green: 0.90, blue: 0.40) }
    public var hinted: Color { Color(red: 0.70, green: 0.85, blue: 0.40, opacity: 0.5) }
    public var legalMove: Color { Color(red: 0.1, green: 0.3, blue: 0.1, opacity: 0.3) }
}
