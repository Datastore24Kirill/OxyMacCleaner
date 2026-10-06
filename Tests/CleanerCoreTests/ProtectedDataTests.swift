import XCTest
@testable import CleanerCore

final class ProtectedDataTests: XCTestCase {
  func testProtectedLocationsAndPackagesRegardlessOfCase() {
    for path in [
      "/Users/test/Library/Preferences/a.plist", "/Users/test/Library/Caches/a.dat",
      "/Users/test/Pictures/Family.PHOTOSLIBRARY/originals/photo.jpg",
      "/Users/test/project/App.XCODEPROJ/project.pbxproj",
      "/Users/test/Downloads/App.DSYM/Contents/Resources/DWARF/App",
      "/Users/test/.CURSOR/chats/a.json", "/Users/test/.local/share/opencode/a.db",
      "/Users/test/backup.sparsebundle/bands/0", "/Users/test/keys/signing.PFX",
      "/Users/test/App.entitlements", "/Users/test/Package.resolved",
      "/System/Volumes/Data/Users/test/a.txt", "/opt/homebrew/bin/tool",
      "/Applications/Tool.APP/Contents/data", "/dev/disk0",
      "/Volumes/Backup/usr/bin/tool", "/Volumes/Old Mac/System/boot/file",
    ] { XCTAssertTrue(QuarantineStore.protected(path), path) }
    XCTAssertFalse(QuarantineStore.protected("/Users/test/Downloads/old-installer.zip"))
  }
  func testProtectedPackageCannotLoseIndividualFileOrWholeFolder() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Downloads/OxyProtectionTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let package = root.appendingPathComponent("Family.PHOTOSLIBRARY")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    let photo = package.appendingPathComponent("original.jpg")
    try Data("unique photo".utf8).write(to: photo)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    XCTAssertThrowsError(try store.move(FileRecord.read(photo)))
    XCTAssertThrowsError(try store.moveDirectory(package, expected: DirectoryManifest.capture(package)))
    XCTAssertEqual(try Data(contentsOf: photo), Data("unique photo".utf8))
    XCTAssertTrue(store.entries().isEmpty)
  }
  func testAssetBesideXcodeProjectWithoutGitIsProtected() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Downloads/OxyProtectionTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = root.appendingPathComponent("Project")
    try FileManager.default.createDirectory(at: project.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
    let asset = project.appendingPathComponent("logo.png")
    try Data("original".utf8).write(to: asset)
    let store = try QuarantineStore(root: root.appendingPathComponent("quarantine"))
    XCTAssertThrowsError(try store.move(FileRecord.read(asset)))
    XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
  }
  func testDerivedDataProtectsSigningKeysAndRepositoryMetadata() {
    for path in ["/cache/.AWS/credentials", "/cache/signing.PFX", "/cache/.ENV.local",
                 "/cache/.hg/store/data", "/cache/login.keychain-db"] {
      XCTAssertTrue(DerivedData.protectedContent(path), path)
    }
    XCTAssertFalse(DerivedData.protectedContent("/cache/objects/generated.o"))
  }
}
