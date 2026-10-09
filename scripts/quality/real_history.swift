import Foundation
import CleanerCore

// Explicitly selected local history only; never writes to the source or publishes its text.
@main struct RealHistoryQA {
  static func main() async throws {
    guard CommandLine.arguments.count == 4 else { fatalError("Usage: real_history AGENT SOURCE NEW_PRIVATE_OUTPUT_DIRECTORY") }
    let source = URL(fileURLWithPath: CommandLine.arguments[2])
    let output = URL(fileURLWithPath: CommandLine.arguments[3])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let transcript = try Transcript.loadNative(source, agent: CommandLine.arguments[1])
    let backup = try transcript.backup(in: output.appendingPathComponent("backup"))
    let result = try await LocalModel().summarize(transcript, model: "qwen2.5:7b", style: "Бережный") { print("Part", $0) }
    guard try Scanner.hash(source) == transcript.digest, try Scanner.hash(backup) == transcript.digest else { throw CleanerError.message("Source or backup mismatch") }
    let destination = output.appendingPathComponent("handoff.md")
    try Data(result.utf8).write(to: destination, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    let reader = try TranscriptReview(transcript)
    var cursor: Int?; var count = 0; var missing = 0
    repeat {
      let page = try reader.reviewIndex(after: cursor)
      count += page.items.count; missing += page.items.filter { !$0.fragmentPresent(in: result) }.count
      cursor = page.nextOffset
    } while cursor != nil
    print("PASS integrity; messages=\(transcript.nativeHistory?.messages ?? 0), retained=\(transcript.nativeHistory?.retainedRecords ?? 0), reviewSignals=\(count), exactFragmentsAbsent=\(missing), outputBytes=\(result.utf8.count). Semantic acceptance requires manual review.")
  }
}
