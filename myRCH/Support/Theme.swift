import SwiftUI

/// App-wide styling tokens drawn from the Royal Children's Hospital Melbourne
/// brand. Teal is the primary accent — vibrant and friendly, so the UI pops —
/// while navy `ink` keeps headings and body text calm and readable. The other
/// "leaf" colours add warmth in small, deliberate doses.
enum Theme {
    /// Primary accent — RCH leaf teal. Used for buttons, active states, tints.
    static let brand = Color(red: 0.13, green: 0.62, blue: 0.74)

    /// A deeper teal for gradients and pressed states.
    static let brandDeep = Color(red: 0.07, green: 0.46, blue: 0.58)

    /// Navy ink for headings and primary text (from the RCH figure/wordmark).
    /// In dark mode it becomes a soft, slightly cool off-white: navy would be
    /// all but invisible on a dark background.
    static let ink = Color(light: Color(red: 0.16, green: 0.15, blue: 0.32),
                           dark: Color(red: 0.91, green: 0.91, blue: 0.96))

    /// Teal for text and links: deep teal on light backgrounds, a lighter
    /// teal on dark ones, where the deep shade would be too dim to read.
    static let brandText = Color(light: brandDeep, dark: Color(red: 0.38, green: 0.78, blue: 0.88))

    /// A solid, muted brand fill for disabled buttons: paler in light mode,
    /// darker in dark mode, so white labels stay readable in both.
    static let brandDisabled = Color(light: brand.mix(with: .white, by: 0.45),
                                     dark: brand.mix(with: .black, by: 0.5))

    /// Text-field fill on the entry screens: white on the light wash, a raised
    /// grey on the dark one.
    static let fieldBackground = Color(light: .white, dark: Color(white: 0.17))

    /// Hairline border for fields and controls, tuned per appearance.
    static let hairline = Color(light: .black.opacity(0.08), dark: .white.opacity(0.14))

    // The five "leaf" accent colours from the RCH logo.
    static let red = Color(red: 0.85, green: 0.23, blue: 0.18)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.17)
    static let yellow = Color(red: 0.96, green: 0.76, blue: 0.11)
    static let green = Color(red: 0.49, green: 0.71, blue: 0.24)
    static let teal = Color(red: 0.13, green: 0.62, blue: 0.74)

    /// Royal blue for test results. Not an RCH leaf colour: every leaf is
    /// already taken by another section. Checked distinct from teal and
    /// purple for colour-blind users, and >= 3:1 in light and dark mode.
    static let blue = Color(red: 0.20, green: 0.38, blue: 0.86)

    /// A secondary accent for the linked "proxy" account colour treatment.
    static let proxy = Color(red: 0.56, green: 0.35, blue: 0.64)

    /// Ordered leaf palette for cycling accents across items.
    static let leaves: [Color] = [red, orange, yellow, green, teal]

    /// The soft, welcoming background wash used behind entry screens. In dark
    /// mode, a deep navy wash in the same spirit.
    static var welcomeBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(light: Color(red: 0.96, green: 0.97, blue: 0.99), dark: Color(red: 0.06, green: 0.07, blue: 0.12)),
                Color(light: Color(red: 0.99, green: 0.99, blue: 1.0), dark: Color(red: 0.04, green: 0.05, blue: 0.08)),
                Color(light: Color(red: 0.95, green: 0.98, blue: 0.99), dark: Color(red: 0.03, green: 0.08, blue: 0.10))
            ],
            startPoint: .top,
            endPoint: .bottom)
    }
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Theme.brand }
}

extension Color {
    /// A colour that follows the system appearance.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
