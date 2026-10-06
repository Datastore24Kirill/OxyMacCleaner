import SwiftUI

/// Wait for an existing operation (e.g. snapshot restoration) before the first read.
/// Each presentation attempts at most once, so errors and empty inventories do not retry in a loop.
struct InventoryLoading: ViewModifier {
  @EnvironmentObject var vm: AppModel
  let isLoaded: Bool
  let load: () -> Void
  @State private var attempted = false
  func body(content: Content) -> some View {
    content.onAppear { loadIfReady() }
      .onChange(of: vm.busy) { _, busy in if !busy { loadIfReady() } }
  }
  private func loadIfReady() {
    guard !attempted, !isLoaded, !vm.busy else { return }
    attempted = true
    load()
  }
}
