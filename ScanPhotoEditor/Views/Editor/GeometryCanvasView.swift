import AppKit
import SwiftUI

struct GeometryCanvasLayout: Equatable {
    static let minimumCanvasSize = CGSize(width: 600, height: 500)
    static let contentPadding: CGFloat = 28

    let contentSize: CGSize
    let imageRect: CGRect

    init(imageSize: CGSize, viewportSize: CGSize, zoom: CGFloat) {
        let availableViewport = CGSize(
            width: max(viewportSize.width - Self.contentPadding * 2, 1),
            height: max(viewportSize.height - Self.contentPadding * 2, 1)
        )
        let baseCanvasSize = CGSize(
            width: max(availableViewport.width, Self.minimumCanvasSize.width),
            height: max(availableViewport.height, Self.minimumCanvasSize.height)
        )
        let effectiveZoom = max(zoom, 0.01)
        let zoomedCanvasSize = CGSize(
            width: baseCanvasSize.width * effectiveZoom,
            height: baseCanvasSize.height * effectiveZoom
        )
        contentSize = CGSize(
            width: max(baseCanvasSize.width, zoomedCanvasSize.width),
            height: max(baseCanvasSize.height, zoomedCanvasSize.height)
        )

        let scale = min(
            zoomedCanvasSize.width / max(imageSize.width, 1),
            zoomedCanvasSize.height / max(imageSize.height, 1)
        )
        let renderedImageSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        imageRect = CGRect(
            x: (contentSize.width - renderedImageSize.width) / 2,
            y: (contentSize.height - renderedImageSize.height) / 2,
            width: renderedImageSize.width,
            height: renderedImageSize.height
        )
    }
}

struct GeometryCanvasView: View {
    let store: ProjectEditingStore
    let undoManager: UndoManager?
    @ObservedObject private var document: PhotoProjectDocument
    @State private var dragStartQuadrilateral: NormalizedQuadrilateral?
    @State private var dragStartLocation: CGPoint?

    init(store: ProjectEditingStore, undoManager: UndoManager?) {
        self.store = store
        self.undoManager = undoManager
        _document = ObservedObject(wrappedValue: store.document)
    }

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack {
                Text("Source")
                    .font(.headline)
                Spacer()
                Slider(value: $store.zoom, in: 0.5 ... 3)
                    .frame(width: 130)
                    .accessibilityLabel("Zoom")
                Text("\(Int(store.zoom * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    if let image = store.sourcePreview {
                        let layout = GeometryCanvasLayout(
                            imageSize: CGSize(width: image.width, height: image.height),
                            viewportSize: viewport.size,
                            zoom: store.zoom
                        )
                        ZStack(alignment: .topLeading) {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                                .position(x: layout.imageRect.midX, y: layout.imageRect.midY)

                            Canvas { context, _ in
                                drawRegions(
                                    context: context,
                                    source: selectedSource,
                                    imageRect: layout.imageRect
                                )
                            }
                            .allowsHitTesting(false)

                            if let region = selectedRegion {
                                handles(for: region.quadrilateral, in: layout.imageRect)
                            }
                        }
                        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                        .padding(GeometryCanvasLayout.contentPadding)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var selectedSource: SourceAsset? {
        guard let selectedRegionID = store.selectedRegionID else {
            return document.manifest.sources.first
        }
        return document.manifest.sources.first {
            $0.regions.contains(where: { $0.id == selectedRegionID })
        }
    }

    private var selectedRegion: PhotoRegion? {
        guard let selectedRegionID = store.selectedRegionID else { return nil }
        return document.manifest.sources
            .lazy
            .flatMap(\.regions)
            .first(where: { $0.id == selectedRegionID })
    }

    @ViewBuilder
    private func handles(
        for quadrilateral: NormalizedQuadrilateral,
        in imageRect: CGRect
    ) -> some View {
        ForEach(QuadrilateralCorner.allCases, id: \.self) { corner in
            let point = quadrilateral.point(for: corner).point(in: imageRect)
            ZStack {
                Circle()
                    .fill(.clear)
                    .stroke(.tint, lineWidth: 3)

                Path { path in
                    path.move(to: CGPoint(x: 3, y: 9))
                    path.addLine(to: CGPoint(x: 15, y: 9))
                    path.move(to: CGPoint(x: 9, y: 3))
                    path.addLine(to: CGPoint(x: 9, y: 15))
                }
                .stroke(.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
                .position(point)
                .gesture(cornerDragGesture(corner: corner, imageRect: imageRect))
                .accessibilityLabel("\(corner.rawValue) corner")
        }

        ForEach(QuadrilateralEdge.allCases, id: \.self) { edge in
            let point = edgeMidpoint(edge, quadrilateral: quadrilateral).point(in: imageRect)
            Capsule()
                .fill(.tint)
                .frame(
                    width: edge == .top || edge == .bottom ? 30 : 10,
                    height: edge == .left || edge == .right ? 30 : 10
                )
                .position(point)
                .gesture(edgeDragGesture(edge: edge, imageRect: imageRect))
                .accessibilityLabel("\(edge.rawValue) edge")
        }
    }

    private func cornerDragGesture(
        corner: QuadrilateralCorner,
        imageRect: CGRect
    ) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStartQuadrilateral == nil {
                    dragStartQuadrilateral = store.selectedRegion?.quadrilateral
                }
                guard let start = dragStartQuadrilateral else { return }
                let point = normalizedPoint(value.location, in: imageRect)
                if let candidate = start.moving(corner: corner, to: point) {
                    store.setQuadrilateral(candidate)
                }
            }
            .onEnded { _ in
                if let previous = dragStartQuadrilateral,
                   let current = store.selectedRegion?.quadrilateral,
                   previous != current {
                    store.setQuadrilateral(
                        current,
                        registerUndoFrom: previous,
                        undoManager: undoManager
                    )
                }
                dragStartQuadrilateral = nil
            }
    }

    private func edgeDragGesture(
        edge: QuadrilateralEdge,
        imageRect: CGRect
    ) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStartQuadrilateral == nil {
                    dragStartQuadrilateral = store.selectedRegion?.quadrilateral
                    dragStartLocation = value.startLocation
                }
                guard let start = dragStartQuadrilateral,
                      let startLocation = dragStartLocation else {
                    return
                }
                let delta = CGPoint(
                    x: (value.location.x - startLocation.x) / imageRect.width,
                    y: (value.location.y - startLocation.y) / imageRect.height
                )
                if let candidate = start.moving(edge: edge, by: delta) {
                    store.setQuadrilateral(candidate)
                }
            }
            .onEnded { _ in
                if let previous = dragStartQuadrilateral,
                   let current = store.selectedRegion?.quadrilateral,
                   previous != current {
                    store.setQuadrilateral(
                        current,
                        registerUndoFrom: previous,
                        undoManager: undoManager
                    )
                }
                dragStartQuadrilateral = nil
                dragStartLocation = nil
            }
    }

