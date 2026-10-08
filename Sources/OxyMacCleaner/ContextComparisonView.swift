import CleanerCore
import SwiftUI

struct ContextComparisonView: View {
  @EnvironmentObject var vm: AppModel
  @State private var showing = false
  @State private var reader: TranscriptReview?
  @State private var page: ReviewPage?
  @State private var offsets: [Int] = []
  @State private var query = ""
  @State private var message = ""
  @State private var findings: TranscriptReview.Findings?
  @State private var reviewProgress = 0.0
  @State private var loading = false
  @State private var operation: Task<Void, Never>?
  @State private var token = Cancellation()
  var body: some View {
    Button(vm.t("Сравнить с исходником", "Compare with source")) { open() }
      .disabled(vm.busy || loading)
      .help(vm.t("Все страницы исходника, поиск текста и ссылок [L…]. Оригинал не изменяется.", "Browse the full source and search text or [L…] references. Original is unchanged."))
      .sheet(isPresented: $showing, onDismiss: { token.cancel(); operation?.cancel() }) {
        VStack(alignment: .leading, spacing: 12) {
          Text(vm.t("Проверка перед переносом", "Review before transfer")).font(.title2.bold())
          Text(vm.t("Ссылки [L…]: строки JSONL или нормализованные записи JSON. Поиск точный, с учётом регистра. Признаки изменений и результатов тестов требуют ручной сверки — это не автоматическое разрешение противоречий.", "[L…] references JSONL lines or normalized JSON records. Search is exact and case-sensitive. Change markers and test outcomes require manual review, not automatic conflict resolution.")).font(.caption)
          HStack {
            TextField(vm.t("Текст или [L123]", "Text or [L123]"), text: $query).onSubmit { search(next: false) }
              .accessibilityLabel(vm.t("Поиск в полной истории", "Search full history"))
            Button(vm.t("Найти", "Find")) { search(next: false) }.disabled(loading || query.isEmpty)
            Button(vm.t("Следующее совпадение", "Next match")) { search(next: true) }.disabled(loading || query.isEmpty)
          }
          HStack {
            Button(vm.t("Назад", "Previous page")) { if let offset = offsets.popLast() { load(offset, remember: false) } }.disabled(loading || offsets.isEmpty)
            Button(vm.t("Далее", "Next page")) { if let page { load(page.next) } }.disabled(loading || page == nil || page!.next >= page!.total)
            if let page { Text("\(page.offset)–\(page.next) / \(page.total) " + vm.t("байт", "bytes")).font(.caption.monospacedDigit()) }
            if loading { ProgressView().controlSize(.small); Button(vm.t("Отмена", "Cancel")) { token.cancel(); operation?.cancel() } }
          }
          if !message.isEmpty { Text(message).font(.caption) }
          HStack {
            Button(vm.t("Проверить изменения во всей истории", "Review changes throughout history")) { review() }.disabled(loading)
              .help(vm.t("Локальный поиск явных изменений требований и результатов тестов. Не определяет, какое решение правильное.", "Locally finds explicit requirement changes and test outcomes. Does not decide which decision is correct."))
            if loading && reviewProgress > 0 { ProgressView(value: reviewProgress).frame(width: 100) }
          }
          if let findings {
            DisclosureGroup(vm.t("Места для проверки: ", "Review signals: ") + String(findings.matches)) {
              Text(vm.t("Показаны первые 200 совпадений. Это подсказки, не доказанные противоречия. Укорочено длинных записей: ", "First 200 matches shown. These are signals, not proven contradictions. Long records inspected by prefix only: ") + String(findings.shortenedRecords)).font(.caption)
              ScrollView {
                LazyVStack(alignment: .leading) {
                  ForEach(findings.items) { item in
                    Button { load(item.offset) } label: { Text(item.excerpt).font(.caption).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }
                      .disabled(loading).help(vm.t("Открыть эту строку в исходнике", "Open this source line"))
                  }
                }
              }.frame(maxHeight: 120)
            }
          }
          HStack(alignment: .top) {
            pane(vm.t("Исходник", "Source"), text: page?.text ?? "")
            pane(vm.t("Результат", "Result"), text: vm.output)
          }
          if let lines = page?.reviewLines, !lines.isEmpty {
            DisclosureGroup(vm.t("На странице есть изменения требований или результаты тестов: ", "Page contains requirement changes or test results: ") + String(lines.count)) {
              ScrollView { Text(lines.joined(separator: "\n")).font(.caption).textSelection(.enabled) }.frame(maxHeight: 100)
            }
          }
          Button(vm.t("Закрыть", "Close")) { showing = false }.keyboardShortcut(.cancelAction)
        }.padding(20).frame(width: 960, height: 700)
      }
  }
  private func open() {
    guard let transcript = vm.transcript else { return }
    loading = true; offsets = []; query = ""; message = ""; findings = nil; reviewProgress = 0
    operation = Task {
      defer { loading = false }
      do {
        let value = try await Task.detached { try TranscriptReview(transcript) }.value
        let first = try await Task.detached { try value.page() }.value
        reader = value; page = first; showing = true
      } catch { vm.error = error.localizedDescription }
    }
  }
  private func review() {
    guard let reader, !loading else { return }
    loading = true; findings = nil; reviewProgress = 0
    token = Cancellation(); let cancellation = token
    operation = Task {
      defer { loading = false; reviewProgress = 0 }
      do {
        let value = try await Task.detached {
          try reader.reviewIndex(cancellation: cancellation) { done, total in
            Task { @MainActor in
              guard loading, token === cancellation, !cancellation.cancelled else { return }
              reviewProgress = Double(done) / Double(max(total, 1))
            }
          }
        }.value
        try cancellation.check(); findings = value; message = ""
      } catch { message = cancellation.cancelled ? vm.t("Проверка остановлена", "Review stopped") : error.localizedDescription }
    }
  }
  private func load(_ offset: Int, remember: Bool = true) {
    guard let reader else { return }; loading = true
    operation = Task {
      defer { loading = false }
      do {
        let result = try await Task.detached { try reader.page(at: offset) }.value
        if remember, let old = page { offsets.append(old.offset) }; page = result; message = ""
      } catch { message = error.localizedDescription }
    }
  }
  private func search(next: Bool) {
    guard let reader, !query.isEmpty, !loading else { return }
    let text = query; let start = next ? min(reader.total, (page?.offset ?? 0) + 1) : 0
    token = Cancellation(); let cancellation = token; loading = true
    operation = Task {
      defer { loading = false }
      do {
        let result = try await Task.detached { () throws -> ReviewPage? in
          guard let offset = try reader.find(text, from: start, cancellation: cancellation) else { return nil }
          return try reader.page(at: offset)
        }.value
        try cancellation.check()
        if let result { if let old = page { offsets.append(old.offset) }; page = result; message = "" }
        else { message = vm.t("Совпадений дальше нет.", "No further matches.") }
      } catch { message = cancellation.cancelled ? vm.t("Поиск остановлен", "Search stopped") : error.localizedDescription }
    }
  }
  private func pane(_ title: String, text: String) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.headline)
      ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.accessibilityLabel(title)
    }.frame(maxWidth: .infinity)
  }
}
