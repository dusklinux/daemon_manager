import SwiftUI

struct DiskHealthView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWriteCounter: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Read latest diagnostic") { model.readDiskHealth(generate: false) }
                    Button("Run new diagnostic") { model.readDiskHealth(generate: true) }
                    Text("Collection can take several minutes and temporarily use CPU and disk space. Keep this app open. Reports stay on this phone; there is no scheduled collection or upload.")
                        .font(.caption).foregroundColor(.secondary)
                    if model.isDiagnosingDisk { ProgressView("Reading or collecting disk health…") }
                    if let error = model.diskHealthError { Text(error).foregroundColor(.orange) }
                }
                .disabled(model.isDiagnosingDisk || model.isApplyingConfig || !model.isProcessing.isEmpty)
                if let report = model.diskHealthReport {
                    Section("Reported NAND wear") {
                        value("User NAND endurance used", "percentUsed", suffix: "%", report: report)
                        value("SLC endurance used", "slcPercentUsed", suffix: "%", report: report)
                        Text("Driver-reported wear is not a remaining-lifetime guarantee. Rated terabytes written are not exposed in this report.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("Erase cycles") {
                        value("Average TLC cycles", "averageTLCPECycles", report: report)
                        value("TLC endurance cycles", "maxNativeEndurance", report: report)
                        value("Average SLC cycles", "averageSLCPECycles", report: report)
                        value("SLC endurance cycles", "maxSLCEndurance", report: report)
                    }
                    Section("Driver counters") {
                        writeCounter("Host writes", "hostWrites", report: report)
                        writeCounter("NAND writes", "nandWrites", report: report)
                        value("Critical warning flags", "smartCritWarnings", report: report)
                        value("Grown bad blocks", "numGrownBad", report: report)
                        value("Retired blocks", "numRetiredBlocks", report: report)
                        value("Uncorrectable reads", "ueccReads", report: report)
                        Text("Tap a write counter for its meaning and conversion status. GB is unavailable because this diagnostic does not identify the counter units. Missing fields remain unavailable.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("Snapshot") {
                        Text(Date(timeIntervalSince1970: report.sampledAt).formatted()).font(.caption)
                        Text(report.path).font(.caption.monospaced()).textSelection(.enabled)
                        Text("This is a saved diagnostic snapshot, not a live reading.").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Disk Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .alert(selectedWriteCounter ?? "Write counter", isPresented: Binding(
                get: { selectedWriteCounter != nil },
                set: { if !$0 { selectedWriteCounter = nil } })) {
                    Button("OK") { selectedWriteCounter = nil }
                } message: {
                    Text("Host writes count data sent to storage; NAND writes count flash writes, including internal storage work. These are cumulative driver counters in the saved report.\n\nGB conversion is unavailable: this report does not establish whether one count represents bytes, sectors, or another unit. Decimal GB would equal verified bytes ÷ 1,000,000,000. Treating these raw counts as bytes would give an incorrect result.")
                }
        }
    }

    private func writeCounter(_ title: String, _ key: String, report: DiskHealthReport) -> some View {
        Button { selectedWriteCounter = title } label: {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                Text(report.values[key].map { $0.formatted(.number.grouping(.always)) + " raw" } ?? "Unavailable")
                    .monospacedDigit().foregroundColor(.secondary)
                Image(systemName: "info.circle").font(.caption)
            }
        }
    }

    private func value(_ title: String, _ key: String, suffix: String = "", report: DiskHealthReport) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(report.values[key].map { String($0) + suffix } ?? "Unavailable")
                .monospacedDigit().foregroundColor(.secondary)
        }
    }
}
