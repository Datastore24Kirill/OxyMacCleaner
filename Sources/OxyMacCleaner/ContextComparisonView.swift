import CleanerCore
import SwiftUI

struct ContextComparisonView: View {
  var reference: Int? = nil
  @EnvironmentObject var vm: AppModel
  @State private var showing = false
  @State private var reader: TranscriptReview?
  @State private var page: ReviewPage?
  @State private var offsets: [Int] = []
  @State private var query = ""
  @State private var message = ""
  @State private var findings: TranscriptReview.Findings?
  @State private var signalFilter = "all"
  @State private var onlyMissing = false
  @State private var signalsExpanded = false
  @State private var pairsExpanded = false
  @State private var reviewProgress = 0.0
  @State private var loading = false
  @State private var operation: Task<Void, Never>?
  @State private var token = Cancellation()
  var body: some View {
    Button(reference.map { "[L\($0)] " + vm.t("в исходнике", "in source") } ?? vm.t("Сравнить с исходником", "Compare with source")) { open() }
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
            DisclosureGroup(vm.t("Места для проверки: ", "Review signals: ") + String(findings.matches), isExpanded: $signalsExpanded) {
              Text(vm.t("Показано до 200 совпадений на странице. Это подсказки, не доказанные противоречия. Укорочено длинных записей: ", "Up to 200 matches per page. These are signals, not proven contradictions. Long records inspected by prefix only: ") + String(findings.shortenedRecords)).font(.caption)
              HStack {
                Text("\(findings.skipped + (findings.items.isEmpty ? 0 : 1))–\(findings.skipped + findings.items.count) / \(findings.matches)").font(.caption.monospacedDigit())
                Button(vm.t("К началу", "First page")) { review() }.disabled(loading || findings.skipped == 0)
                Button(vm.t("Следующие 200", "Next 200")) { review(after: findings.nextOffset) }.disabled(loading || findings.nextOffset == nil)
              }
              Toggle(vm.contextAudit == nil ? vm.t("Только фрагменты, не найденные в результате", "Only fragments not found in result") : vm.t("Только строки без ссылки в результате", "Only unreferenced source lines"), isOn: $onlyMissing)
              Text((vm.contextAudit == nil ? vm.t("Текст не найден среди показанных фрагментов: ", "Displayed fragments not found: ") : vm.t("Нет ссылки на показанные строки: ", "Displayed lines without references: ")) + String(findings.items.filter { !represented($0) }.count))
                .font(.caption).foregroundStyle(.orange)
              Text(vm.contextAudit == nil ? vm.t("Сравниваются точные фрагменты после скрытия секретов. Совпадение фрагмента не подтверждает полноту длинной записи или актуальность решения.", "Exact fragments are compared after secret redaction. A match does not confirm the full long record or that a decision is current.") : vm.t("Для пересказа проверяем наличие ссылки, а не совпадение формулировки. Ссылка не доказывает сохранение всего смысла строки.", "For a summary, this checks references rather than exact wording. A reference does not prove that all meaning was retained.")).font(.caption)
              Picker(vm.t("Показать", "Show"), selection: $signalFilter) {
                Text(vm.t("Все подсказки", "All signals")).tag("all")
                ForEach(TranscriptReview.Signal.allCases, id: \.rawValue) { signal in
                  Text(signal.title(russian: vm.language != "en")).tag(signal.rawValue)
                }
              }.pickerStyle(.menu)
              if findings.items.filter({ matchesFilter($0) }).isEmpty {
                Text(vm.t("На этой странице нет подсказок этого типа. Это не доказывает, что их нет в истории.", "No signals of this type on this page. This does not prove absence from the history.")).font(.caption)
              }
              ScrollView {
                LazyVStack(alignment: .leading) {
                  ForEach(findings.items.filter { matchesFilter($0) }) { item in
                    Button { load(item.offset) } label: {
                      VStack(alignment: .leading, spacing: 4) {
                        Text(item.signals.map { $0.title(russian: vm.language != "en") }.joined(separator: " · ")).bold()
                        if !represented(item) {
                          Label(vm.contextAudit == nil ? vm.t("Фрагмент не найден в результате", "Fragment not found in result") : vm.t("Нет ссылки в результате", "No reference in result"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        Text(item.excerpt).fixedSize(horizontal: false, vertical: true)
                      }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }.buttonStyle(.plain)
                      .disabled(loading).help(vm.t("Открыть эту строку в исходнике", "Open this source line"))
                  }
                }
              }.frame(height: 145)
            }
          }
          if let findings {
            let pairs = TranscriptReview.decisionPairs(in: findings.items)
            DisclosureGroup(vm.t("Связанные решения для сверки: ", "Related decisions to compare: ") + String(pairs.count), isExpanded: $pairsExpanded) {
              Text(vm.t("Совпадение слов на текущей странице, до 50 пар. Связи между страницами могут быть пропущены. Это не доказательство противоречия: проверьте проект, автора и смысл. Более поздняя строка не становится автоматически действующей.", "Shared words on this page, up to 50 pairs. Cross-page links may be missed. This does not prove a conflict: check the project, author and meaning. A later line is not automatically authoritative.")).font(.caption)
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                  ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: 4) {
                      Text(pair.attributionKnown
                        ? vm.t("Одинаковые явные метки пользователя и проекта", "Matching explicit user and project labels")
                        : vm.t("Автор или проект не определён — проверьте принадлежность", "Author or project unknown — verify attribution"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                      Button { load(pair.earlier.offset) } label: {
                        VStack(alignment: .leading) { Text(vm.t("Ранее", "Earlier")).bold(); Text(pair.earlier.excerpt) }
                      }
                      Button { load(pair.later.offset) } label: {
                        VStack(alignment: .leading) { Text(vm.t("Позднее", "Later")).bold(); Text(pair.later.excerpt) }
                      }
                    }.buttonStyle(.plain).font(.caption).disabled(loading)
                      .help(vm.t("Открыть выбранную строку исходника; решение принимаете вы.", "Open the selected source line; you decide which applies."))
                    }
                  }
                }
              }.frame(height: 100)
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
        }.padding(20).frame(width: 960, height: 760)
          .onChange(of: signalsExpanded) { _, expanded in if expanded { pairsExpanded = false } }
          .onChange(of: pairsExpanded) { _, expanded in if expanded { signalsExpanded = false } }
      }
  }
  private func represented(_ item: TranscriptReview.Finding) -> Bool {
    guard vm.contextAudit != nil else { return item.fragmentPresent(in: vm.output) }
    guard item.excerpt.hasPrefix("[L"), let end = item.excerpt.firstIndex(of: "]"),
      let line = Int(item.excerpt[item.excerpt.index(item.excerpt.startIndex, offsetBy: 2)..<end]) else { return false }
    return ContextSafety.citations(vm.output).contains(line)
  }
  private func matchesFilter(_ item: TranscriptReview.Finding) -> Bool {
    (signalFilter == "all" || item.signals.contains { $0.rawValue == signalFilter })
      && (!onlyMissing || !represented(item))
  }
  private func open() {
    guard let transcript = vm.transcript else { return }
    loading = true; offsets = []; query = ""; message = ""; findings = nil; reviewProgress = 0; signalFilter = "all"; onlyMissing = false; signalsExpanded = false; pairsExpanded = false
    operation = Task {
      defer { loading = false }
      do {
        let value = try await Task.detached { try TranscriptReview(transcript) }.value
        let target = reference
        let first = try await Task.detached {
          let offset = try target.flatMap { try value.findSourceLine($0) } ?? 0
          return try value.page(at: offset)
        }.value
        reader = value; page = first; showing = true
      } catch { vm.error = ErrorPresentation.message(error.localizedDescription, russian: vm.language != "en") }
    }
  }
  private func review(after: Int? = nil) {
    guard let reader, !loading else { return }
    loading = true; findings = nil; reviewProgress = 0
    token = Cancellation(); let cancellation = token
    operation = Task {
      defer { loading = false; reviewProgress = 0 }
      do {
        let value = try await Task.detached {
          try reader.reviewIndex(after: after, cancellation: cancellation) { done, total in
            Task { @MainActor in
              guard loading, token === cancellation, !cancellation.cancelled else { return }
              reviewProgress = Double(done) / Double(max(total, 1))
            }
          }
        }.value
        try cancellation.check(); findings = value; message = ""
      } catch { message = cancellation.cancelled ? vm.t("Проверка остановлена", "Review stopped") : ErrorPresentation.message(error.localizedDescription, russian: vm.language != "en") }
    }
  }
  private func load(_ offset: Int, remember: Bool = true) {
    guard let reader else { return }; loading = true
    operation = Task {
      defer { loading = false }
      do {
        let result = try await Task.detached { try reader.page(at: offset) }.value
        if remember, let old = page { offsets.append(old.offset) }; page = result; message = ""
      } catch { message = ErrorPresentation.message(error.localizedDescription, russian: vm.language != "en") }
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
      } catch { message = cancellation.cancelled ? vm.t("Поиск остановлен", "Search stopped") : ErrorPresentation.message(error.localizedDescription, russian: vm.language != "en") }
    }
  }
  private func pane(_ title: String, text: String) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.headline)
      ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.accessibilityLabel(title)
    }.frame(maxWidth: .infinity)
  }
}
