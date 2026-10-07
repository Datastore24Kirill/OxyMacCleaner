import Foundation
import CleanerCore

@main struct LongContextQA {
  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OxyLongContext-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("history.md")
    let text = "Пользователь: лимит архивов 3. Оригинал истории никогда не удалять.\n"
      + "Инструмент: " + String(repeating: "debug line without proof of completion; ", count: 450)
      + "\nПользователь: вместо лимита 3 теперь лимит 7. Только локально, без сети.\n"
      + "Инструмент: " + String(repeating: "still investigating output; ", count: 450)
      + "\nТест testRecovery FAILED. testExport PASSED. Исправление НЕ выполнено. Релиз НЕ опубликован.\n"
      + "Пользователь: секрет password=LongSyntheticSecret12345 не переносить. Следующий шаг: исправить testRecovery.\n"
    try text.write(to: input, atomically: true, encoding: .utf8)
    let transcript = try Transcript.load(input, agent: "codex")
    let model = LocalModel()
    let result = try await model.summarize(transcript, model: "qwen2.5:7b", style: "Бережный") { print("Part", $0) }
    for required in ["лимит 7", "никогда не удалять", "testRecovery FAILED", "testExport PASSED", "НЕ опубликован"] {
      guard result.contains(required) else { throw CleanerError.message("Missing acceptance anchor: " + required) }
    }
    guard !result.contains("LongSyntheticSecret12345"), try String(contentsOf: input) == text else { throw CleanerError.message("Secret leak or original changed") }
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try result.write(to: output, atomically: true, encoding: .utf8)
    print("PASS: multi-part requirements, prohibition, conflicting tests and redaction; manual review still required")
  }
}
