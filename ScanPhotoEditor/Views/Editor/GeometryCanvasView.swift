import AppKit
import SwiftUI

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

            ScrollView([.horizontal, .vertical]) {
                GeometryReader { proxy in
                    if let image = store.sourcePreview {
                        let imageRect = aspectFitRect(
                            imageSize: CGSize(width: image.width, height: image.height),
                            containerSize: proxy.size,
                            zoom: store.zoom
                        )
                        ZStack(alignment: .topLeading) {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: imageRect.width, height: imageRect.height)
                                .position(x: imageRect.midX, y: imageRect.midY)

                            Canvas { context, _ in
                                drawRegions(
                                    context: context,
                                    source: selectedSource,
                                    imageRect: imageRect
                                )
                            }
                            .allowsHitTesting(false)

                            if let region = selectedRegion {
                                handles(for: region.quadrilateral, in: imageRect)
                            }
                        }
                    }
                }
                .frame(
                    minWidth: 600 * store.zoom,
                    minHeight: 500 * store.zoom
                )
                .padding(28)
            }
            .background(Color(nsColor: .controlBackgroundColor))
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
            Circle()
                .fill(.white)
                .stroke(.tint, lineWidth: 3)
                .frame(width: 16, height: 16)
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

    private func aspectFitRect(
        imageSize: CGSize,
        containerSize: CGSize,
        zoom: CGFloat
    ) -> CGRect {
        let available = CGSize(
            width: max(containerSize.width, 1),
            height: max(containerSize.height, 1)
        )
        let scale = min(available.width / imageSize.width, available.height / imageSize.height) * zoom
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: max(0, (available.width - size.width) / 2),
            y: max(0, (available.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
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
