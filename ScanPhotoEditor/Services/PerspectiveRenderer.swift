import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum PerspectiveRenderingError: LocalizedError {
    case invalidGeometry
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .invalidGeometry: "The selected region has invalid geometry."
        case .renderingFailed: "The corrected image could not be rendered."
        }
    }
}

enum PerspectiveRenderer {
    static func render(
        source: CGImage,
        region: PhotoRegion,
        maximumDimension: CGFloat? = nil
    ) throws -> CGImage {
        guard region.quadrilateral.isValid() else {
            throw PerspectiveRenderingError.invalidGeometry
        }

        var image = CIImage(cgImage: source)
        let extent = image.extent
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = coreImagePoint(region.quadrilateral.topLeft, in: extent)
        filter.topRight = coreImagePoint(region.quadrilateral.topRight, in: extent)
        filter.bottomRight = coreImagePoint(region.quadrilateral.bottomRight, in: extent)
        filter.bottomLeft = coreImagePoint(region.quadrilateral.bottomLeft, in: extent)

        guard let corrected = filter.outputImage else {
            throw PerspectiveRenderingError.renderingFailed
        }
        image = translatedToOrigin(corrected)

        switch region.rotation {
        case .zero:
            break
        case .clockwise90:
            image = translatedToOrigin(image.oriented(.right))
        case .clockwise180:
            image = translatedToOrigin(image.oriented(.down))
        case .clockwise270:
            image = translatedToOrigin(image.oriented(.left))
        }

        if region.flipHorizontal {
            image = translatedToOrigin(
                image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            )
        }
        if region.flipVertical {
            image = translatedToOrigin(
                image.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            )
        }

        if let maximumDimension {
            let largest = max(image.extent.width, image.extent.height)
            if largest > maximumDimension {
                let scale = maximumDimension / largest
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        guard let result = ImageRenderingContext.shared.createCGImage(
            image,
            from: image.extent.integral,
            format: .RGBA8,
            colorSpace: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        ) else {
            throw PerspectiveRenderingError.renderingFailed
        }
        return result
    }

    private static func coreImagePoint(_ point: NormalizedPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + point.x * extent.width,
            y: extent.minY + (1 - point.y) * extent.height
        )
    }

    private static func translatedToOrigin(_ image: CIImage) -> CIImage {
        image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            )
        )
    }
}

