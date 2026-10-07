import CleanerCore
import SwiftUI

private final class UpdateRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    let host = request.url?.host ?? ""
    completionHandler(request.url?.scheme == "https" && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(host) ? request : nil)
  }
}
@MainActor final class AppUpdater: ObservableObject {
  @Published var release: AppRelease?
  @Published var status = ""
  @Published var busy = false
  @Published var installing = false
  private var checkedOnLaunch = false
  func checkOnLaunch() {
    guard !checkedOnLaunch else { return }; checkedOnLaunch = true
    if UserDefaults.standard.object(forKey: "automaticUpdateCheck") as? Bool ?? true { check() }
  }
  @Published var fraction: Double = 0
  private let session = URLSession(configuration: .ephemeral, delegate: UpdateRedirect(), delegateQueue: nil)
  private func download(_ url: URL, limit: Int, to destination: URL? = nil) async throws -> Data {
    let session = self.session
    let transfer = Task.detached(priority: .utility) { () throws -> Data in
      let (bytes,response) = try await session.bytes(from: url)
      guard let response = response as? HTTPURLResponse, response.statusCode == 200,
        response.expectedContentLength <= limit else { throw CleanerError.message("Update download failed or exceeded size limit") }
      var data = Data(); data.reserveCapacity(min(limit, 8_000_000))
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < limit else { throw CleanerError.message("Update exceeds size limit") }
        data.append(byte)
        if data.count % 65536 == 0 {
          let progress = response.expectedContentLength > 0 ? Double(data.count) / Double(response.expectedContentLength) : 0
          await MainActor.run { self.fraction = progress }
        }
      }
      if let destination { try data.write(to: destination, options: .atomic) }
      await MainActor.run { self.fraction = 1 }
      return data
    }
    return try await withTaskCancellationHandler(operation: { try await transfer.value }, onCancel: { transfer.cancel() })
  }

  func check() {
    guard !busy else { return }; busy = true; fraction = 0; status = "Проверяем релизы…"
    Task {
      defer { busy = false }
      do {
        let data = try await download(URL(string: "https://api.github.com/repos/Datastore24Kirill/OxyMacCleaner/releases?per_page=20")!, limit: 2_000_000)
        release = try AppRelease.parse(data, current: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
        status = release.map { "Доступна версия " + $0.version } ?? "Установлена актуальная версия"
      } catch { status = error.localizedDescription }
    }
  }
  func install() {
    guard !busy, let release else { return }
    busy = true; installing = true; fraction = 0; status = "Скачиваем обновление…"
    Task {
      var stage: URL?
      var launched = false
      defer { busy = false; installing = false; if !launched, let stage { try? FileManager.default.removeItem(at: stage) } }
      do {
        let app = Bundle.main.bundleURL.standardizedFileURL
        guard app.pathExtension == "app", app.resolvingSymlinksInPath() == app,
          FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
          throw CleanerError.message("Move the app to a writable Applications folder before updating")
        }
        let folder = app.deletingLastPathComponent().appendingPathComponent(".OxyMacUpdate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); stage = folder
        let zip = folder.appendingPathComponent("update.zip")
        _ = try await download(release.archive, limit: 100_000_000, to: zip)
        let checksum = try await download(release.checksums, limit: 65536)
        let expected = try release.expectedHash(String(decoding: checksum, as: UTF8.self))
        status = "Проверяем сборку…"
        let staged = try await Task.detached { () throws -> URL in
          guard try Scanner.hash(zip) == expected else { throw CleanerError.message("Update checksum mismatch") }
          let listing = try DeveloperCommand.run("/usr/bin/unzip", ["-Z1", zip.path])
          try AppRelease.validateEntries(String(decoding: listing, as: UTF8.self))
          let totals = String(decoding: try DeveloperCommand.run("/usr/bin/zipinfo", ["-t", zip.path]), as: UTF8.self)
          let expression = try NSRegularExpression(pattern: "([0-9]+) bytes uncompressed")
          let totalText = totals as NSString
          guard let match = expression.firstMatch(in: totals, range: NSRange(location: 0, length: totalText.length)),
            let expanded = Int64(totalText.substring(with: match.range(at: 1))), expanded < 500_000_000 else {
            throw CleanerError.message("Expanded update is too large")
          }
          let types = try DeveloperCommand.run("/usr/bin/zipinfo", ["-l", zip.path])
          guard !String(decoding: types, as: UTF8.self).split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else { throw CleanerError.message("Symbolic links in update are not supported") }
          let unpacked = folder.appendingPathComponent("unpacked")
          try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: false)
          _ = try DeveloperCommand.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
          let next = unpacked.appendingPathComponent("OxyMac Cleaner.app")
          let plist = try Data(contentsOf: next.appendingPathComponent("Contents/Info.plist"))
          let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
          guard info?["CFBundleIdentifier"] as? String == "com.oxyfire.OxyMacCleaner",
            info?["CFBundleExecutable"] as? String == "OxyMacCleaner",
            info?["CFBundleShortVersionString"] as? String == release.version else { throw CleanerError.message("Unexpected application in update") }
          _ = try DeveloperCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", next.path])
          return next
        }.value
        let script = folder.appendingPathComponent("install.sh")
        try Self.script.write(to: script, atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), app.path, staged.path, folder.path]
        let log = folder.appendingPathComponent("update.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
        try process.run(); launched = true
        status = "Перезапускаем. При сбое вернётся предыдущая версия."
        NSApplication.shared.terminate(nil)
      } catch { status = error.localizedDescription }
    }
  }
  static let script = #"""
  set -eu
  old_pid="$1"; app="$2"; next="$3"; stage="$4"
  backup="$stage/previous.app"
  n=0
  while kill -0 "$old_pid" 2>/dev/null; do
    n=$((n+1)); [ "$n" -lt 60 ] || exit 1
    sleep 1
  done
  /bin/mv "$app" "$backup"
  if ! /bin/mv "$next" "$app"; then /bin/mv "$backup" "$app"; /usr/bin/open "$app"; exit 1; fi
  "$app/Contents/MacOS/OxyMacCleaner" --oxy-update-health "$stage/healthy" &
  child=$!
  n=0
  while [ "$n" -lt 45 ]; do
    if [ -f "$stage/healthy" ]; then echo 'Update launched successfully; previous.app retained'; exit 0; fi
    n=$((n+1)); sleep 1
  done
  echo 'No launch confirmation; restoring previous version'
  kill -TERM "$child" 2>/dev/null || true
  sleep 2
  if kill -0 "$child" 2>/dev/null; then echo 'New app still running; manual recovery required. Backup retained.'; exit 1; fi
  /bin/mv "$app" "$stage/failed.app"
  /bin/mv "$backup" "$app"
  /usr/bin/open "$app"
  """#
  static func markHealthy() {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "--oxy-update-health"), args.indices.contains(index+1) else { return }
    let file = URL(fileURLWithPath: args[index+1]).standardizedFileURL
    let parent = file.deletingLastPathComponent()
    guard file.lastPathComponent == "healthy", parent.lastPathComponent.hasPrefix(".OxyMacUpdate-"),
      parent.deletingLastPathComponent() == Bundle.main.bundleURL.deletingLastPathComponent(),
      parent.resolvingSymlinksInPath() == parent else { return }
    try? Data("ready".utf8).write(to: file, options: .atomic)
  }
}
struct AppUpdateView: View {
  @EnvironmentObject var vm: AppModel
  @EnvironmentObject var updater: AppUpdater
  @AppStorage("automaticUpdateCheck") private var automatic = true
  var body: some View {
    VStack(alignment: .leading) {
      Toggle(vm.t("Проверять при запуске", "Check at launch"), isOn: $automatic)
      Text(updater.status)
      if updater.busy {
        ProgressView(value: updater.fraction)
        Text("\(Int(updater.fraction * 100)) %").font(.caption.monospacedDigit())
      }
      Button(vm.t("Проверить обновления", "Check for updates")) { updater.check() }.disabled(updater.busy || vm.busy)
      if let release = updater.release {
        Button(vm.t("Обновить до ", "Update to ") + release.version) { updater.install() }.disabled(updater.busy || vm.busy)
      }
      Text(vm.t("Источник — GitHub проекта. Проверяем SHA-256 и целостность подписи. Подпись Developer ID пока отсутствует. Предыдущая версия сохраняется рядом с приложением для отката; после обновления macOS может снова запросить доступ.", "Source: project GitHub. SHA-256 and signature integrity are checked. Developer ID is not available yet. The previous version is retained beside the app for rollback; macOS may ask for access again.")).font(.caption)
    }
  }
}
