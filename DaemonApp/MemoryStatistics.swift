import Foundation
import Darwin

struct ProcessMemorySnapshot {
    let footprintMiB: Double
    let headroomMiB: Double?

    static func read() -> ProcessMemorySnapshot? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        #if os(iOS)
        let headroom: Double? = Double(os_proc_available_memory()) / 1_048_576.0
        #else
        let headroom: Double? = nil
        #endif
        return ProcessMemorySnapshot(footprintMiB: Double(info.phys_footprint) / 1_048_576.0, headroomMiB: headroom)
    }
}

// XNU host_statistics64 free_count already includes speculative_count.
struct MemorySnapshot {
    let sampledAt: Date
    let totalMiB: Double
    let freeAndSpeculativeMiB: Double
    let speculativeMiB: Double
    let activeMiB: Double
    let inactiveMiB: Double
    let wiredMiB: Double
    let compressorMiB: Double
    let uncompressedInCompressorMiB: Double
    let purgeableMiB: Double
    let fileBackedMiB: Double
    let anonymousMiB: Double
    let throttledMiB: Double

    let lifetimeCompressions: UInt64
    let lifetimeDecompressions: UInt64
    let lifetimeSwapins: UInt64
    let lifetimeSwapouts: UInt64
    let lifetimePageins: UInt64
    let lifetimePageouts: UInt64
    let lifetimeFaults: UInt64
    let lifetimeCowFaults: UInt64
    let lifetimeZeroFills: UInt64
    let lifetimeReactivations: UInt64
    let lifetimePurges: UInt64
    let lifetimeLookups: UInt64
    let lifetimeHits: UInt64
    let pageSizeBytes: Int

    init(
        sampledAt: Date,
        totalMiB: Double,
        freeAndSpeculativeMiB: Double,
        speculativeMiB: Double,
        activeMiB: Double,
        inactiveMiB: Double,
        wiredMiB: Double,
        compressorMiB: Double,
        uncompressedInCompressorMiB: Double,
        purgeableMiB: Double,
        fileBackedMiB: Double,
        anonymousMiB: Double,
        throttledMiB: Double = 0,
        lifetimeCompressions: UInt64 = 0,
        lifetimeDecompressions: UInt64 = 0,
        lifetimeSwapins: UInt64 = 0,
        lifetimeSwapouts: UInt64 = 0,
        lifetimePageins: UInt64 = 0,
        lifetimePageouts: UInt64 = 0,
        lifetimeFaults: UInt64 = 0,
        lifetimeCowFaults: UInt64 = 0,
        lifetimeZeroFills: UInt64 = 0,
        lifetimeReactivations: UInt64 = 0,
        lifetimePurges: UInt64 = 0,
        lifetimeLookups: UInt64 = 0,
        lifetimeHits: UInt64 = 0,
        pageSizeBytes: Int = 16_384
    ) {
        self.sampledAt = sampledAt
        self.totalMiB = totalMiB
        self.freeAndSpeculativeMiB = freeAndSpeculativeMiB
        self.speculativeMiB = speculativeMiB
        self.activeMiB = activeMiB
        self.inactiveMiB = inactiveMiB
        self.wiredMiB = wiredMiB
        self.compressorMiB = compressorMiB
        self.uncompressedInCompressorMiB = uncompressedInCompressorMiB
        self.purgeableMiB = purgeableMiB
        self.fileBackedMiB = fileBackedMiB
        self.anonymousMiB = anonymousMiB
        self.throttledMiB = throttledMiB
        self.lifetimeCompressions = lifetimeCompressions
        self.lifetimeDecompressions = lifetimeDecompressions
        self.lifetimeSwapins = lifetimeSwapins
        self.lifetimeSwapouts = lifetimeSwapouts
        self.lifetimePageins = lifetimePageins
        self.lifetimePageouts = lifetimePageouts
        self.lifetimeFaults = lifetimeFaults
        self.lifetimeCowFaults = lifetimeCowFaults
        self.lifetimeZeroFills = lifetimeZeroFills
        self.lifetimeReactivations = lifetimeReactivations
        self.lifetimePurges = lifetimePurges
        self.lifetimeLookups = lifetimeLookups
        self.lifetimeHits = lifetimeHits
        self.pageSizeBytes = pageSizeBytes
    }

    var physicalFreeMiB: Double { max(0, freeAndSpeculativeMiB - speculativeMiB) }

    var compressionRatio: Double? {
        compressorMiB > 0 ? uncompressedInCompressorMiB / compressorMiB : nil
    }

    var compressorSpaceSavedMiB: Double {
        max(0, uncompressedInCompressorMiB - compressorMiB)
    }

    static func pageBytes(_ pages: UInt64, pageSizeBytes: Int) -> UInt64 {
        let safePageSize = UInt64(max(0, pageSizeBytes))
        let (product, overflow) = pages.multipliedReportingOverflow(by: safePageSize)
        return overflow ? UInt64.max : product
    }

