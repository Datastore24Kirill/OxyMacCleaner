import Foundation
import CleanerCore
let n = Int(CommandLine.arguments.dropFirst().first ?? "100000")!
let decoder = JSONDecoder()
let files = try (0..<n).map { i in
  let json = "{\"path\":\"/Users/test/.cocoapods/repos/specs/\(i / 3)/File-\(i).json\",\"bytes\":\(i+1),\"allocated\":4096,\"modified\":0,\"inode\":\(i),\"device\":1,\"links\":1}"
  return try decoder.decode(FileRecord.self, from: Data(json.utf8))
}
let index = try FileBrowserIndex(files: files, excluded: [], quarantine: "/q", downloads: "/d")
var query = FileBrowserIndex.Query()
let start=Date(); let result=try index.filter(query)
print("cold count=\(n) matches=\(result.matches) seconds=\(Date().timeIntervalSince(start))")
query.limit=400
let page=Date(); let next=try index.filter(query)
print("page400 rows=\(next.rows.count) seconds=\(Date().timeIntervalSince(page))")
