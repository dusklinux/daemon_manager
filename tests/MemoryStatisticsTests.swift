import Foundation

@main
struct MemoryStatisticsTests {
    static func main() {
        let snapshot = MemorySnapshot(
            sampledAt: Date(), totalMiB: 3072,
            freeAndSpeculativeMiB: 200, speculativeMiB: 80,
            activeMiB: 400, inactiveMiB: 300, wiredMiB: 800,
            compressorMiB: 256, uncompressedInCompressorMiB: 512,
            purgeableMiB: 60, fileBackedMiB: 100, anonymousMiB: 600)
        precondition(snapshot.physicalFreeMiB == 120, "Speculative pages must be subtracted, not added again")
        precondition(snapshot.freeAndSpeculativeMiB == 200, "The headline must not double-count speculative pages")
        precondition(snapshot.compressionRatio == 2, "Compression ratio must compare original pages to physical compressor occupancy")
        let empty = MemorySnapshot(
            sampledAt: Date(), totalMiB: 3072,
            freeAndSpeculativeMiB: 0, speculativeMiB: 0,
            activeMiB: 0, inactiveMiB: 0, wiredMiB: 0,
            compressorMiB: 0, uncompressedInCompressorMiB: 0,
            purgeableMiB: 0, fileBackedMiB: 0, anonymousMiB: 0)
        precondition(empty.compressionRatio == nil, "An empty compressor has no ratio")
        precondition(MemoryPressure(rawValue: 1) == .normal)
        precondition(MemoryPressure(rawValue: 2) == .warning)
        precondition(MemoryPressure(rawValue: 4) == .critical)
        precondition(MemoryPressure(rawValue: 0) == nil, "Internal VM enum values must not be mistaken for exported flags")
        guard let live = MemorySnapshot.read() else { fatalError("host_statistics64 failed on the build host") }
        precondition(live.totalMiB > 0 && live.freeAndSpeculativeMiB >= live.speculativeMiB)
        precondition(live.physicalFreeMiB >= 0 && live.compressorMiB >= 0)
        print("Memory accounting, pressure flags, empty compressor, and live Mach snapshot passed")
    }
}
