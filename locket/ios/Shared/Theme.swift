import SwiftUI

// Design tokens for the app and both extensions. The rules behind them are in
// locket/ios/DESIGN.md (taste-skill app-screen rules + Vercel interface guidelines):
// true black ground, surfaces one tone step up, no shadows or gradients at rest,
// one accent (Locket yellow) on data and on at most one control per screen.

enum Palette {
    /// Page ground.
    static let ground = Color.black
    /// Cards, fields, chips: one tone step above the ground (#111).
    static let surface = Color(white: 0.067)
    /// Nested surfaces, skeletons, toasts (#222).
    static let raised = Color(white: 0.133)
    /// Lines on a surface (#2e2e2e).
    static let border = Color(white: 0.18)
    /// Outlined controls, one step stronger than lines (#444).
    static let control = Color(white: 0.267)

    static let text = Color.white
    /// Secondary text (#b4b4b4, 9.6:1 on black).
    static let muted = Color(white: 0.706)
    /// Meta text and placeholders (#949494, 6.9:1 on black).
    static let faint = Color(white: 0.58)

    /// Locket yellow. Data (stars, your reactions, the leader) and at most one control per screen.
    static let accent = Color(red: 1.0, green: 0.78, blue: 0.0)
    /// Fill behind a selected reaction or star chip, always paired with an accent stroke
    /// so the choice also reads by shape (feed, notification, widget).
    static let accentTint = accent.opacity(0.2)
    /// Behind text and controls laid over a photo.
    static let scrim = Color.black.opacity(0.55)
    /// Text on the accent or on a white fill.
    static let onFill = Color.black
    /// Fills on the notification's system material, which can be light or dark.
    static let systemFill = Color.primary.opacity(0.08)

    static let positive = Color(red: 0.247, green: 0.753, blue: 0.478) // #3fc07a
    static let negative = Color(red: 0.898, green: 0.337, blue: 0.435) // #e5566f
}

/// Nested radii step down: photo frame > card > control > chip (capsule).
enum Radius {
    static let photo: CGFloat = 24
    static let card: CGFloat = 20
    static let control: CGFloat = 14
    /// Skeleton lines standing in for text.
    static let line: CGFloat = 6
}

/// One gutter everywhere: the same value horizontally and vertically.
enum Space {
    static let margin: CGFloat = 20
    static let gap: CGFloat = 16
    /// Between a section header and its content, on every screen.
    static let header: CGFloat = 12
    static let cardPadding: CGFloat = 20
    static let section: CGFloat = 40
    static let controlHeight: CGFloat = 50
    static let hitTarget: CGFloat = 44
}

/// Two avatar sizes: rows and stacks use `small`, a person's own row uses `regular`.
enum AvatarSize {
    static let small: CGFloat = 32
    static let regular: CGFloat = 40
}

// Type: one grotesk (SF Pro) on the system text styles so Dynamic Type works.
// Five sizes per screen at most: title 28 · title3 20 · body 17 · subheadline 15 · footnote 13.
// Weights: regular, semibold, bold (bold only for the screen title).

/// Non-breaking space: keeps a number with its unit ("11 очков", "3 фото").
let nbsp = "\u{00A0}"
