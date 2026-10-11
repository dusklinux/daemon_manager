import SwiftUI

struct MemoryDetailsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var storage: StorageSnapshot?

    private var pressureColor: Color {
        switch model.memoryPressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case nil: return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Memory pressure") {
                    HStack {
                        Circle().fill(pressureColor).frame(width: 10, height: 10)
                        Text(model.memoryPressure?.title ?? "No reading yet")
                            .font(.headline).foregroundColor(pressureColor)
                        Spacer()
                        if model.isReadingMemoryPressure { ProgressView() }
                    }
                    Text("iOS reports Normal, Warning, or Critical. Free memory alone is not a pressure percentage.")
                        .font(.caption).foregroundColor(.secondary)
                    if model.memoryPressure == nil && !model.isReadingMemoryPressure {
                        Text("Check the root password in Tools, then tap Refresh to request the current reading.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                if let memory = model.memorySnapshot {
                    Section("RAM") {
                        memoryRow("Physical RAM", memory.totalMiB)
                        memoryRow("Free + speculative", memory.freeAndSpeculativeMiB)
                        memoryRow("Compressed", memory.compressorMiB)
                    }
                    Section("Compression") {
                        memoryRow("Contents before compression", memory.uncompressedInCompressorMiB)
                        if let ratio = memory.compressionRatio {
                            HStack {
                                Text("Compression ratio")
                                Spacer()
                                Text(String(format: "%.2f×", ratio)).monospacedDigit().foregroundColor(.secondary)
                            }
                        }
                        Text("Compressed is the RAM used by the compressor. The second value is the original size of its stored pages.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("Memory categories") {
                        memoryRow("Physical free", memory.physicalFreeMiB)
                        memoryRow("Speculative", memory.speculativeMiB)
                        memoryRow("Active", memory.activeMiB)
                        memoryRow("Inactive", memory.inactiveMiB)
                        memoryRow("Wired", memory.wiredMiB)
                        memoryRow("Purgeable", memory.purgeableMiB)
                        memoryRow("File-backed", memory.fileBackedMiB)
                        memoryRow("Anonymous", memory.anonymousMiB)
                        Text("Speculative pages cache reclaimable data and are included in Free + speculative. Other categories overlap; do not add these values together. RAM values refresh every two seconds while the app is active. Pressure changes update when iOS reports them.")
                            .font(.caption).foregroundColor(.secondary)
                        Text("Updated \(memory.sampledAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        Text("Memory statistics are unavailable. Tap Refresh to try again.")
                            .foregroundColor(.secondary)
                    }
                }
                Section("Storage") {
                    if let disk = storage {
                        storageRow("Total capacity", disk.totalBytes)
                        storageRow("Available", disk.availableBytes)
                        storageRow("Used", max(0, disk.totalBytes - disk.availableBytes))
                    } else {
                        Text("Storage capacity unavailable").foregroundColor(.secondary)
                    }
                    Text("Lifetime writes, rated write endurance, and wear percentage are unavailable through the verified interface. Capacity is not a disk-health score.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Memory & Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") {
                        storage = StorageSnapshot.read()
                        model.refreshMemoryDetails()
                    }
                        .disabled(model.isReadingMemoryPressure)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            storage = StorageSnapshot.read()
            model.refreshMemoryDetails()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                storage = StorageSnapshot.read()
                model.refreshMemoryDetails()
            }
        }
    }

    private func storageRow(_ title: String, _ bytes: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal))
                .monospacedDigit().foregroundColor(.secondary)
        }
    }

    private func memoryRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: "%.1f MiB", value))
                .monospacedDigit().foregroundColor(.secondary)
        }
    }
}
