import Foundation
import UniformTypeIdentifiers

struct ImportedImage: Sendable {
    let url: URL
    let data: Data
    let typeIdentifier: String
}

enum ImageImportService {
    private static let supportedTypes: [UTType] = [.heic, .heif, .jpeg, .png, .tiff]

    static func discoverAndRead(urls: [URL]) -> (images: [ImportedImage], report: ImportReport) {
        var report = ImportReport()
        var candidates: [URL] = []
        var seen = Set<URL>()

        for url in urls {
            discover(url: url.standardizedFileURL, candidates: &candidates, report: &report)
        }

        var images: [ImportedImage] = []
        for url in candidates where seen.insert(url.standardizedFileURL).inserted {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
                  supportedTypes.contains(where: { type.conforms(to: $0) })
            else {
                report.skipped.append(url.lastPathComponent)
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    report.skipped.append(url.lastPathComponent)
                    continue
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                images.append(
                    ImportedImage(
                        url: url,
                        data: data,
                        typeIdentifier: type.identifier
                    )
                )
                report.imported.append(url.lastPathComponent)
            } catch {
                report.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (images, report)
    }

    private static func discover(
        url: URL,
        candidates: inout [URL],
        report: inout ImportReport
    ) {
        do {
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
                candidates.append(url)
                return
            }
            guard values.isDirectory == true else {
                report.skipped.append(url.lastPathComponent)
                return
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            for childURL in children.sorted(by: { $0.path < $1.path }) {
                discover(url: childURL, candidates: &candidates, report: &report)
            }
        } catch {
            report.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
