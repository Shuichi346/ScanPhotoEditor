import SwiftUI

struct CorrectedPreviewView: View {
    let image: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Corrected Preview")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            ZStack {
                Color(nsColor: .controlBackgroundColor)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(28)
                } else {
                    ContentUnavailableView(
                        "Preview Unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
        }
    }
}