    var lifetimeCompressedBytes: UInt64 {
        Self.pageBytes(lifetimeCompressions, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeDecompressedBytes: UInt64 {
        Self.pageBytes(lifetimeDecompressions, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeNetCompressedPages: UInt64 {
        lifetimeCompressions >= lifetimeDecompressions
            ? lifetimeCompressions - lifetimeDecompressions
            : 0
    }

    var lifetimeNetCompressedBytes: UInt64 {
        Self.pageBytes(lifetimeNetCompressedPages, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeSwapinBytes: UInt64 {
        Self.pageBytes(lifetimeSwapins, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeSwapoutBytes: UInt64 {
        Self.pageBytes(lifetimeSwapouts, pageSizeBytes: pageSizeBytes)
    }

    var lifetimePageinBytes: UInt64 {
        Self.pageBytes(lifetimePageins, pageSizeBytes: pageSizeBytes)
    }

    var lifetimePageoutBytes: UInt64 {
        Self.pageBytes(lifetimePageouts, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeZeroFilledBytes: UInt64 {
        Self.pageBytes(lifetimeZeroFills, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeReactivatedBytes: UInt64 {
        Self.pageBytes(lifetimeReactivations, pageSizeBytes: pageSizeBytes)
    }

    var lifetimePurgedBytes: UInt64 {
        Self.pageBytes(lifetimePurges, pageSizeBytes: pageSizeBytes)
    }

    var lifetimeDecompressionRatio: Double? {
        lifetimeCompressions > 0
            ? (Double(lifetimeDecompressions) / Double(lifetimeCompressions)) * 100.0
            : nil
    }

    var lifetimeCowFaultRatio: Double? {
        lifetimeFaults > 0
            ? (Double(lifetimeCowFaults) / Double(lifetimeFaults)) * 100.0
            : nil
    }

    var lifetimeObjectCacheHitRatio: Double? {
        lifetimeLookups > 0
            ? (Double(lifetimeHits) / Double(lifetimeLookups)) * 100.0
            : nil
    }

    static func formattedDynamicMiB(_ mib: Double) -> String {
        let clamped = max(0.0, mib)
        // Check against rounded thresholds so 1023.96 MiB becomes 1.00 GiB rather than 1024.0 MiB.
        if (clamped * 10.0).rounded() < 10_240.0 {
            return String(format: "%.1f MiB", clamped)
        }
        let gib = clamped / 1_024.0
        if (gib * 100.0).rounded() < 102_400.0 {
            return String(format: "%.2f GiB", gib)
        }
        let tib = gib / 1_024.0
        if (tib * 100.0).rounded() < 102_400.0 {
            return String(format: "%.2f TiB", tib)
        }
        let pib = tib / 1_024.0
        return String(format: "%.2f PiB", pib)
    }

    static func formattedDynamicBytes(_ bytes: UInt64) -> String {
        formattedDynamicMiB(Double(bytes) / 1_048_576.0)
    }

    func formattedDynamicBytes(_ bytes: UInt64) -> String {
        Self.formattedDynamicBytes(bytes)
    }

    static func formattedEventCount(_ count: UInt64) -> String {
        if count < 1_000 {
            return "\(count) events"
        }
        let thousands = Double(count) / 1_000.0
        if (thousands * 10.0).rounded() < 10_000.0 {
            return String(format: "%.1fK events", thousands)
        }
        let millions = Double(count) / 1_000_000.0
        if (millions * 10.0).rounded() < 10_000.0 {
            return String(format: "%.1fM events", millions)
        }
        let billions = Double(count) / 1_000_000_000.0
        if (billions * 100.0).rounded() < 100_000.0 {
            return String(format: "%.2fB events", billions)
        }
        let trillions = Double(count) / 1_000_000_000_000.0
        return String(format: "%.2fT events", trillions)
    }

    static func read() -> MemorySnapshot? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let unit = Double(pageSize) / 1_048_576.0
        return MemorySnapshot(
            sampledAt: Date(),
            totalMiB: Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0,
            freeAndSpeculativeMiB: Double(stats.free_count) * unit,
            speculativeMiB: Double(stats.speculative_count) * unit,
            activeMiB: Double(stats.active_count) * unit,
            inactiveMiB: Double(stats.inactive_count) * unit,
            wiredMiB: Double(stats.wire_count) * unit,
            compressorMiB: Double(stats.compressor_page_count) * unit,
            uncompressedInCompressorMiB: Double(stats.total_uncompressed_pages_in_compressor) * unit,
            purgeableMiB: Double(stats.purgeable_count) * unit,
            fileBackedMiB: Double(stats.external_page_count) * unit,
            anonymousMiB: Double(stats.internal_page_count) * unit,
            throttledMiB: Double(stats.throttled_count) * unit,
            lifetimeCompressions: stats.compressions,
            lifetimeDecompressions: stats.decompressions,
            lifetimeSwapins: stats.swapins,
            lifetimeSwapouts: stats.swapouts,
            lifetimePageins: stats.pageins,
            lifetimePageouts: stats.pageouts,
            lifetimeFaults: stats.faults,
            lifetimeCowFaults: stats.cow_faults,
            lifetimeZeroFills: stats.zero_fill_count,
            lifetimeReactivations: stats.reactivations,
            lifetimePurges: stats.purges,
            lifetimeLookups: stats.lookups,
            lifetimeHits: stats.hits,
            pageSizeBytes: Int(pageSize)
        )
    }
}

enum MemoryPressure: Int32 {
    // The sysctl exports NOTE_MEMORYSTATUS dispatch flags, not internal VM levels.
    case normal = 1
    case warning = 2
    case critical = 4

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    static func read() -> MemoryPressure? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return nil }
        return MemoryPressure(rawValue: value)
    }
}
