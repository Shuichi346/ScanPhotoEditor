# ScanPhotoEditor Repository Instructions

- Target macOS 26 or later on Apple Silicon with Swift 6.3 strict concurrency.
- Treat `ScanPhotoEditor.xcodeproj` as the primary build, test, signing, and release format.
- Regenerate the project from `project.yml` with XcodeGen 2.45.4 after project-setting changes.
- Open the generated project in Xcode and use the Xcode integration for diagnostics after Swift or project edits. `xcodebuild` is the run-script fallback.
- Keep image processing geometry-only: orientation normalization, perspective correction, explicit quarter-turn rotation, explicit flips, and encoder-required color-profile handling.
- Never add automatic adjustment, white balance, exposure, contrast, saturation, sharpening, denoising, restoration, OCR, face analysis, or cloud upload code.
- Never modify imported originals. Copy them into the `.scanphoto` package and render exports from the copied bytes.
- Use normalized top-left-origin coordinates ordered top-left, top-right, bottom-right, bottom-left.
- Preserve undoability for user-visible geometry, creation, deletion, and ordering changes.
- Use preview-sized images while editing and decode full resolution only for export.
- SwiftUI views that render values from `PhotoProjectDocument.manifest` must observe the document directly; observing only `ProjectEditingStore` does not propagate the document's Combine updates.
