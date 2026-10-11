import Foundation

struct StorageSnapshot {
    let totalBytes: Int64
    let availableBytes: Int64

    static func read() -> StorageSnapshot? {
        // The user's data filesystem, rather than the read-only system volume.
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = values[.systemSize] as? NSNumber,
              let available = values[.systemFreeSize] as? NSNumber else { return nil }
        return StorageSnapshot(totalBytes: total.int64Value, availableBytes: available.int64Value)
    }
}
