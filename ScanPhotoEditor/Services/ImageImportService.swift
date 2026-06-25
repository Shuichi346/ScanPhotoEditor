import Foundation
import UniformTypeIdentifiers

struct ImportedImage: Sendable {
    let url: URL
    let localURL: URL
    let typeIdentifier: String
}

struct ImportDiscovery: Sendable {
    let images: [ImportedImage]
    let report: ImportReport
    let stagingDirectory: URL
}

enum ImageImportService {
    private static let supportedTypes: [UTType] = [.heic, .heif, .jpeg, .png, .tiff]

    static func discoverAndStage(urls: [URL]) throws -> ImportDiscovery {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanPhotoEditor", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        do {
            var report = ImportReport()
            var images: [ImportedImage] = []
            var seen = Set<URL>()

            for submittedURL in urls {
                try Task.checkCancellation()
                let url = submittedURL.standardizedFileURL
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                try discoverAndCopy(
                    url: url,
                    stagingDirectory: stagingDirectory,
                    seen: &seen,
                    images: &images,
                    report: &report
                )
            }

            return ImportDiscovery(
                images: images,
                report: report,
                stagingDirectory: stagingDirectory
            )
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            throw error
        }
    }

    private static func discoverAndCopy(
        url: URL,
        stagingDirectory: URL,
        seen: inout Set<URL>,
        images: inout [ImportedImage],
        report: inout ImportReport
    ) throws {
        do {
            try Task.checkCancellation()
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isHiddenKey,
                .isPackageKey,
                .isSymbolicLinkKey
            ]
            let values = try url.resourceValues(forKeys: keys)
            if values.isHidden == true || values.isPackage == true || values.isSymbolicLink == true {
                report.skipped.append(url.lastPathComponent)
                return
            }

            if values.isRegularFile == true {
                try copySupportedImage(
                    at: url,
                    stagingDirectory: stagingDirectory,
                    seen: &seen,
                    images: &images,
                    report: &report
                )
                return
            }

            guard values.isDirectory == true else {
                report.skipped.append(url.lastPathComponent)
                return
            }

            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            for childURL in children.sorted(by: { $0.path < $1.path }) {
                try discoverAndCopy(
                    url: childURL,
                    stagingDirectory: stagingDirectory,
                    seen: &seen,
                    images: &images,
                    report: &report
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            report.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func copySupportedImage(
        at url: URL,
        stagingDirectory: URL,
        seen: inout Set<URL>,
        images: inout [ImportedImage],
        report: inout ImportReport
    ) throws {
        let standardizedURL = url.standardizedFileURL
        guard seen.insert(standardizedURL).inserted else { return }
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
              supportedTypes.contains(where: { type.conforms(to: $0) })
        else {
            report.skipped.append(url.lastPathComponent)
            return
        }

        try Task.checkCancellation()
        let fileExtension = url.pathExtension.lowercased()
        let stagedURL = stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        let partialURL = stagedURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partialURL)
        do {
            try FileManager.default.copyItem(at: url, to: partialURL)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: partialURL, to: stagedURL)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }

        images.append(
            ImportedImage(
                url: url,
                localURL: stagedURL,
                typeIdentifier: type.identifier
            )
        )
        report.imported.append(url.lastPathComponent)
    }
}
