import SwiftUI

struct SettingsView: View {
    @AppStorage(DetectionPreferences.maximumDetectionsKey)
    private var maximumDetections = DetectionPreferences.defaultMaximumDetections
    @AppStorage(ExportPreferences.jpegQualityKey)
    private var jpegQuality = ExportPreferences.defaultQualityPercent
    @AppStorage(ExportPreferences.heicQualityKey)
    private var heicQuality = ExportPreferences.defaultQualityPercent
    @AppStorage(ExportPreferences.pdfQualityKey)
    private var pdfQuality = ExportPreferences.defaultQualityPercent

    var body: some View {
        Form {
            Section("Detection") {
                Stepper(
                    value: $maximumDetections,
                    in: DetectionPreferences.maximumDetectionsRange
                ) {
                    LabeledContent("Maximum detections per image") {
                        Text(maximumDetections, format: .number)
                            .monospacedDigit()
                    }
                }

                Text("Applies to newly imported images and when detection is rerun.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Export quality") {
                qualityStepper("JPEG quality", value: $jpegQuality)
                qualityStepper("HEIC quality", value: $heicQuality)
                qualityStepper("PDF image quality", value: $pdfQuality)

                Text("Lower values create smaller files. PNG and TIFF exports remain lossless.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .scenePadding()
    }

    private func qualityStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: ExportPreferences.qualityPercentRange) {
            LabeledContent(title) {
                Text(value.wrappedValue, format: .percent.scale(1))
                    .monospacedDigit()
            }
        }
    }
}
