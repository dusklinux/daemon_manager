import SwiftUI

private struct RelatedDataFile: Identifiable {
    let title: String
    let path: String
    let note: String
    var id: String { path }

    var information: String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            if let date = attributes[.modificationDate] as? Date {
                return "\(formattedSize) • Modified \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return formattedSize
        } catch {
            return "Not available: \(error.localizedDescription)"
        }
    }
}

struct ServiceDetailsView: View {
    let service: LaunchdService
    @State private var fileInformation: [String: String] = [:]

    private var relatedFiles: [RelatedDataFile] {
        guard ["com.apple.contactsd", "com.apple.ABDatabaseDoctor"].contains(service.label) else { return [] }
        return [
            RelatedDataFile(title: "Contacts database", path: "/var/mobile/Library/AddressBook/AddressBook.sqlitedb",
                            note: "The Contacts address-book store. Metadata only; contact records are not read."),
            RelatedDataFile(title: "Contacts images database", path: "/var/mobile/Library/AddressBook/AddressBookImages.sqlitedb",
                            note: "The related address-book image store. File availability varies by device.")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let warning = SafetyManager.warning(for: service.label) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(SafetyManager.isCritical(service.label) ? .red : .orange)
                    .padding(8)
                    .background((SafetyManager.isCritical(service.label) ? Color.red : Color.orange).opacity(0.10))
                    .cornerRadius(8)
            }
            if let description = DaemonDescriptions.get(for: service.label) {
                Text(description).font(.subheadline)
            }
            if let path = service.plistPath { detail("Launchd configuration", path) }
            if let executable = service.executablePath { detail("Executable", executable) }
            detail("Override domain", service.domain ?? "Unresolved")
            ForEach(relatedFiles) { file in
                VStack(alignment: .leading, spacing: 3) {
                    detail(file.title, file.path)
                    Text(fileInformation[file.id] ?? "Reading file metadata…")
                        .font(.caption).foregroundColor(.secondary)
                    Text(file.note).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .textSelection(.enabled)
        .task(id: service.id) {
            let files = relatedFiles
            let information = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.information) })
            }.value
            guard !Task.isCancelled else { return }
            fileInformation = information
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Text(value).font(.system(.caption, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
