import SwiftUI

struct MemoryDetailsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var stress = MemoryStressModel()

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
                Section("Memory stress test") {
                    memoryRow("Test allocation", Double(stress.allocatedBytes) / 1_048_576.0)
                    HStack {
                        Button("+100 MiB") { stress.add() }
                            .disabled(stress.isWorking || scenePhase != .active)
                        Button("−100 MiB") { stress.subtract() }
                            .disabled(stress.isWorking || stress.allocatedBytes == 0)
                        Spacer()
                        Button("Clear") { stress.clear() }
                            .disabled(!stress.isWorking && stress.allocatedBytes == 0)
                    }
                    .buttonStyle(.bordered)
                    if stress.isWorking { ProgressView("Updating allocation…") }
                    if let process = stress.processMemory {
                        memoryRow("App footprint", process.footprintMiB)
                        if let headroom = process.headroomMiB { memoryRow("App allocation headroom", headroom) }
                    }
                    if let error = stress.error { Text(error).font(.caption).foregroundColor(.red) }
                    Text("Each addition writes varied random data into 100 MiB. Held pages are not continually rewritten. Pressure can compress other pages or terminate apps; this is a stress test, not additional RAM. Clear releases test memory. Closing this sheet or backgrounding releases it automatically. App headroom is advisory and can change; Jetsam limits still apply.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("2 GiB inflation worker") {
                    if let status = model.duskMemoryStatus {
                        memoryRow("Worker allocation", Double(status.bytes) / 1_048_576)
                        Text(status.title).font(.caption)
                        if status.state == 1 {
                            ProgressView(value: Double(status.bytes), total: Double(max(status.target, 1)))
                        }
                        if status.error != 0 { Text("Worker error: \(status.error)").foregroundColor(.red) }
                    }
                    HStack {
                        Button("Inflate to 2 GiB") { model.setDuskieMemory(enabled: true) }
                            .disabled(!model.hasDuskieMemoryWorker || model.isChangingDuskieMemory || model.duskMemoryStatus?.state != 0)
                        Button("Release") { model.setDuskieMemory(enabled: false) }
                            .disabled(model.isChangingDuskieMemory || model.duskMemoryStatus == nil || model.duskMemoryStatus?.state == 0)
                    }.buttonStyle(.bordered)
                    if let error = model.duskMemoryError { Text(error).font(.caption).foregroundColor(.red) }
                    Text("Uses the installed Duskie worker, with its own process memory allowance and random page fill. It stays active while switching apps or closing this sheet; use Release to stop it. Manual 100 MiB controls above remain separate. This creates memory pressure, not extra RAM, and can cause apps to close.")
                        .font(.caption).foregroundColor(.secondary)
                    if !model.hasDuskieMemoryWorker {
                        Text("Install Duskie with its memory worker to use this control.").font(.caption)
                    }
                }
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
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") {
                        model.refreshMemoryDetails()
                    }
                        .disabled(model.isReadingMemoryPressure)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { stress.clear(); dismiss() }
                }
            }
        }
        .task {
            model.refreshMemoryDetails()
            stress.refreshProcessMemory()
            model.refreshDuskieMemory()
        }
        .onReceive(model.$memorySnapshot) { _ in
            stress.refreshProcessMemory()
            model.refreshDuskieMemory()
        }
        .onDisappear { stress.clear() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.refreshMemoryDetails()
                stress.refreshProcessMemory()
            } else if phase == .background {
                stress.clear()
            }
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
