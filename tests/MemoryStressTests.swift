import Foundation
import Compression

@main
struct MemoryStressTests {
    static func main() throws {
        let allocator = MemoryStressAllocator()
        allocator.removeLast()
        precondition(allocator.allocatedBytes == 0)
        let bytes = 2 * 1_048_576
        try allocator.add(bytes: bytes)
        let first = allocator.sample(count: bytes)
        precondition(first.count == bytes)
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes * 2)
        defer { output.deallocate() }
        let compressed = first.withUnsafeBytes { data in
            compression_encode_buffer(output, bytes * 2, data.bindMemory(to: UInt8.self).baseAddress!, bytes, nil, COMPRESSION_ZLIB)
        }
        precondition(compressed > bytes * 95 / 100, "Test data must resist compression")
        try allocator.add(bytes: bytes)
        precondition(allocator.allocatedBytes == bytes * 2)
        precondition(allocator.sample(count: bytes) != first, "Blocks must contain different data")
        allocator.removeLast()
        precondition(allocator.allocatedBytes == bytes)
        var checks = 0
        do {
            try allocator.add(bytes: bytes) { checks += 1; return checks >= 3 }
            fatalError("Cancelled allocation was retained")
        } catch MemoryStressError.cancelled { }
        precondition(allocator.allocatedBytes == bytes, "Cancelled fill must release its partial mapping")
        allocator.clear()
        allocator.clear()
        precondition(allocator.allocatedBytes == 0 && allocator.sample(count: 1).isEmpty)
        do {
            try allocator.add(bytes: 0)
            fatalError("Invalid allocation accepted")
        } catch MemoryStressError.allocation { }
        precondition(ProcessMemorySnapshot.read()?.footprintMiB ?? 0 > 0)
        print("Random-data compression, block accounting, minus, clear, cancellation, invalid request and live process footprint passed")
    }
}
