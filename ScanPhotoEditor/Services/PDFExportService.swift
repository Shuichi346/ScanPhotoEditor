import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PDFExportError: LocalizedError {
    case contextCreationFailed
    case imageEncodingFailed
    case noPages

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: "The PDF could not be created."
        case .imageEncodingFailed: "A PDF page image could not be compressed."
        case .noPages: "There are no regions to export."
        }
    }
}

enum PDFExportService {
    static func export(
        images: [(name: String, image: CGImage)],
        quality: Double,
        destinationDirectory: URL
    ) throws -> URL {
        try export(
            pageCount: images.count,
            quality: quality,
            destinationDirectory: destinationDirectory,
            imageProvider: { images[$0].image }
        )
    }

    static func export(
        pageCount: Int,
        quality: Double,
        destinationDirectory: URL,
        imageProvider: (_ index: Int) throws -> CGImage,
        didCompletePage: (_ completedPages: Int) -> Void = { _ in }
    ) throws -> URL {
        guard pageCount > 0 else { throw PDFExportError.noPages }
        let outputURL = ImageExportService.conflictSafeURL(
            baseName: "ScanPhotoEditor Export",
            fileExtension: "pdf",
            directory: destinationDirectory
        )
        let temporaryURL = outputURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: temporaryURL)
        var succeeded = false
        defer {
            if !succeeded {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        guard let consumer = CGDataConsumer(url: temporaryURL as CFURL) else {
            throw PDFExportError.contextCreationFailed
        }
        try Task.checkCancellation()
        let firstImage = try imageProvider(0)
        var initialBox = pageBox(for: firstImage)
        guard let context = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else {
            throw PDFExportError.contextCreationFailed
        }
        var contextClosed = false
        defer {
            if !contextClosed {
                context.closePDF()
            }
        }

        for index in 0 ..< pageCount {
            try Task.checkCancellation()
            let image = index == 0 ? firstImage : try imageProvider(index)
            let compressedImage = try jpegBackedImage(
                from: image,
                quality: quality
            )
            var pageBox = pageBox(for: image)
            let pageInfo = [
                kCGPDFContextMediaBox: NSData(
                    bytes: &pageBox,
                    length: MemoryLayout<CGRect>.size
                )
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.interpolationQuality = .high
            context.draw(compressedImage, in: pageBox)
            context.endPDFPage()
            didCompletePage(index + 1)
        }
        context.closePDF()
        contextClosed = true
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        succeeded = true
        return outputURL
    }

    private static func jpegBackedImage(
        from image: CGImage,
        quality: Double
    ) throws -> CGImage {
        guard let opaqueImage = ImageRenderingContext.opaqueImage(from: image) else {
            throw PDFExportError.imageEncodingFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PDFExportError.imageEncodingFailed
        }
        let properties = [
            kCGImagePropertyOrientation: 1,
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.01), 1)
        ] as CFDictionary
        CGImageDestinationAddImage(destination, opaqueImage, properties)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data),
              let compressedImage = CGImage(
                  jpegDataProviderSource: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else {
            throw PDFExportError.imageEncodingFailed
        }
        return compressedImage
    }

    private static func pageBox(for image: CGImage) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width) / 300 * 72,
            height: CGFloat(image.height) / 300 * 72
        )
    }
}
