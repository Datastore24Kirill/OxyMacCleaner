import Foundation
import CleanerCore

@main struct SemanticQA {
  static func main() async {
    do {
      guard CommandLine.arguments.count == 4 else { throw CleanerError.message("Usage: semantic_context AGENT SOURCE NEW_PRIVATE_DIRECTORY") }
      let source = URL(fileURLWithPath: CommandLine.arguments[2])
      let folder = URL(fileURLWithPath: CommandLine.arguments[3])
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
      let agent = CommandLine.arguments[1]
      let transcript = try agent == "text" ? Transcript.load(source, agent:agent) : Transcript.loadNative(source, agent:agent)
      let backup = try transcript.backup(in: folder.appendingPathComponent("backup"))
      let report = try await LocalModel().semanticContext(transcript, model:"qwen2.5:7b", style:"Сбалансированный", russian:true, diagnostics: { name, response in
        FileManager.default.createFile(atPath:folder.appendingPathComponent(name + ".json").path, contents:Data(response.utf8), attributes:[.posixPermissions:0o600])
      }) { stage in
        let line = "\(stage.kind) \(stage.part)/\(stage.total) retry=\(stage.retry)\n"
        try? FileHandle.standardOutput.write(contentsOf: Data(line.utf8))
      }
      guard try Scanner.hash(source) == transcript.digest, try Scanner.hash(backup) == transcript.digest else { throw CleanerError.message("Integrity mismatch") }
      let encoded = try JSONEncoder().encode(report.facts)
      let review = try JSONEncoder().encode(report.missing)
      FileManager.default.createFile(atPath:folder.appendingPathComponent("accepted.json").path,contents:encoded,attributes:[.posixPermissions:0o600])
      FileManager.default.createFile(atPath:folder.appendingPathComponent("review.json").path,contents:review,attributes:[.posixPermissions:0o600])
      let target = folder.appendingPathComponent("handoff.md")
      try Data(report.text.utf8).write(to:target)
      try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
      print("PASS integrity. bytes=\(report.sourceBytes)->\(report.text.utf8.count), parts=\(report.parts), facts=\(report.facts.count), missing=\(report.missing.count), unreferenced=\(report.unrepresented.count), concerns=\(report.concerns.count). Manual semantic review required.")
    } catch {
      fputs("FAILED: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}
