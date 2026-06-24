# Engineering Notes

## 2026-06-24

- The editor workspace switched layouts because `ViewThatFits` re-evaluated whether its horizontal candidate fit as child measurements changed. `EditorWorkspaceView` now uses a fixed vertical stack for stable source-above-preview presentation.
- The layout fix passed Xcode diagnostics, Debug build, launch verification, and unit tests. The UI-test runner still exited before establishing its connection when run from `xcodebuild`.
- JPEG thumbnails and exports now use an opaque RGBX render before ImageIO encoding, preventing the `AlphaPremulLast` warning and avoiding unnecessary decode memory.
- JPEG, HEIC, and PDF image quality are persisted as separate 1–100 settings with an 80% default; PDF pages use JPEG-compressed image streams to avoid raw-bitmap file growth.
- The full unit and UI test suite passed with normal Xcode signing; disabling code signing caused the UI-test runner to exit before establishing its connection.
- Crop corner handles were changed from opaque white circles to transparent scope-style controls with red crosshairs; Xcode diagnostics, the full build, and launch verification passed.
- Filename sorting used localized natural comparison, so numbered names such as `Album 2` precede `Album 10`; it also regrouped `regionOrder` by source while preserving each source's existing region order.
- The filename-sort implementation was verified with an undo test and the full Xcode test suite, with all 20 tests passing.
- Detection candidates are deduplicated, ranked by confidence, limited by the persisted 1–32 preference, and then ordered spatially for display.
- The source canvas applied zoom independently to its minimum frame and rendered image, allowing the image to extend beyond the measured scroll bounds. `GeometryCanvasLayout` now derives both from one explicit zoomed canvas size.
- Crop previews updated correctly, but source-canvas guidelines stayed stale because the canvas observed the editing store while geometry lived in the document's published manifest. `GeometryCanvasView` now observes `PhotoProjectDocument` directly.
- The application uses a package-based `ReferenceFileDocument`.
- Originals are retained as bytes in document state so unsaved imports can be written into a new package.
- Geometry uses normalized top-left-origin coordinates throughout the model and UI.
- Detection uses Vision `DetectRectanglesRequest`; rendering uses only Core Image perspective correction plus explicit user transformations.
- Processing concurrency is bounded to two source images.
