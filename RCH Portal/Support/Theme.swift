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
    static let ink = Color(red: 0.16, green: 0.15, blue: 0.32)

    // The five "leaf" accent colours from the RCH logo.
    static let red = Color(red: 0.85, green: 0.23, blue: 0.18)
    static let orange = Color(red: 0.94, green: 0.55, blue: 0.17)
    static let yellow = Color(red: 0.96, green: 0.76, blue: 0.11)
    static let green = Color(red: 0.49, green: 0.71, blue: 0.24)
    static let teal = Color(red: 0.13, green: 0.62, blue: 0.74)

    /// A secondary accent for the linked "proxy" account colour treatment.
    static let proxy = Color(red: 0.56, green: 0.35, blue: 0.64)

    /// Ordered leaf palette for cycling accents across items.
    static let leaves: [Color] = [red, orange, yellow, green, teal]

    /// The soft, welcoming background wash used behind entry screens.
    static var welcomeBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.99, green: 0.99, blue: 1.0),
                Color(red: 0.95, green: 0.98, blue: 0.99)
            ],
            startPoint: .top,
            endPoint: .bottom)
    }
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Theme.brand }
}
