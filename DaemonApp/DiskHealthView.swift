import SwiftUI

struct DiskHealthView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var activeDetailTitle: String?
    @State private var activeDetailMessage: String?

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
                        wearRow("User NAND wear used", key: "percentUsed", report: report)
                        wearRow("SLC cache wear used", key: "slcPercentUsed", report: report)
                        Text("Driver-reported wear percentage relative to rated flash endurance.")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    Section("Erase cycles & ratings") {
                        cyclesRow("TLC erase cycles", currentKey: "averageTLCPECycles", maxKey: "maxNativeEndurance", report: report)
                        cyclesRow("SLC erase cycles", currentKey: "averageSLCPECycles", maxKey: "maxSLCEndurance", report: report)
                    }

                    Section("Storage written (4 KB sector verified)") {
                        storageCounterRow("Host writes", key: "hostWrites",
                                          description: "Host writes count all data sent to storage by iOS and user applications.",
                                          report: report)
                        storageCounterRow("NAND writes", key: "nandWrites",
                                          description: "NAND writes count physical flash memory writes by the controller, including SLC caching, wear leveling, and internal maintenance.",
                                          report: report)
                        writeAmplificationRow(report: report)
                        Text("Tap any counter to inspect exact bytes, binary GiB, and raw sector counts.")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    if report.values["hostReads"] != nil || report.values["nandReads"] != nil {
                        Section("Storage read (4 KB sector verified)") {
                            if report.values["hostReads"] != nil {
                                storageCounterRow("Host reads", key: "hostReads",
                                                  description: "Host reads count all data read from storage by iOS and user applications.",
                                                  report: report)
                            }
                            if report.values["nandReads"] != nil {
                                storageCounterRow("NAND reads", key: "nandReads",
                                                  description: "NAND reads count actual flash memory read operations executed by the controller.",
                                                  report: report)
                            }
                            if let ra = report.readAmplification {
                                HStack {
                                    Text("Read amplification")
                                    Spacer()
                                    Text(String(format: "%.2f×", ra))
                                        .monospacedDigit().foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Section("Storage utilization & integrity") {
                        if report.values["validLbas"] != nil {
                            storageCounterRow("Active user data", key: "validLbas",
                                              description: "Currently allocated and valid Logical Block Addresses (LBAs) stored on physical NAND.",
                                              report: report)
                        }
                        integrityRow("Critical warnings", key: "smartCritWarnings", normalValue: 0, normalText: "Normal", report: report)
                        integrityRow("Grown bad blocks", key: "numGrownBad", normalValue: 0, normalText: "None", report: report)
                        integrityRow("Retired blocks", key: "numRetiredBlocks", normalValue: 0, normalText: "None", report: report)
                        integrityRow("Uncorrectable reads", key: "ueccReads", normalValue: 0, normalText: "None", report: report)
                    }

                    if report.values["boots"] != nil || report.values["shutdowns"] != nil || report.values["uncleanBoots"] != nil {
                        Section("System boot history") {
                            if let boots = report.values["boots"] {
                                value("Total boots", "\(boots.formatted(.number.locale(Locale(identifier: "en_US"))))")
                            }
                            if let shutdowns = report.values["shutdowns"] {
                                value("Clean shutdowns", "\(shutdowns.formatted(.number.locale(Locale(identifier: "en_US"))))")
                            }
                            if let unclean = report.values["uncleanBoots"] {
                                value("Unclean boots", "\(unclean.formatted(.number.locale(Locale(identifier: "en_US"))))")
                            }
                        }
                    }

                    Section("Snapshot") {
                        Text(Date(timeIntervalSince1970: report.sampledAt).formatted()).font(.caption)
                        Text(report.path).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Counters are cumulative driver metrics saved at capture time.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Disk Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .alert(activeDetailTitle ?? "Storage Details", isPresented: Binding(
                get: { activeDetailMessage != nil },
                set: { if !$0 { activeDetailMessage = nil; activeDetailTitle = nil } })) {
                    Button("OK") { activeDetailMessage = nil; activeDetailTitle = nil }
                } message: {
                    Text(activeDetailMessage ?? "")
                }
        }
    }

    private func storageCounterRow(_ title: String, key: String, description: String, report: DiskHealthReport) -> some View {
        Button {
            if let raw = report.values[key], let bytes = report.bytes(for: key) {
                let breakdown = DiskHealthReport.detailedBreakdown(bytes, rawSectors: raw)
                let message = "\(description)\n\n\(breakdown)\n\nUnit is verified: 1 sector = 4,096 bytes (4 KB)."
                activeDetailTitle = title
                activeDetailMessage = message
            }
        } label: {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                Text(report.formattedStorage(for: key) ?? "Unavailable")
                    .monospacedDigit().foregroundColor(.secondary)
                Image(systemName: "info.circle").font(.caption)
            }
        }
    }

    private func writeAmplificationRow(report: DiskHealthReport) -> some View {
        Button {
            if let wa = report.writeAmplification,
               let host = report.values["hostWrites"],
               let nand = report.values["nandWrites"] {
                let message = """
                Write Amplification Factor (WAF = NAND writes ÷ Host writes).

                • Ratio: \(String(format: "%.3f×", wa))
                • Host writes: \(report.formattedStorage(for: "hostWrites") ?? "") (\(host.formatted(.number.locale(Locale(identifier: "en_US")))) sectors)
                • NAND writes: \(report.formattedStorage(for: "nandWrites") ?? "") (\(nand.formatted(.number.locale(Locale(identifier: "en_US")))) sectors)

                A WAF of ~1.30× represents normal and healthy flash translation layer efficiency on TLC NAND (typical SSD range: 1.2× – 2.5×).
                """
                activeDetailTitle = "Write Amplification"
                activeDetailMessage = message
            }
        } label: {
            HStack {
                Text("Write amplification").foregroundColor(.primary)
                Spacer()
                Text(report.writeAmplification.map { String(format: "%.2f×", $0) } ?? "Unavailable")
                    .monospacedDigit().foregroundColor(.secondary)
                Image(systemName: "info.circle").font(.caption)
            }
        }
    }

    private func wearRow(_ title: String, key: String, report: DiskHealthReport) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let used = report.values[key] {
                let remaining = used <= 100 ? 100 - used : 0
                Text("\(used)% (\(remaining)% remaining)")
                    .monospacedDigit().foregroundColor(.secondary)
            } else {
                Text("Unavailable").foregroundColor(.secondary)
            }
        }
    }

    private func cyclesRow(_ title: String, currentKey: String, maxKey: String, report: DiskHealthReport) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let cur = report.values[currentKey], let max = report.values[maxKey], max > 0 {
                let pct = (Double(cur) / Double(max)) * 100.0
                Text("\(cur.formatted(.number.locale(Locale(identifier: "en_US")))) / \(max.formatted(.number.locale(Locale(identifier: "en_US")))) (\(String(format: "%.1f%%", pct)))")
                    .monospacedDigit().foregroundColor(.secondary)
            } else if let cur = report.values[currentKey] {
                Text(cur.formatted(.number.locale(Locale(identifier: "en_US"))))
                    .monospacedDigit().foregroundColor(.secondary)
            } else {
                Text("Unavailable").foregroundColor(.secondary)
            }
        }
    }

    private func integrityRow(_ title: String, key: String, normalValue: UInt64, normalText: String, report: DiskHealthReport) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let v = report.values[key] {
                if v == normalValue {
                    Text("\(v) (\(normalText))").monospacedDigit().foregroundColor(.secondary)
                } else {
                    Text("\(v)").monospacedDigit().foregroundColor(.orange)
                }
            } else {
                Text("Unavailable").foregroundColor(.secondary)
            }
        }
    }

    private func value(_ title: String, _ text: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(text).monospacedDigit().foregroundColor(.secondary)
        }
    }
}
