import Foundation

/// Fixed-size ring buffer that never allocates after init.
/// Used for the dB waveform display — O(1) append, O(n) read.
struct RingBuffer<T> {
    private var storage: [T]
    private var writeIndex = 0
    private(set) var count = 0
    let capacity: Int
    /// Incremented on every append — lets consumers skip toArray() when unchanged.
    private(set) var generation: UInt64 = 0

    init(capacity: Int, defaultValue: T) {
        self.capacity = capacity
        self.storage = Array(repeating: defaultValue, count: capacity)
    }

    /// Append a value. Overwrites oldest if full.
    mutating func append(_ value: T) {
        storage[writeIndex] = value
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
        generation &+= 1
    }

    /// Append multiple values.
    mutating func append(contentsOf values: [T]) {
        for v in values { append(v) }
    }

    /// Read all values in chronological order (oldest first).
    func toArray() -> [T] {
        guard count > 0 else { return [] }
        if count < capacity {
            return Array(storage[0..<count])
        }
        // Wrap around: read from writeIndex to end, then start to writeIndex
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }

    /// Most recent value.
    var last: T? {
        guard count > 0 else { return nil }
        let idx = (writeIndex - 1 + capacity) % capacity
        return storage[idx]
    }

    mutating func removeAll() {
        writeIndex = 0
        count = 0
        generation = 0
    }
}
