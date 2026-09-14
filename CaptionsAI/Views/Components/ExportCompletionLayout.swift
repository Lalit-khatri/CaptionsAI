import CoreGraphics

/// Geometry for the export-completion screen, as plain arithmetic.
///
/// The screen it serves needs a `Project`, an `ExportViewModel`, a StoreKit
/// environment and a finished export before it will draw anything, so nothing
/// in a test can reach it. These numbers can be reached, which is the point of
/// moving them here.
///
/// Nothing in this file is new behaviour. Every value is the one `ExportView`
/// already drew with; they are pulled out of the view body so that the commit
/// which changes one has to say so in its own diff.
enum ExportCompletionLayout {
    /// The success thumbnail is a portrait card. 140 x 210 today, so 2:3.
    static let heroAspectRatio: CGFloat = 140.0 / 210.0

    /// How tall the success thumbnail is, given the height of the area it has
    /// to fill.
    ///
    /// A constant 210pt was the reason this screen looked wrong: it is 35% of
    /// an iPhone SE and 23% of a Pro Max, so the taller the phone the more the
    /// content read as a small cluster adrift in the middle. A share of the
    /// viewport keeps the proportion steady instead.
    ///
    /// The floor matters more than the ceiling. A container that has not been
    /// measured yet proposes 0, and without the floor the hero would collapse
    /// on the first layout pass and pop open on the second.
    static func heroHeight(forViewportHeight viewport: CGFloat) -> CGFloat {
        max(200, min(viewport * 0.44, 340))
    }

    /// What the pinned footer is assumed to take, when deciding how much of
    /// the screen the content above it should stretch to fill.
    ///
    /// The footer measures 126pt at the default text size and grows with it;
    /// this is a deliberate slight over-estimate. Being wrong costs a few
    /// points of scroll on an already-full screen and nothing else — the
    /// footer is pinned by `safeAreaInset`, so its reachability does not
    /// depend on this number being right.
    static let footerReserve: CGFloat = 140

    /// Vertical padding inside the "Done" button.
    ///
    /// 10pt measured 38pt tall, under Apple's 44pt minimum touch target and
    /// the only control on the screen that was. 14pt measures 46pt.
    static let doneVerticalPadding: CGFloat = 14
}
