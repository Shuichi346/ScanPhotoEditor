# ScanPhotoEditor Repository Instructions

- Target macOS 26 or later on Apple Silicon with Swift 6.3 strict concurrency.
- Treat `ScanPhotoEditor.xcodeproj` as the primary build, test, signing, and release format.
- Regenerate the project from `project.yml` with XcodeGen 2.45.4 after project-setting changes.
- Change app versions through `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; keep `Info.plist` version keys bound to those build settings.
- Open the generated project in Xcode and use the Xcode integration for diagnostics after Swift or project edits. `xcodebuild` is the run-script fallback.
- Keep image processing geometry-only: orientation normalization, perspective correction, explicit quarter-turn rotation, explicit flips, and encoder-required color-profile handling.
- Never add automatic adjustment, white balance, exposure, contrast, saturation, sharpening, denoising, restoration, OCR, face analysis, or cloud upload code.
- Never modify imported originals. Copy them into the `.scanphoto` package and render exports from the copied bytes.
- Use normalized top-left-origin coordinates ordered top-left, top-right, bottom-right, bottom-left.
- Preserve undoability for user-visible geometry, creation, deletion, and ordering changes.
- When reordering source images, update both `SourceAsset.importOrder` for sidebar presentation and `ProjectManifest.regionOrder` for export/PDF ordering; preserve the current region order within each source.
- Use preview-sized images while editing and decode full resolution only for export.
- Keep imported originals file-backed in `ProjectFileStorage`; do not reintroduce a document-wide in-memory original-data dictionary.
- Keep PDF export page-streamed so full-resolution corrected images are not accumulated across pages.
- Keep successful export completion distinct from cancellation; only present the completion view for a finished, non-cancelled export report.
- Do not isolate `PhotoProjectDocument` or its `ReferenceFileDocument` conformance to `MainActor`; SwiftUI creates, opens, and snapshots reference documents on non-main queues.
- Before encoding JPEG thumbnails or exports with ImageIO, render opaque images as RGBX so the encoder does not receive an unnecessary alpha channel.
- Mark UI tests that use `XCUIApplication` or `XCUIElement` APIs as `@MainActor` under Swift strict concurrency.
- SwiftUI views that render values from `PhotoProjectDocument.manifest` must observe the document directly; observing only `ProjectEditingStore` does not propagate the document's Combine updates.
- In `GeometryCanvasView`, derive the rendered image rectangle and scrollable content size from the same zoomed canvas dimensions so the image never extends beyond the scroll bounds.
- Keep `EditorWorkspaceView` in a stable top-and-bottom layout with the source editor above the corrected preview; do not use content-measurement-driven layout switching such as `ViewThatFits`.
- Define main-window toolbar content only in `ProjectRootView`; do not add competing toolbar declarations to split-view child views. Group related controls with `ControlGroup` so sidebar and inspector width changes do not independently overflow actions.
- Keep source-wide actions in the Source Actions menu, region creation/deletion in their own `ControlGroup`, and transforms in the geometry group; do not expose source removal and region deletion as adjacent, indistinguishable trash buttons.

## Documentation maintenance

- After completed implementation work, update `CHANGELOG.md`, `NOTES.md`, and `AGENTS.md` in English using the current task's evidence, including already committed or pushed work.
- Record what changed in the changelog in past tense under `Fixed`, `Added`, `Changed`, and `Removed`. Omit empty categories and routine cleanup or test-only changes unless their impact matters.
- Use `## YYYY-MM-DD` for new work, newest first, and append to existing same-day categories. Use the completion date in the user's timezone; do not guess dates or release versions. Preserve existing dated/versioned history and classify undated historical entries directly under `Fixed`, `Added`, `Changed`, and `Removed`. Do not create new `Unreleased` sections.
- Keep causes, solution rationale, behavior to preserve, known useful paths/tests, and unresolved limitations in `NOTES.md`, following its existing conventions. Keep durable, verified repository instructions in `AGENTS.md`; avoid duplicate summaries, session logs, and one-time rules.
- Read only relevant sections needed to avoid duplicates or contradictions. Reuse task evidence; inspect the smallest relevant diff or source excerpt only for missing material facts, without routinely rebuilding history.
- For a full update, consider all three root files and create missing files with minimal headings. Leave existing files unchanged when there is nothing material to add.
- Review the documentation diff and unresolved references, and run required documentation checks. Documentation-only changes do not require rerunning implementation tests solely to record the work.
