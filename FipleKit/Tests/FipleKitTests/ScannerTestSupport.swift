import Foundation
@testable import FipleKit

/// A scanner whose "last used" signal is the modification date alone.
///
/// The production default is Finder truth (Spotlight last-open + mtime +
/// added-to-folder date) — but a real file created inside a test is always
/// "just used" under that signal, because its added-to-folder date is the
/// moment the test wrote it. Tests therefore drive time through the backdated
/// modification date instead; the thresholding/eviction logic under test is
/// identical either way.
func mtimeScanner(
    stalenessThreshold: TimeInterval = 60 * 86_400,
    reviewWindow: TimeInterval = 7 * 86_400
) -> StaleFileScanner {
    StaleFileScanner(
        stalenessThreshold: stalenessThreshold,
        reviewWindow: reviewWindow,
        lastUsed: { _, values in values.contentModificationDate }
    )
}
