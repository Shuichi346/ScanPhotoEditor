import SwiftUI

struct CorrectedPreviewLayout: Equatable {
    static let contentPadding: CGFloat = 28

    let contentSize: CGSize
    let imageSize: CGSize

    init(sourceImageSize: CGSize, viewportSize: CGSize, zoom: CGFloat) {
        let availableSize = CGSize(
            width: max(viewportSize.width - Self.contentPadding * 2, 1),
            height: max(viewportSize.height - Self.contentPadding * 2, 1)
        )
        let fitScale = min(
            availableSize.width / max(sourceImageSize.width, 1),
            availableSize.height / max(sourceImageSize.height, 1)
        )
        let effectiveZoom = min(max(zoom, 0.5), 3)
        imageSize = CGSize(
            width: sourceImageSize.width * fitScale * effectiveZoom,
            height: sourceImageSize.height * fitScale * effectiveZoom
        )
        contentSize = CGSize(
            width: max(viewportSize.width, imageSize.width + Self.contentPadding * 2),
            height: max(viewportSize.height, imageSize.height + Self.contentPadding * 2)
        )
    }
}

struct CorrectedPreviewView: View {
    let image: CGImage?
    @State private var zoom: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Corrected Preview")
                    .font(.headline)
                Spacer()
                Slider(value: $zoom, in: 0.5 ... 3)
                    .frame(width: 130)
                    .accessibilityLabel("Corrected Preview Zoom")
                Text("\(Int(zoom * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            GeometryReader { viewport in
                if let image {
                    let layout = CorrectedPreviewLayout(
                        sourceImageSize: CGSize(width: image.width, height: image.height),
                        viewportSize: viewport.size,
                        zoom: zoom
                    )
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                            .frame(
                                width: layout.contentSize.width,
                                height: layout.contentSize.height,
                                alignment: .center
                            )
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                } else {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        ContentUnavailableView(
                            "Preview Unavailable",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
            }
        }
    }
}
