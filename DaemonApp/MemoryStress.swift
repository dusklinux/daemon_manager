import Foundation
import Combine
import Darwin

enum MemoryStressError: LocalizedError {
    case allocation(Int32)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .allocation(let code): return "Memory allocation failed: \(String(cString: strerror(code)))"
        case .cancelled: return nil
        }
    }
}

// Owned by one serial worker. Separate mappings let minus/Clear return pages
// directly to the VM instead of leaving them cached in malloc's heap.
final class MemoryStressAllocator {
    static let stepBytes = 100 * 1_048_576
    private var blocks: [(pointer: UnsafeMutableRawPointer, bytes: Int)] = []
    var allocatedBytes: Int { blocks.reduce(0) { $0 + $1.bytes } }

    func add(bytes: Int = stepBytes, shouldCancel: () -> Bool = { false }) throws {
        guard bytes > 0 else { throw MemoryStressError.allocation(EINVAL) }
        guard !shouldCancel() else { throw MemoryStressError.cancelled }
        let mapping = mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard mapping != MAP_FAILED, let pointer = mapping else { throw MemoryStressError.allocation(errno) }
        var retained = false
        defer { if !retained { munmap(pointer, bytes) } }
        var offset = 0
        while offset < bytes {
            guard !shouldCancel() else { throw MemoryStressError.cancelled }
            let count = min(1_048_576, bytes - offset)
            // New random bytes throughout every block, not a repeated page or
            // a zero fill. Writing commits the pages; idle blocks aren't polled.
            arc4random_buf(pointer.advanced(by: offset), count)
            offset += count
            Thread.sleep(forTimeInterval: 0.001)
        }
        guard !shouldCancel() else { throw MemoryStressError.cancelled }
        blocks.append((pointer, bytes))
        retained = true
    }

    func removeLast() {
        guard let block = blocks.popLast() else { return }
        munmap(block.pointer, block.bytes)
    }

    func clear() {
        for block in blocks { munmap(block.pointer, block.bytes) }
        blocks.removeAll(keepingCapacity: false)
    }

    // A diagnostic sample for the allocator tests, never used to rewrite held pages.
    func sample(count: Int) -> Data {
        guard let block = blocks.last else { return Data() }
        return Data(bytes: block.pointer, count: min(max(count, 0), block.bytes))
    }

    deinit { clear() }
}

private final class MemoryStressCancellation {
    private let lock = NSLock()
    private var generation = 0
    func current() -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
    }
}

final class MemoryStressModel: ObservableObject {
    @Published private(set) var allocatedBytes = 0
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var processMemory: ProcessMemorySnapshot?
    private let worker = DispatchQueue(label: "com.dusklinux.DaemonApp.memory-stress", qos: .userInitiated)
    private let allocator = MemoryStressAllocator()
    private let cancellation = MemoryStressCancellation()

    func add() { perform { try $0.add(shouldCancel: $1) } }
    func subtract() { perform { allocator, _ in allocator.removeLast() } }

    func clear() {
        cancellation.cancel()
        // Runs after an interrupted fill; all mapping ownership stays on worker.
        perform(force: true) { allocator, _ in allocator.clear() }
    }

    func refreshProcessMemory() { processMemory = ProcessMemorySnapshot.read() }

    private func perform(force: Bool = false, operation: @escaping (MemoryStressAllocator, () -> Bool) throws -> Void) {
        guard force || !isWorking else { return }
        isWorking = true
        error = nil
        let token = cancellation.current()
        let allocator = self.allocator
        let cancellation = self.cancellation
        worker.async { [weak self] in
            var failure: String?
            do { try operation(allocator, { cancellation.current() != token }) }
            catch { failure = (error as? MemoryStressError)?.errorDescription ?? error.localizedDescription }
            let bytes = allocator.allocatedBytes
            DispatchQueue.main.async { [weak self] in
                guard let self, cancellation.current() == token else { return }
                self.allocatedBytes = bytes
                self.isWorking = false
                self.error = failure
                self.refreshProcessMemory()
            }
        }
    }

    deinit { cancellation.cancel() }
}
