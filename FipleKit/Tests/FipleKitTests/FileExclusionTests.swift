import Foundation
import Testing
@testable import FipleKit

@Suite("File exclusion filter")
struct FileExclusionTests {
    @Test("hidden / dotfiles are excluded")
    func excludesHidden() {
        #expect(FileExclusion.isExcluded(fileName: ".DS_Store", relativePath: ".DS_Store"))
        #expect(FileExclusion.isExcluded(fileName: ".gitignore", relativePath: "proj/.gitignore"))
    }

    @Test("app / installer / package bundles are excluded by extension")
    func excludesBundles() {
        #expect(FileExclusion.isExcluded(fileName: "Xcode.app", relativePath: "Xcode.app"))
        #expect(FileExclusion.isExcluded(fileName: "Installer.dmg", relativePath: "Installer.dmg"))
        #expect(FileExclusion.isExcluded(fileName: "Photos.photoslibrary", relativePath: "Photos.photoslibrary"))
        #expect(FileExclusion.isExcluded(fileName: "half.crdownload", relativePath: "half.crdownload"))
    }

    @Test("ordinary documents are not excluded")
    func keepsDocuments() {
        #expect(!FileExclusion.isExcluded(fileName: "Q3.key", relativePath: "Decks/Q3.key"))
        #expect(!FileExclusion.isExcluded(fileName: "report.pdf", relativePath: "report.pdf"))
        #expect(!FileExclusion.isExcluded(fileName: "notes.md", relativePath: "notes.md"))
    }

    @Test("user-ignored subfolders are excluded on a path boundary")
    func excludesIgnoredSubfolders() {
        let ignored = ["Private", "Work/Secret"]
        #expect(FileExclusion.isExcluded(fileName: "diary.txt", relativePath: "Private/diary.txt", ignoredSubfolders: ignored))
        #expect(FileExclusion.isExcluded(fileName: "plan.md", relativePath: "Work/Secret/plan.md", ignoredSubfolders: ignored))
        // "Workshop" must not match the "Work" boundary of "Work/Secret".
        #expect(!FileExclusion.isExcluded(fileName: "a.txt", relativePath: "Workshop/a.txt", ignoredSubfolders: ignored))
        // "Private" as a bare prefix of another folder name shouldn't match.
        #expect(!FileExclusion.isExcluded(fileName: "b.txt", relativePath: "PrivateStuff/b.txt", ignoredSubfolders: ignored))
    }
}
