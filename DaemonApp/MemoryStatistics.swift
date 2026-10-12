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

    var physicalFreeMiB: Double { max(0, freeAndSpeculativeMiB - speculativeMiB) }
    var compressionRatio: Double? {
        compressorMiB > 0 ? uncompressedInCompressorMiB / compressorMiB : nil
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
            sampledAt: Date(), totalMiB: Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0,
            freeAndSpeculativeMiB: Double(stats.free_count) * unit,
            speculativeMiB: Double(stats.speculative_count) * unit,
            activeMiB: Double(stats.active_count) * unit,
            inactiveMiB: Double(stats.inactive_count) * unit,
            wiredMiB: Double(stats.wire_count) * unit,
            compressorMiB: Double(stats.compressor_page_count) * unit,
            uncompressedInCompressorMiB: Double(stats.total_uncompressed_pages_in_compressor) * unit,
            purgeableMiB: Double(stats.purgeable_count) * unit,
            fileBackedMiB: Double(stats.external_page_count) * unit,
            anonymousMiB: Double(stats.internal_page_count) * unit)
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