    private func drawRegions(
        context: GraphicsContext,
        source: SourceAsset?,
        imageRect: CGRect
    ) {
        guard let source else { return }
        for region in source.regions {
            let points = region.quadrilateral.points.map { $0.point(in: imageRect) }
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            let selected = region.id == store.selectedRegionID
            context.stroke(
                path,
                with: .color(selected ? .accentColor : .mint.opacity(0.8)),
                lineWidth: selected ? 3 : 1.5
            )
            if selected, store.showGrid {
                drawGrid(
                    context: context,
                    quadrilateral: region.quadrilateral,
                    imageRect: imageRect
                )
            }
        }
    }

    private func drawGrid(
        context: GraphicsContext,
        quadrilateral: NormalizedQuadrilateral,
        imageRect: CGRect
    ) {
        for index in 1 ..< 8 {
            let t = CGFloat(index) / 8
            var vertical = Path()
            vertical.move(to: interpolate(
                quadrilateral.topLeft.point(in: imageRect),
                quadrilateral.topRight.point(in: imageRect),
                t
            ))
            vertical.addLine(to: interpolate(
                quadrilateral.bottomLeft.point(in: imageRect),
                quadrilateral.bottomRight.point(in: imageRect),
                t
            ))
            context.stroke(vertical, with: .color(.mint.opacity(0.55)), lineWidth: 1)

            var horizontal = Path()
            horizontal.move(to: interpolate(
                quadrilateral.topLeft.point(in: imageRect),
                quadrilateral.bottomLeft.point(in: imageRect),
                t
            ))
            horizontal.addLine(to: interpolate(
                quadrilateral.topRight.point(in: imageRect),
                quadrilateral.bottomRight.point(in: imageRect),
                t
            ))
            context.stroke(horizontal, with: .color(.mint.opacity(0.55)), lineWidth: 1)
        }
    }

    private func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        ).clamped()
    }

    private func edgeMidpoint(
        _ edge: QuadrilateralEdge,
        quadrilateral: NormalizedQuadrilateral
    ) -> NormalizedPoint {
        let pair: (NormalizedPoint, NormalizedPoint) = switch edge {
        case .top: (quadrilateral.topLeft, quadrilateral.topRight)
        case .right: (quadrilateral.topRight, quadrilateral.bottomRight)
        case .bottom: (quadrilateral.bottomLeft, quadrilateral.bottomRight)
        case .left: (quadrilateral.topLeft, quadrilateral.bottomLeft)
        }
        return NormalizedPoint(x: (pair.0.x + pair.1.x) / 2, y: (pair.0.y + pair.1.y) / 2)
    }

    private func interpolate(_ start: CGPoint, _ end: CGPoint, _ value: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * value,
            y: start.y + (end.y - start.y) * value
        )
    }
}
