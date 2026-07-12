import AppKit
import SwiftUI

/// Central animation duration/curve system. Every animated view in Flipbook should route
/// through here rather than hardcoding durations, so both `accessibilityReduceMotion` and
/// the user's Settings > Display "animation speed" multiplier compose correctly in one place.
public enum AnimationTokens {
    private static let standardBase: Double = 0.28
    private static let quickBase: Double = 0.15
    private static let pageTurnBase: Double = 0.45

    /// Resolves an effective duration given Reduce Motion and the user's speed multiplier.
    /// Reduce Motion collapses everything toward-instant rather than simply disabling animation,
    /// so state changes still read as connected without any large-scale motion.
    public static func duration(
        base: Double,
        reduceMotion: Bool,
        speedMultiplier: Double
    ) -> Double {
        if reduceMotion { return min(base * speedMultiplier, 0.05) }
        return base * speedMultiplier
    }

    public static func standard(reduceMotion: Bool = false, speedMultiplier: Double = 1.0) -> Animation {
        .smooth(duration: duration(base: standardBase, reduceMotion: reduceMotion, speedMultiplier: speedMultiplier))
    }

    public static func quick(reduceMotion: Bool = false, speedMultiplier: Double = 1.0) -> Animation {
        .smooth(duration: duration(base: quickBase, reduceMotion: reduceMotion, speedMultiplier: speedMultiplier))
    }

    public static func pageTurn(reduceMotion: Bool = false, speedMultiplier: Double = 1.0) -> Animation {
        if reduceMotion {
            return .smooth(duration: duration(base: pageTurnBase, reduceMotion: true, speedMultiplier: speedMultiplier))
        }
        return .interpolatingSpring(duration: pageTurnBase * speedMultiplier, bounce: 0.12)
    }

    /// Convenience defaults that honor the system Reduce Motion setting on every access.
    /// Call sites that also want the user's animation-speed preference should use the
    /// parameterized variants via `AppModel.animation(_:)`.
    public static var standard: Animation { standard(reduceMotion: systemReduceMotion) }
    public static var quick: Animation { quick(reduceMotion: systemReduceMotion) }
    public static var pageTurnDefault: Animation { pageTurn(reduceMotion: systemReduceMotion) }

    private static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
