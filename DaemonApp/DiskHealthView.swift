import SwiftUI

struct DiskHealthView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

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
                        value("Host writes (raw)", "hostWrites", report: report)
                        value("NAND writes (raw)", "nandWrites", report: report)
                        value("Critical warning flags", "smartCritWarnings", report: report)
                        value("Grown bad blocks", "numGrownBad", report: report)
                        value("Retired blocks", "numRetiredBlocks", report: report)
                        value("Uncorrectable reads", "ueccReads", report: report)
                        Text("Write-counter units are unverified on this model, so these counters are not converted to TB. Missing fields remain unavailable.")
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
