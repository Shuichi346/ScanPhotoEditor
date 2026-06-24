import CoreGraphics
import Foundation

enum PDFExportError: LocalizedError {
    case contextCreationFailed
    case noPages

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: "The PDF could not be created."
        case .noPages: "There are no regions to export."
        }
    }
}

enum PDFExportService {
    static func export(
        images: [(name: String, image: CGImage)],
        destinationDirectory: URL
    ) throws -> URL {
        guard !images.isEmpty else { throw PDFExportError.noPages }
        let outputURL = ImageExportService.conflictSafeURL(
            baseName: "ScanPhotoEditor Export",
            fileExtension: "pdf",
            directory: destinationDirectory
        )
        let temporaryURL = outputURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: temporaryURL)

        guard let consumer = CGDataConsumer(url: temporaryURL as CFURL) else {
            throw PDFExportError.contextCreationFailed
        }
        var initialBox = pageBox(for: images[0].image)
        guard let context = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else {
            throw PDFExportError.contextCreationFailed
        }

        for item in images {
            var pageBox = pageBox(for: item.image)
            let pageInfo = [
                kCGPDFContextMediaBox: NSData(
                    bytes: &pageBox,
                    length: MemoryLayout<CGRect>.size
                )
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.interpolationQuality = .high
            context.draw(item.image, in: pageBox)
            context.endPDFPage()
        }
        context.closePDF()
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        return outputURL
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
