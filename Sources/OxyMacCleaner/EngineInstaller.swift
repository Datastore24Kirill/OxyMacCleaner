import AppKit
import CleanerCore
import Foundation

extension AppModel {
  func launchOllama() {
    let choices = [
      URL(fileURLWithPath: "/Applications/Ollama.app"),
      home.appendingPathComponent("Applications/Ollama.app"),
    ]
    guard let app = choices.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
      error = t("Сначала установите Ollama.", "Install Ollama first.")
      return
    }
    NSWorkspace.shared.open(app)
  }
  func installOllama() {
    guard !busy else { return }
    let target = home.appendingPathComponent("Applications/Ollama.app")
    if FileManager.default.fileExists(atPath: target.path)
      || FileManager.default.fileExists(atPath: "/Applications/Ollama.app")
    {
      launchOllama()
      return
    }
    guard
      confirm(
        t("Установить Ollama?", "Install Ollama?"),
        t(
          "Загрузка около 200 МБ с официального GitHub Ollama. Подпись проверяется macOS. Установка в ~/Applications без прав администратора. Модель скачивается отдельно. Лицензии: github.com/ollama/ollama",
          "About 200 MB from the official Ollama GitHub. macOS verifies the signature. Installs to ~/Applications without administrator access. Model downloads are separate. Licenses: github.com/ollama/ollama"
        ))
    else { return }
    busy = true
    status = t("Получаю сведения о загрузке…", "Getting download information…")
    let staging = support.appendingPathComponent("Downloads").appendingPathComponent(
      UUID().uuidString)
    task = Task {
      do {
        let (api, response) = try await URLSession.shared.data(
          from: URL(string: "https://api.github.com/repos/ollama/ollama/releases/latest")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
          let j = try JSONSerialization.jsonObject(with: api) as? [String: Any],
          let assets = j["assets"] as? [[String: Any]],
          let asset = assets.first(where: { $0["name"] as? String == "Ollama-darwin.zip" }),
          let link = asset["browser_download_url"] as? String,
          link.hasPrefix("https://github.com/ollama/ollama/releases/download/"),
          let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
          let expected = asset["size"] as? Int
        else { throw CleanerError.message("No verified macOS download available") }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let archive = staging.appendingPathComponent("Ollama.zip")
        status = t("Скачивание Ollama…", "Downloading Ollama…")
        // URLSessionDownloadTask writes to disk rather than accumulating the installer in RAM.
        let downloader = DownloadProgress()
        try await downloader.fetch(URL(string: link)!, to: archive) { done, total in
          Task { @MainActor in
            self.status =
              self.t("Ollama: ", "Ollama: ")
              + String(format: "%.1f / %.1f MB", Double(done) / 1e6, Double(total) / 1e6)
          }
        }
        try Task.checkCancellation()
        let attrs = try FileManager.default.attributesOfItem(atPath: archive.path)
        guard (attrs[.size] as? NSNumber)?.intValue == expected,
          try Scanner.hash(archive) == String(digest.dropFirst(7))
        else { throw CleanerError.message("Installer integrity check failed") }
        status = t("Проверка и установка…", "Verifying and installing…")
        try await Task.detached {
          let listing = try runTool("/usr/bin/unzip", ["-Z1", archive.path])
          guard
            listing.split(separator: "\n").allSatisfy({
              !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..")
            })
          else { throw CleanerError.message("Unsafe archive") }
          _ = try runTool("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
          let app = staging.appendingPathComponent("Ollama.app")
          _ = try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
          _ = try runTool("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
          try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
          try FileManager.default.moveItem(at: app, to: target)
        }.value
        log("Ollama installed with verified hash and Gatekeeper assessment")
        NSWorkspace.shared.open(target)
        status = t(
          "Ollama установлена. Завершите её первый запуск и нажмите «Проверить».",
          "Ollama installed. Finish its first-run setup, then click Check.")
      } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
      try? FileManager.default.removeItem(at: staging)
      busy = false
    }
  }
}
final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private var continuation: CheckedContinuation<Void, Error>?
  private var destination: URL?
  private var progress: ((Int64, Int64) -> Void)?
  private var session: URLSession?
  private var download: URLSessionDownloadTask?
  private let lock = NSLock()
  private var cancelled = false
  func fetch(_ url: URL, to: URL, progress: @escaping (Int64, Int64) -> Void) async throws {
    try await withTaskCancellationHandler(
      operation: {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
          lock.lock()
          defer { lock.unlock() }
          if cancelled {
            c.resume(throwing: CancellationError())
            return
          }
          continuation = c
          destination = to
          self.progress = progress
          let config = URLSessionConfiguration.ephemeral
          config.timeoutIntervalForResource = 1800
          session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
          download = session!.downloadTask(with: url)
          download!.resume()
        }
      },
      onCancel: {
        self.lock.lock()
        self.cancelled = true
        self.download?.cancel()
        self.lock.unlock()
      })
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) { progress?(totalBytesWritten, max(0, totalBytesExpectedToWrite)) }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200
      else { throw CleanerError.message("Download failed") }
      try FileManager.default.moveItem(at: location, to: destination!)
    } catch { finish(error) }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    finish(error)
  }
  private func finish(_ error: Error?) {
    lock.lock()
    let c = continuation
    continuation = nil
    lock.unlock()
    if let error { c?.resume(throwing: error) } else { c?.resume() }
    session?.finishTasksAndInvalidate()
  }
}
