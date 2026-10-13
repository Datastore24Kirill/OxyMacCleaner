import Foundation
import CleanerCore
import Darwin
setbuf(stdout, nil)

// Read-only. Pass an existing snapshot explicitly; output contains counts/timings, no paths.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let start = Date()
let saved = try ScanStore(url: url).load()!
print("RESTORE files=\(saved.report.files.count) seconds=\(Date().timeIntervalSince(start))")
let home = FileManager.default.homeDirectoryForCurrentUser
let index = try FileBrowserIndex(files: saved.report.files, excluded: [], quarantine: home.appendingPathComponent("Library/Application Support/OxyMacCleaner/Quarantine").path, downloads: home.appendingPathComponent("Downloads").path)
var query = FileBrowserIndex.Query(); query.text = "Downloads/"
for pass in 1...2 {
  let began = Date(); let result = try index.filter(query)
  print("FILES pass=\(pass) matches=\(result.matches) rows=\(result.rows.count) seconds=\(Date().timeIntervalSince(began))")
}
query.limit = 400
let began = Date(); let page = try index.filter(query)
print("PAGE400 rows=\(page.rows.count) seconds=\(Date().timeIntervalSince(began))")
let disk = DiskIndex(report: saved.report)
for pass in 1...2 {
  let began = Date(); let result = try disk.nodes(in: "/")
  print("MAP pass=\(pass) children=\(result.0.count) seconds=\(Date().timeIntervalSince(began))")
}
