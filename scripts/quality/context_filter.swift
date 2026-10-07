import Foundation
import CleanerCore
let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
if CommandLine.arguments.contains("--ground") {
  let object = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! [String: String]
  print(try ContextSafety.groundedExcerpt(object["proposal"]!, source: object["source"]!), terminator: "")
} else { print(ContextSafety.redact(input), terminator: "") }
