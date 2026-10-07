import Foundation

enum ErrorPresentation {
  static func message(_ raw: String, russian: Bool) -> String {
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
