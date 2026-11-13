import Foundation

@main
struct MemoryStatisticsTests {
    static func main() {
        let snapshot = MemorySnapshot(
            sampledAt: Date(), totalMiB: 3072,
            freeAndSpeculativeMiB: 200, speculativeMiB: 80,
            activeMiB: 400, inactiveMiB: 300, wiredMiB: 800,
            compressorMiB: 256, uncompressedInCompressorMiB: 512,
            purgeableMiB: 60, fileBackedMiB: 100, anonymousMiB: 600,
            throttledMiB: 0,
            lifetimeCompressions: 176_400_000,
            lifetimeDecompressions: 136_657_080,
            lifetimeSwapins: 1_000,
            lifetimeSwapouts: 2_500,
            lifetimePageins: 1_200_000,
            lifetimePageouts: 45_000,
            lifetimeFaults: 520_000_000,
            lifetimeCowFaults: 38_000_000,
            lifetimeZeroFills: 95_000_000,
            lifetimeReactivations: 14_000_000,
            lifetimePurges: 900_000,
            lifetimeLookups: 80_000_000,
            lifetimeHits: 76_000_000,
            pageSizeBytes: 16_384)
        precondition(snapshot.physicalFreeMiB == 120, "Speculative pages must be subtracted, not added again")
        precondition(snapshot.freeAndSpeculativeMiB == 200, "The headline must not double-count speculative pages")
        precondition(snapshot.compressionRatio == 2, "Compression ratio must compare original pages to physical compressor occupancy")
        precondition(snapshot.compressorSpaceSavedMiB == 256, "Compressor space saved must equal uncompressed minus compressed MiB")
        precondition(snapshot.lifetimeCompressedBytes == 176_400_000 * 16_384, "Lifetime compressed bytes must equal compressions * pageSizeBytes")
        precondition(snapshot.lifetimeDecompressedBytes == 136_657_080 * 16_384, "Lifetime decompressed bytes must equal decompressions * pageSizeBytes")
        precondition(snapshot.lifetimeNetCompressedPages == 176_400_000 - 136_657_080, "Net compressed pages must equal compressions minus decompressions")
        precondition(snapshot.lifetimeNetCompressedBytes == (176_400_000 - 136_657_080) * 16_384, "Net compressed bytes must match net pages * pageSizeBytes")
        precondition(snapshot.lifetimeSwapinBytes == 1_000 * 16_384 && snapshot.lifetimeSwapoutBytes == 2_500 * 16_384, "Swap byte conversions must match pageSizeBytes")
        precondition(snapshot.lifetimeZeroFilledBytes == 95_000_000 * 16_384 && snapshot.lifetimeReactivatedBytes == 14_000_000 * 16_384, "Zero-fill and reactivation byte conversions must match pageSizeBytes")
        guard let lifetimeRatio = snapshot.lifetimeDecompressionRatio else {
            fatalError("Lifetime decompression ratio must be non-nil when lifetimeCompressions > 0")
        }
        precondition(abs(lifetimeRatio - 77.47) < 0.01, "Lifetime decompression ratio must calculate ~77.47%")
        guard let cowRatio = snapshot.lifetimeCowFaultRatio else {
            fatalError("CoW fault ratio must be non-nil when lifetimeFaults > 0")
        }
        precondition(abs(cowRatio - 7.30769) < 0.01, "CoW fault ratio must calculate ~7.31%")
        guard let hitRatio = snapshot.lifetimeObjectCacheHitRatio else {
            fatalError("Object cache hit ratio must be non-nil when lifetimeLookups > 0")
        }
        precondition(abs(hitRatio - 95.0) < 0.001, "Object cache hit ratio must calculate 95.00%")

        let empty = MemorySnapshot(
            sampledAt: Date(), totalMiB: 3072,
            freeAndSpeculativeMiB: 0, speculativeMiB: 0,
            activeMiB: 0, inactiveMiB: 0, wiredMiB: 0,
            compressorMiB: 0, uncompressedInCompressorMiB: 0,
            purgeableMiB: 0, fileBackedMiB: 0, anonymousMiB: 0)
        precondition(empty.compressionRatio == nil, "An empty compressor has no ratio")
        precondition(empty.compressorSpaceSavedMiB == 0, "An empty compressor saves 0 MiB")
        precondition(empty.lifetimeCompressions == 0 && empty.lifetimeDecompressions == 0, "Default lifetime counts must be 0")
        precondition(empty.lifetimeDecompressionRatio == nil, "Zero lifetime compressions must yield a nil decompression ratio")
        precondition(empty.lifetimeCowFaultRatio == nil, "Zero lifetime faults must yield a nil CoW fault ratio")
        precondition(empty.lifetimeObjectCacheHitRatio == nil, "Zero lifetime lookups must yield a nil object cache hit ratio")
        precondition(MemorySnapshot.pageBytes(UInt64.max, pageSizeBytes: 16_384) == UInt64.max, "Overflowing byte multiplication must saturate at UInt64.max")

        let mibBytes: UInt64 = 598_900_000 // ~571.2 MiB
        let gibBytes: UInt64 = 2 * 1_073_741_824 + 150_323_855 // ~2.14 GiB
        let tibBytes: UInt64 = 2 * 1_099_511_627_776 + 824_633_720_832 // ~2.75 TiB
        let pibBytes: UInt64 = 1_125_899_906_842_624 // 1.00 PiB
        precondition(MemorySnapshot.formattedDynamicBytes(0) == "0.0 MiB", "Zero bytes must format as 0.0 MiB")
        precondition(MemorySnapshot.formattedDynamicBytes(mibBytes).hasSuffix("MiB"), "Under 1,024 MiB must format as MiB")
        precondition(MemorySnapshot.formattedDynamicMiB(1023.96) == "1.00 GiB", "Values rounding to 1024.0 MiB must promote cleanly to 1.00 GiB")
        precondition(MemorySnapshot.formattedDynamicBytes(gibBytes) == "2.14 GiB", "GiB range must format to 2 decimal places in GiB")
        precondition(MemorySnapshot.formattedDynamicBytes(tibBytes) == "2.75 TiB", "TiB range must format to 2 decimal places in TiB")
        precondition(MemorySnapshot.formattedDynamicBytes(pibBytes) == "1.00 PiB", "PiB range must format to 2 decimal places in PiB")
        precondition(MemorySnapshot.formattedEventCount(999_950) == "1.0M events", "Boundary event counts must promote cleanly without 1000.0K")

        precondition(MemoryPressure(rawValue: 1) == .normal)
        precondition(MemoryPressure(rawValue: 2) == .warning)
        precondition(MemoryPressure(rawValue: 4) == .critical)
        precondition(MemoryPressure(rawValue: 0) == nil, "Internal VM enum values must not be mistaken for exported flags")
        guard let live = MemorySnapshot.read() else { fatalError("host_statistics64 failed on the build host") }
        precondition(live.totalMiB > 0 && live.freeAndSpeculativeMiB >= live.speculativeMiB)
        precondition(live.physicalFreeMiB >= 0 && live.compressorMiB >= 0)
        precondition(live.pageSizeBytes > 0)
        print("Memory accounting, full lifetime VM & compressor stats, dynamic byte formatting, pressure flags, and live Mach snapshot passed")
    }
}
