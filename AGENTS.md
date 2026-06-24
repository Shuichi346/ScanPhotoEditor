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
- When reordering source images, update both `SourceAsset.importOrder` for sidebar presentation and `ProjectManifest.regionOrder` for export/PDF ordering; preserve the current region order within each source.
- Use preview-sized images while editing and decode full resolution only for export.
- Before encoding JPEG thumbnails or exports with ImageIO, render opaque images as RGBX so the encoder does not receive an unnecessary alpha channel.
- Mark UI tests that use `XCUIApplication` or `XCUIElement` APIs as `@MainActor` under Swift strict concurrency.
- SwiftUI views that render values from `PhotoProjectDocument.manifest` must observe the document directly; observing only `ProjectEditingStore` does not propagate the document's Combine updates.
- In `GeometryCanvasView`, derive the rendered image rectangle and scrollable content size from the same zoomed canvas dimensions so the image never extends beyond the scroll bounds.
- Keep `EditorWorkspaceView` in a stable top-and-bottom layout with the source editor above the corrected preview; do not use content-measurement-driven layout switching such as `ViewThatFits`.
