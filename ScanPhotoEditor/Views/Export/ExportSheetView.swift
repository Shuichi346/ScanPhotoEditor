import AppKit
import SwiftUI

struct ExportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let store: ProjectEditingStore
    @State private var selectedFormats: Set<ExportImageFormat> = [.jpeg]
    @State private var includePDF = true
    @State private var selectionMode = ExportSelectionMode.all
    @State private var exportDirectory: URL?

    var body: some View {
        Group {
            if let report = store.exportReport,
               !store.isExporting,
               !store.exportWasCancelled {
                completionView(report: report)
            } else {
                exportOptionsView
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            store.prepareForExportPresentation()
        }
    }

    private var exportOptionsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export Photographs")
                .font(.title2.bold())

            Picker("Regions", selection: $selectionMode) {
                Text("All Regions").tag(ExportSelectionMode.all)
                Text("Selected Region").tag(ExportSelectionMode.selected)
            }
            .pickerStyle(.segmented)

            GroupBox("Image formats") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ExportImageFormat.allCases) { format in
                        Toggle(
                            format.label,
                            isOn: Binding(
                                get: { selectedFormats.contains(format) },
                                set: { enabled in
                                    if enabled {
                                        selectedFormats.insert(format)
                                    } else {
                                        selectedFormats.remove(format)
                                    }
                                }
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Toggle("Create ordered multi-page PDF", isOn: $includePDF)

            if store.isExporting {
                ProgressView(value: store.exportProgress)
                Button("Cancel Export", role: .cancel) {
                    store.cancelExport()
                }
            }

            if let report = store.exportReport, !report.failures.isEmpty {
                Text("\(report.failures.count) item\(report.failures.count == 1 ? "" : "s") failed.")
                    .foregroundStyle(.red)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.failures) { failure in
                            Text("\(failure.item): \(failure.message)")
                                .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 100)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Choose Destination…") {
                    chooseDestination()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    (selectedFormats.isEmpty && !includePDF)
                        || store.isExporting
                        || (selectionMode == .selected && store.selectedRegionID == nil)
                )
            }
        }
    }

    private func completionView(report: ExportReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text("Export Complete")
                    .font(.title2.bold())
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Text(completionMessage(report: report))
                .foregroundStyle(.secondary)

            if !report.failures.isEmpty {
                GroupBox("Items that could not be exported") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.failures) { failure in
                                Text("\(failure.item): \(failure.message)")
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                    .frame(maxHeight: 120)
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                Button("Open in Finder") {
                    openExportLocation(report: report)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(exportDirectory == nil && report.exportedURLs.isEmpty)
            }
        }
    }

    private func chooseDestination() {
        guard selectionMode != .selected || store.selectedRegionID != nil else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        exportDirectory = directory

        store.exportOptions = ExportOptions(
            formats: selectedFormats,
            includePDF: includePDF,
            selectedRegionIDs: selectionMode == .selected
                ? store.selectedRegionID.map { [$0] }
                : nil,
            jpegQuality: qualityPreference(
                key: ExportPreferences.jpegQualityKey
            ),
            heicQuality: qualityPreference(
                key: ExportPreferences.heicQualityKey
            ),
            pdfQuality: qualityPreference(
                key: ExportPreferences.pdfQualityKey
            )
        )
        store.export(to: directory)
    }

    private func completionMessage(report: ExportReport) -> String {
        let exportedCount = report.exportedURLs.count
        let exportedSummary =
            "\(exportedCount) file\(exportedCount == 1 ? "" : "s") exported."
        guard !report.failures.isEmpty else {
            return exportedSummary
        }
        let failureCount = report.failures.count
        return "\(exportedSummary) \(failureCount) item\(failureCount == 1 ? "" : "s") failed."
    }

    private func openExportLocation(report: ExportReport) {
        if let exportDirectory {
            NSWorkspace.shared.open(exportDirectory)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(report.exportedURLs)
        }
    }

    private func qualityPreference(key: String) -> Double {
        let defaults = UserDefaults.standard
        let percent = defaults.object(forKey: key) == nil
            ? ExportPreferences.defaultQualityPercent
            : defaults.integer(forKey: key)
        return ExportPreferences.quality(from: percent)
    }
}

private enum ExportSelectionMode: Hashable {
    case all
    case selected
}
