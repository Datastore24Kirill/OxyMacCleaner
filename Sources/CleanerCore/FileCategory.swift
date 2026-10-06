import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
  case derivedData = "DerivedData"
  case xcodeArchive = "Xcode Archive"
  case build = "Build"
  case applications = "Applications"
  case games = "Games"
  case appData = "App Data"
  case caches = "Caches"
  case images = "Images"
  case video = "Video"
  case audio = "Audio"
  case documents = "Documents"
  case archive = "Archive"
  case source = "Source"
  case system = "System"
  case other = "File"

  public var russian: String {
    switch self {
    case .derivedData: return "Кэш Xcode"
    case .xcodeArchive: return "Архивы Xcode"
    case .build: return "Сборки и зависимости"
    case .applications: return "Программы"
    case .games: return "Данные игр"
    case .appData: return "Данные приложений"
    case .caches: return "Кэши"
    case .images: return "Фото и изображения"
    case .video: return "Видео"
    case .audio: return "Аудио"
    case .documents: return "Документы"
    case .archive: return "Архивы и установщики"
    case .source: return "Исходный код"
    case .system: return "Системные файлы"
    case .other: return "Другие файлы"
    }
  }
  public var english: String { self == .other ? "Other files" : rawValue }
  public static func classify(_ path: String) -> Self {
    let url = URL(fileURLWithPath: path)
    let parts = url.pathComponents.map { $0.lowercased() }
    let lower = path.lowercased()
    if parts.contains("deriveddata") { return .derivedData }
    if parts.contains(where: { $0.hasSuffix(".xcarchive") }) { return .xcodeArchive }
    if lower.contains("/steamapps/") || lower.contains("/gog games/")
      || lower.contains("/epic games/") || lower.contains("/library/application support/minecraft/")
    {
      return .games
    }
    if parts.contains(where: { $0.hasSuffix(".app") }) { return .applications }
    if parts.contains("caches") || parts.contains(".cache") { return .caches }
    if parts.contains("node_modules") || parts.contains(".build") || parts.contains("build")
      || parts.contains("pods") || parts.contains(".gradle")
    {
      return .build
    }
    if lower.hasPrefix("/system/") || lower.hasPrefix("/usr/") || lower.hasPrefix("/bin/")
      || lower.hasPrefix("/sbin/")
    {
      return .system
    }
    if lower.contains("/library/application support/") || lower.contains("/library/containers/")
      || lower.contains("/library/group containers/")
    {
      return .appData
    }
    if parts.contains(where: { $0.hasSuffix(".photoslibrary") }) { return .images }
    let ext = url.pathExtension.lowercased()
    if [
      "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "avif", "tif", "tiff", "bmp", "svg",
      "raw", "dng", "cr2", "cr3", "nef", "arw", "raf", "psd", "ai", "exr",
    ].contains(ext) {
      return .images
    }
    if ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mpg", "mpeg", "mts", "m2ts", "wmv", "flv"]
      .contains(ext)
    {
      return .video
    }
    if [
      "mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "ogg", "opus", "wma", "alac", "mid",
      "midi",
    ].contains(ext) {
      return .audio
    }
    if ["zip", "dmg", "pkg", "ipa", "xip", "tar", "gz", "bz2", "xz", "7z", "rar", "iso", "zst"]
      .contains(ext)
    {
      return .archive
    }
    if [
      "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf",
      "odt", "ods", "epub", "csv",
    ].contains(ext) {
      return .documents
    }
    if [
      "swift", "m", "mm", "h", "c", "cpp", "hpp", "py", "js", "jsx", "ts", "tsx", "json", "yml",
      "yaml", "html", "css", "scss", "java", "kt", "rs", "go", "rb", "php", "sh", "md", "sql",
      "dart",
    ].contains(ext) {
      return .source
    }
    return .other
  }
}
