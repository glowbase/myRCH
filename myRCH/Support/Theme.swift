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

    /// The portal's account colours (Family Access → Colour scheme), in its
    /// order: ProxySwitch's and CustomizeSubject's `TabColor` index into this.
    static let accountColours: [Color] = [
        Color(red: 0.31, green: 0.50, blue: 0.91),  // blue
        Color(red: 0.47, green: 0.76, blue: 0.85),  // light blue
        Color(red: 0.29, green: 0.65, blue: 0.50),  // green
        Color(red: 0.56, green: 0.75, blue: 0.33),  // lime
        Color(red: 0.61, green: 0.27, blue: 0.75),  // purple
        Color(red: 0.88, green: 0.26, blue: 0.45),  // pink
        Color(red: 0.92, green: 0.57, blue: 0.29)   // orange
    ]

    /// Names for VoiceOver, matching `accountColours`.
    static let accountColourNames = ["Blue", "Light blue", "Green", "Lime", "Purple", "Pink", "Orange"]

    /// An account's portal colour, or a leaf by position when it has none.
    static func accountTint(_ account: LinkedAccount, at index: Int) -> Color {
        if let colour = account.tabColor, accountColours.indices.contains(colour) {
            return accountColours[colour]
        }
        return leaves[index % leaves.count]
    }

    /// Section colours for Browse tiles and card headers: lively, but a
    /// notch calmer than the system colours, and gold rather than bright
    /// yellow for letters. Each has a lighter shade for dark mode. All at
    /// least 3.1:1 against white cards and 6.5:1 against dark ones, so the
    /// icons stay clear.
    enum Section {
        static let visits = shade(0.88, 0.32, 0.24, dark: 1.00, 0.52, 0.44)        // coral red
        static let testResults = shade(0.36, 0.35, 0.86, dark: 0.60, 0.60, 1.00)   // indigo
        static let medication = shade(0.00, 0.50, 0.78, dark: 0.30, 0.74, 0.98)    // cyan blue
        static let immunisations = shade(0.58, 0.30, 0.80, dark: 0.78, 0.58, 0.98) // violet
        static let allergies = shade(0.86, 0.42, 0.06, dark: 1.00, 0.64, 0.30)     // orange
        static let growthCharts = shade(0.16, 0.58, 0.28, dark: 0.38, 0.82, 0.46)  // green
        static let trackHealth = shade(0.00, 0.55, 0.58, dark: 0.24, 0.82, 0.82)   // teal
        static let implants = shade(0.62, 0.40, 0.22, dark: 0.86, 0.64, 0.44)      // warm brown
        static let letters = shade(0.76, 0.52, 0.00, dark: 1.00, 0.76, 0.28)       // gold
        static let referrals = shade(0.30, 0.42, 0.58, dark: 0.58, 0.70, 0.88)     // slate blue
        static let healthSummary = shade(0.86, 0.26, 0.48, dark: 1.00, 0.54, 0.70) // pink
        static let messages = shade(0.10, 0.46, 0.92, dark: 0.42, 0.66, 1.00)      // blue
        static let sharing = shade(0.00, 0.58, 0.48, dark: 0.28, 0.84, 0.70)       // jade
        static let medicalID = shade(0.80, 0.16, 0.20, dark: 1.00, 0.46, 0.46)     // red

        private static func shade(_ r: Double, _ g: Double, _ b: Double,
                                  dark dr: Double, _ dg: Double, _ db: Double) -> Color {
            Color(light: Color(red: r, green: g, blue: b), dark: Color(red: dr, green: dg, blue: db))
        }
    }

    /// The soft, welcoming background wash used behind entry screens. Plain
    /// black in dark mode.
    static var welcomeBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(light: Color(red: 0.96, green: 0.97, blue: 0.99), dark: .black),
                Color(light: Color(red: 0.99, green: 0.99, blue: 1.0), dark: .black),
                Color(light: Color(red: 0.95, green: 0.98, blue: 0.99), dark: .black)
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
