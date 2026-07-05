import SwiftUI

/// Small design-system constants for consistent spacing, radii, and accents.
public enum Theme {
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
    }
    public enum Radius {
        public static let chip: CGFloat = 6   // small overlay chrome (thumbnails, glass readouts)
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 22
    }
    /// Brand accent (teal-ish, medical-imaging feel without being clinical).
    public static let accent = Color(red: 0.16, green: 0.66, blue: 0.78)
}

public extension ShapeStyle where Self == Color {
    /// App accent shortcut.
    static var brand: Color { Theme.accent }
}
