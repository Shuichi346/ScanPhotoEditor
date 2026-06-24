import SwiftUI

struct SettingsView: View {
    @AppStorage(DetectionPreferences.maximumDetectionsKey)
    private var maximumDetections = DetectionPreferences.defaultMaximumDetections

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .frame(width: 440)
        .scenePadding()
    }
}
