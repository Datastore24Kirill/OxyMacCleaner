import XCTest
@testable import CleanerCore

final class AllocatedScanTests: XCTestCase {
  func testSparseFileAndHardLinkKeepLogicalAndAllocatedSeparate() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OxySparse-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("disk.raw")
    try Data("fixture".utf8).write(to: file)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 64 * 1024 * 1024); try handle.close()
    try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("alias.raw"))
    var latest = ScanProgress()
    let report = Scanner.scan(roots: [root], excluded: [], cancellation: Cancellation(), progress: { latest = $0 })
    XCTAssertEqual(report.files.count, 1)
    XCTAssertEqual(latest.bytes, 64 * 1024 * 1024)
    let allocated = try XCTUnwrap(latest.allocatedBytes)
    XCTAssertLessThan(allocated, latest.bytes)
    XCTAssertEqual(allocated, try FileRecord.read(file).allocated)
    let saved = SavedScan(roots: [root], volumeID: "fixture", report: report, progress: latest)
    let adjusted = ScanReconciliation.removing(report.files.map(\.path), from: saved)
    XCTAssertEqual(adjusted.progress.allocatedBytes, 0)
  }
  func testLegacyProgressLoadsAndAllocationIsRecoveredFromRecords() throws {
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ScanProgress())) as? [String: Any])
    json.removeValue(forKey: "allocatedBytes")
    let old = try JSONDecoder().decode(ScanProgress.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertNil(old.allocatedBytes)
    var report = ScanReport()
    report.files = [FileRecord(path: "/fixture/a", bytes: 1_000_000, allocated: 4096, modified: Date(), inode: 1, device: 1, links: 1)]
    let saved = SavedScan(roots: [URL(fileURLWithPath: "/fixture")], volumeID: "test", report: report, progress: old)
    XCTAssertEqual(saved.progress.allocatedBytes, 4096)
    let encoded = try JSONEncoder().encode(saved.progress)
    XCTAssertEqual(try JSONDecoder().decode(ScanProgress.self, from: encoded).allocatedBytes, 4096)
  }
}
