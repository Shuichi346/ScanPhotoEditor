# Engineering Notes

## 2026-06-24

- Filename sorting used localized natural comparison, so numbered names such as `Album 2` precede `Album 10`; it also regrouped `regionOrder` by source while preserving each source's existing region order.
- The filename-sort implementation was verified with an undo test and the full Xcode test suite, with all 20 tests passing.
- Detection candidates are deduplicated, ranked by confidence, limited by the persisted 1–32 preference, and then ordered spatially for display.
- The source canvas applied zoom independently to its minimum frame and rendered image, allowing the image to extend beyond the measured scroll bounds. `GeometryCanvasLayout` now derives both from one explicit zoomed canvas size.
- Crop previews updated correctly, but source-canvas guidelines stayed stale because the canvas observed the editing store while geometry lived in the document's published manifest. `GeometryCanvasView` now observes `PhotoProjectDocument` directly.
- The Xcode build and unit tests passed after the fix. The existing UI test runner exited before establishing its test connection.
- The application uses a package-based `ReferenceFileDocument`.
- Originals are retained as bytes in document state so unsaved imports can be written into a new package.
- Geometry uses normalized top-left-origin coordinates throughout the model and UI.
- Detection uses Vision `DetectRectanglesRequest`; rendering uses only Core Image perspective correction plus explicit user transformations.
- Processing concurrency is bounded to two source images.
