import Foundation
import XCTest
@testable import CleanerCore

final class PathClassificationOptimizationTests: XCTestCase {
  func testDirectoryMatchingPreservesLiteralSlashBoundaries() {
    let gamePaths = ["steamapps", "gog games", "epic games", "library/application support/minecraft"]
    let appPaths = ["library/application support", "library/containers", "library/group containers"]
    // Extensionless leaves isolate the directory rules from extension classification.
    for directory in gamePaths + appPaths {
      for prefix in ["", "/", "/Users/test/", "relative/", "/prefix", "//"] {
        for suffix in ["", "/", "/payload", "//payload", "extra/payload"] {
          for spelling in [directory, directory.uppercased(), directory.replacingOccurrences(of: "/", with: "//")] {
            let path = prefix + spelling + suffix
            let lower = path.lowercased()
            let expected: FileCategory
            if gamePaths.contains(where: { lower.range(of: "/" + $0 + "/", options: .literal) != nil }) {
              expected = .games
            } else if appPaths.contains(where: { lower.range(of: "/" + $0 + "/", options: .literal) != nil }) {
              expected = .appData
            } else {
              expected = .other
            }
            XCTAssertEqual(FileCategory.classify(path), expected, path)
          }
        }
      }
    }
  }

  func testCategoryPriorityRemainsUnchanged() {
    let cases: [(String, FileCategory)] = [
      ("/steamapps/.docker/payload", .docker),
      ("/steamapps/DerivedData/payload", .derivedData),
      ("/steamapps/release.xcarchive/payload", .xcodeArchive),
      ("/steamapps/Game.app/payload", .games),
      ("/Library/Application Support/Game.app/payload", .applications),
      ("/Library/Application Support/Caches/payload", .caches),
      ("/Library/Application Support/build/payload", .build),
      ("/usr/Library/Application Support/payload", .system),
      ("/Library/Application Support/Minecraft/payload.jpg", .games),
      ("/Library/Application Support/payload.jpg", .appData),
      ("/steamapps/payload.jpg", .games),
      ("/steamapps-extra/payload.jpg", .images),
    ]
    for (path, expected) in cases { XCTAssertEqual(FileCategory.classify(path), expected, path) }
  }

  func testSnapshotProtectionMatchesPublicPolicyAcrossCanonicalBoundaries() {
    let paths = [
      "", "/", "//", "relative", "relative/../Library/payload", ".", "..",
      "/Users/test/plain", "/Users/test/plain/", "/Users/test/plain//payload",
      "/Users/test/./payload", "/Users/test/../payload", "/Users/test/.", "/Users/test/..",
      "/Users/test/...", "/Users/test/.../payload", "/Users/test/.hidden/payload",
      "/Users/test/a./payload", "/Users/test/..a/payload", "/Users/test/a../payload",
      "/Users/test/Library/../payload", "/Users/test/plain/../Library/payload",
      "/Users/test/Library//payload", "/Users/test/Library/./payload",
      "/Users/test/Library-extra/payload", "/Users/test/.git/payload",
      "/Users/test/项目/данные", "/Users/test/项目/../.ssh/key",
      "/Users/test/FILE.SWIFT", "/Volumes/Disk/System/payload",
      "/Volumes/Disk/System-extra/payload", "/Users/test/Application.app/payload",
    ]
    for path in paths {
      XCTAssertEqual(QuarantineStore.protectedSnapshotPath(path), QuarantineStore.protected(path), path)
    }
  }
}
