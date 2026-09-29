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

    /// Corner radius for every card, like the Health app's uniform, generous
    /// rounding.
    static let cardRadius: CGFloat = 24

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

    /// Medication, as in the Health app: a cyan-blue, deep enough in light
    /// mode for white button text and small icons to read.
    static let medication = Color(light: Color(red: 0.0, green: 0.52, blue: 0.74),
                                  dark: Color(red: 0.35, green: 0.78, blue: 0.98))

    /// A secondary accent for the linked "proxy" account colour treatment.
    static let proxy = Color(red: 0.56, green: 0.35, blue: 0.64)

    /// Ordered leaf palette for cycling accents across items.
    static let leaves: [Color] = [red, orange, yellow, green, teal]

    /// Section colours for Browse tiles and card headers: softer than the
    /// system colours, each with a lighter shade for dark mode. All at least
    /// 3.9:1 against white cards and 6.5:1 against dark ones, so the icons
    /// stay clear.
    enum Section {
        static let visits = muted(0.74, 0.38, 0.27, dark: 0.92, 0.60, 0.48)        // terracotta
        static let testResults = muted(0.36, 0.38, 0.66, dark: 0.64, 0.66, 0.92)   // slate indigo
        static let medication = muted(0.16, 0.46, 0.62, dark: 0.46, 0.72, 0.86)    // steel cyan
        static let immunisations = muted(0.52, 0.38, 0.62, dark: 0.76, 0.64, 0.86) // plum
        static let allergies = muted(0.72, 0.44, 0.18, dark: 0.92, 0.66, 0.40)     // amber
        static let growthCharts = muted(0.33, 0.53, 0.36, dark: 0.56, 0.76, 0.58)  // sage
        static let trackHealth = muted(0.18, 0.50, 0.52, dark: 0.46, 0.76, 0.76)   // deep teal
        static let implants = muted(0.52, 0.42, 0.34, dark: 0.76, 0.66, 0.57)      // taupe
        static let letters = muted(0.60, 0.49, 0.14, dark: 0.86, 0.74, 0.40)       // ochre
        static let healthSummary = muted(0.68, 0.34, 0.45, dark: 0.90, 0.60, 0.68) // dusty rose
        static let messages = muted(0.24, 0.43, 0.67, dark: 0.54, 0.70, 0.92)      // denim
        static let sharing = muted(0.22, 0.51, 0.43, dark: 0.50, 0.78, 0.68)       // seafoam
        static let medicalID = muted(0.66, 0.26, 0.28, dark: 0.90, 0.52, 0.53)     // brick

        private static func muted(_ r: Double, _ g: Double, _ b: Double,
                                  dark dr: Double, _ dg: Double, _ db: Double) -> Color {
            Color(light: Color(red: r, green: g, blue: b), dark: Color(red: dr, green: dg, blue: db))
        }
    }

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
    /// A paler shade of the same colour, for the second layer of two-tone
    /// icons. Mixed with white, so it stays bright on dark backgrounds too.
    var lighter: Color { mix(with: .white, by: 0.45) }

    /// A colour that follows the system appearance.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
