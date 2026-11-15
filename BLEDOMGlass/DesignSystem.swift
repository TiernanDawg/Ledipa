import SwiftUI

/// Shared visual constants for the 2.1 interface.
enum MorgDesign {
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    static let background = Color(red: 0.018, green: 0.022, blue: 0.040)
    static let secondaryText = Color.white.opacity(0.58)
    static let hairline = Color.white.opacity(0.12)
}
