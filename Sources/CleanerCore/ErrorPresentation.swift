import Foundation

public enum ErrorPresentation {
  public static func message(_ raw: String, russian: Bool) -> String {
    let text = raw.lowercased()
    let common: (String, String)?
    if text.contains("cancel") { common = ("Операция остановлена. Проверьте её результат в истории операций.", "Operation stopped. Check its result in operation history.") }
    else if text.contains("checksum") || text.contains("integrity") || text.contains("copied file differs") { common = ("Проверка целостности не прошла. Не удаляйте исходную копию. Повторите загрузку или проверьте носитель.", "Integrity verification failed. Keep the original copy. Retry the download or check the disk.") }
    else if text.contains("connection refused") || text.contains("could not connect") || text.contains("cannot connect") { common = ("Нет соединения с локальным движком. Откройте «Локальный движок», запустите Ollama и проверьте состояние.", "Cannot connect to the local engine. Open Local engine, launch Ollama and check its status.") }
    else if text.contains("model") && text.contains("not found") { common = ("Выбранная модель не найдена. В разделе «Локальный движок» выберите установленную или скачайте модель.", "The selected model was not found. Select an installed model or download one in Local engine.") }
    else if text.contains("destination") && (text.contains("exists") || text.contains("changed")) { common = ("По выбранному пути уже есть данные или назначение изменилось. Выберите другую папку либо имя.", "The destination exists or has changed. Choose another folder or name.") }
    else if text.contains("no space") || text.contains("insufficient space") { common = ("Не хватает места на целевом диске. Исходные копии не удаляйте; освободите место и повторите операцию.", "The destination disk has insufficient space. Keep the source copies, free space and retry.") }
    else if text.contains("no such file") || text.contains("disconnected") || text.contains("offline") { common = ("Объект или диск недоступен. Подключите диск и обновите список.", "The item or disk is unavailable. Reconnect the disk and refresh the list.") }
    else { common = nil }
    if let common { return (russian ? common.0 + "\n\nПодробности: " : common.1 + "\n\nDetails: ") + raw }
    guard russian else { return raw }
    let value = raw.lowercased()
    let hint: String
    if value.contains("permission") || value.contains("not permitted") || value.contains("access denied") {
      hint = "Нет доступа к объекту. Проверьте подключение диска и раздел «Доступ к диску» в настройках приложения."
    } else if value.contains("space") && (value.contains("no ") || value.contains("insufficient")) {
      hint = "Недостаточно свободного места для операции. Освободите место на целевом диске и повторите попытку."
    } else if value.contains("changed") || value.contains("scan again") {
      hint = "Данные изменились после проверки. Обновите список и заново проверьте выбранные объекты."
    } else if value.contains("integrity") || value.contains("checksum") || value.contains("differs") {
      hint = "Проверка целостности не прошла. Проверьте исходник и копию; не удаляйте их до выяснения причины."
    } else if value.contains("destination already exists") || value.contains("destination changed") {
      hint = "По выбранному пути уже есть данные. Выберите другое имя или другую папку для восстановления."
    } else if value.contains("unrecognized") || value.contains("unsupported") || value.contains("jsonl") {
      hint = "Формат файла не поддержан или повреждён. Выберите одну историю нужного агента либо импортируйте текстовый экспорт."
    } else if value.contains("connect") || value.contains("local engine") || value.contains("ollama") {
      hint = "Проверьте, что Ollama запущена, а локальная модель установлена. Затем повторите операцию."
    } else if value.contains("protected") || value.contains("active") || value.contains("xcodebuild") {
      hint = "Объект защищён или используется. Проверьте причину блокировки и состояние сборок; принудительное удаление не выполняется."
    } else { return raw }
    return hint + "\n\nПодробности: " + raw
  }
}
