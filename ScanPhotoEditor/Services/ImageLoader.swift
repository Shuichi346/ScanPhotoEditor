import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageLoadingError: LocalizedError {
    case unsupportedImage
    case decodingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: "The file is not a supported image."
        case .decodingFailed: "The image could not be decoded."
        case .encodingFailed: "A derived image could not be encoded."
        }
    }
}

struct LoadedImage: @unchecked Sendable {
    let image: CGImage
    let pixelSize: CGSize
}

struct ImageMetadata: Sendable {
    let uprightPixelSize: CGSize
    let typeIdentifier: String?
}

enum ImageLoader {
    static func metadata(data: Data) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageLoadingError.unsupportedImage
        }
        return try metadata(source: source)
    }

    static func metadata(url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoadingError.unsupportedImage
        }
        return try metadata(source: source)
    }

    static func loadUprightImage(data: Data, maximumDimension: Int? = nil) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageLoadingError.unsupportedImage
        }
        let orientedImage = CIImage(
            data: data,
            options: [.applyOrientationProperty: true]
        )
        return try loadUprightImage(
            source: source,
            orientedImage: orientedImage,
            maximumDimension: maximumDimension
        )
    }

    static func loadUprightImage(url: URL, maximumDimension: Int? = nil) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoadingError.unsupportedImage
        }
        let orientedImage = CIImage(
            contentsOf: url,
            options: [.applyOrientationProperty: true]
        )
        return try loadUprightImage(
            source: source,
            orientedImage: orientedImage,
            maximumDimension: maximumDimension
        )
    }

    static func jpegThumbnail(data: Data, maximumDimension: Int = 512) throws -> Data {
        let loaded = try loadUprightImage(data: data, maximumDimension: maximumDimension)
        return try jpegData(from: loaded.image)
    }

    static func jpegThumbnail(url: URL, maximumDimension: Int = 512) throws -> Data {
        let loaded = try loadUprightImage(url: url, maximumDimension: maximumDimension)
        return try jpegData(from: loaded.image)
    }

    static func typeIdentifier(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.identifier
    }

    private static func metadata(source: CGImageSource) throws -> ImageMetadata {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw ImageLoadingError.unsupportedImage
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5 ... 8).contains(orientation)
        return ImageMetadata(
            uprightPixelSize: CGSize(
                width: swapsDimensions ? height.doubleValue : width.doubleValue,
                height: swapsDimensions ? width.doubleValue : height.doubleValue
            ),
            typeIdentifier: CGImageSourceGetType(source) as String?
        )
    }

    private static func loadUprightImage(
        source: CGImageSource,
        orientedImage: CIImage?,
        maximumDimension: Int?
    ) throws -> LoadedImage {
        let image: CGImage?
        if let maximumDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            guard let orientedImage else {
                throw ImageLoadingError.decodingFailed
            }
            image = ImageRenderingContext.shared.createCGImage(
                orientedImage,
                from: orientedImage.extent.integral,
                format: .RGBA8,
                colorSpace: orientedImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
            )
        }

        guard let image else {
            throw ImageLoadingError.decodingFailed
        }
        return LoadedImage(
            image: image,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
    }

    private static func jpegData(from image: CGImage) throws -> Data {
        guard let opaqueImage = ImageRenderingContext.opaqueImage(from: image) else {
            throw ImageLoadingError.encodingFailed
        }
        let result = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                result,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            throw ImageLoadingError.encodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            opaqueImage,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ImageLoadingError.encodingFailed
        }
        return result as Data
    }
}

enum ImageRenderingContext {
    static let shared = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: false
    ])

    static func opaqueImage(from image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        return shared.createCGImage(
            ciImage,
            from: ciImage.extent.integral,
            format: .RGBX8,
            colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        )
    }
}
