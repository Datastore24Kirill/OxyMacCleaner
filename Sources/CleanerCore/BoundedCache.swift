import Foundation

/// A small, synchronized LRU. Values must be immutable snapshots; no filesystem authority is cached.
final class BoundedCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [(key: Key, value: Value, cost: Int)] = []
  private let capacity: Int
  private let budget: Int
  init(capacity: Int, budget: Int) { self.capacity = capacity; self.budget = budget }
  func value(for key: Key) -> Value? {
    lock.lock(); defer { lock.unlock() }
    guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
    let entry = entries.remove(at: index); entries.append(entry)
    return entry.value
  }
  func insert(_ value: Value, for key: Key, cost: Int) {
    guard capacity > 0, cost >= 0, cost <= budget else { return }
    lock.lock(); defer { lock.unlock() }
    entries.removeAll { $0.key == key }
    while !entries.isEmpty && (entries.count >= capacity || entries.reduce(cost, { $0 + $1.cost }) > budget) {
      entries.removeFirst()
    }
    entries.append((key, value, cost))
  }
}
