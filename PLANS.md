# Implementation Plan: ScanPhotoEditor for macOS 26

## Overview

Build an offline Apple Silicon macOS app that imports smartphone photos by drag and drop, automatically detects one or more printed photographs, corrects perspective distortion, and permits manual geometry refinement before batch export.

All processing is non-destructive and geometry-only. The app must never apply white balance, exposure, contrast, saturation, sharpening, denoising, OCR, or automatic visual enhancement.

## Stated Assumptions and Decisions

1. Target: macOS 26+, Apple Silicon only, Swift 6.3.
2. App name: `ScanPhotoEditor`.
3. Bundle ID: `com.shuichi.ScanPhotoEditor`.
4. Project documents use the `.scanphoto` package format and copy originals into the project.
5. Supported inputs: HEIC/HEIF, JPEG, PNG, and TIFF.
6. Dropped folders are searched recursively; hidden files, packages, and symlinks are skipped.
7. Multiple photographs may be extracted from one source image.
8. Processing starts automatically after import; confirmation is not required.
9. Missed or incorrect detections are fixed afterward using the geometry editor.
10. Outputs: JPEG, HEIC, PNG, TIFF, and an optional ordered multi-page PDF.
11. UI is English-first and uses localizable strings.
12. The supplied screenshot is an interaction reference only and is not added to the repository.

## Requirements

1. Accept multiple files and folders by dropping them anywhere in the main window.
2. Copy supported originals into the project without modifying source files.
3. Normalize EXIF orientation before detection or coordinate calculations.
4. Automatically detect multiple non-overlapping rectangular photographs per source.
5. Generate corrected previews immediately after detection.
6. Create a full-frame region marked `Needs Review` when no rectangle is found.
7. Provide draggable corner and edge handles, an 8×8 grid, zoom, pan, rotate, flip, reset, add/delete region, and rerun detection.
8. Support undo/redo for geometry, deletion, creation, and ordering changes.
9. Preserve original pixel resolution except where perspective correction changes output bounds.
10. Never invoke image enhancement or tone/color adjustment filters.
11. Save non-destructive edits, ordering, thumbnails, and copied originals in the project package.
12. Export selected or all regions with progress, cancellation, conflict-safe filenames, and a failure report.

## Tech Stack and Conventions

- SwiftUI for the document window, sidebar, editor, inspector, commands, and drop targets.
- `ReferenceFileDocument` and `FileWrapper` for `.scanphoto` packages.
- Vision `DetectRectanglesRequest` for automatic rectangle detection.
- Core Image `CIPerspectiveCorrection` for geometry correction.
- ImageIO for decoding and JPEG/HEIC/PNG/TIFF encoding.
- Core Graphics for ordered PDF generation.
- AppKit only for save/destination panels and narrow window integration.
- Swift concurrency with a processing limit of two source images at once.
- XCTest and XCUITest.
- XcodeGen 2.45.4 as a development-only project generator; no third-party runtime dependencies.

Target structure:

```text
project.yml
ScanPhotoEditor/
  App/
  Documents/
  Models/
  Services/
  Stores/
  Views/
  Support/
  Resources/
ScanPhotoEditorTests/
ScanPhotoEditorUITests/
script/build_and_run.sh
.codex/environments/environment.toml
```

### Project Package

```text
Example.scanphoto/
  manifest.json
  Originals/
    <source-uuid>.<original-extension>
  Thumbnails/
    <source-uuid>.jpg
```

`manifest.json` uses schema version `1` and contains:

- `ProjectManifest`: project ID, timestamps, sources, and global output order.
- `SourceAsset`: ID, display name, stored filename, UTI, pixel dimensions, import order, processing state, and regions.
- `PhotoRegion`: ID, source ID, quadrilateral, origin, review state, rotation, flips, and ordering.
- `NormalizedQuadrilateral`: points ordered top-left, top-right, bottom-right, bottom-left in upright image coordinates, with a top-left origin and values from 0 through 1.

### Detection Rules

Use these initial Vision settings:

- `maximumObservations = 32`
- `minimumSize = 0.05`
- `minimumConfidence = 0.35`
- `minimumAspectRatio = 0.20`
- `maximumAspectRatio = 1.00`
- `quadratureToleranceDegrees = 35`

Reject self-intersecting or out-of-range quadrilaterals and regions below 1.5% normalized area. Deduplicate candidates with polygon IoU of at least 0.80, retaining the higher-confidence candidate.

Initial ordering is source import order, then region centroid from top-to-bottom and left-to-right. Manual reordering overrides it.

### Rendering Invariant

The rendering chain may contain only:

1. EXIF orientation normalization.
2. Perspective correction.
3. Explicit user-requested quarter-turn rotation.
4. Explicit horizontal or vertical flip.
5. Color-profile handling required by the output encoder.

Do not call automatic adjustment APIs or Core Image tone, color, restoration, noise, or sharpening filters.

## Boundaries

### Always

- Keep originals unchanged.
- Process locally.
- Use preview-sized images for editing and full resolution only during export.
- Write exports through temporary files followed by atomic replacement.
- Preserve embedded color profiles where the destination supports them.
- Strip GPS and phone-specific capture metadata from exports.

### Ask First

- Installing XcodeGen through Homebrew if it is unavailable.
- Changing the bundle ID, package format, deployment target, or runtime dependencies.
- Adding the supplied screenshot or other user files to the repository.
- Adding cloud synchronization, App Store signing, or notarization.

### Never

- Apply hidden image enhancement.
- Overwrite imported originals.
- Upload photos or metadata.
- Add OCR, facial analysis, or restoration features to this release.
- Follow folder symlinks outside the dropped directory.

## Agent Summary

| Agent | Step Count | Phases Involved |
|---|---:|---|
| `devops-agent` | 1 | 1 |
| `coding-agent` | 14 | 1–5 |
| `review-agent` | 5 | 1–5 |
| `documentation-agent` | 1 | 5 |

## Implementation Steps

### Phase 1 — Project and Document Foundation

#### Step 1.1 — Scaffold the macOS project

- **Agent:** `devops-agent`
- **Location:** `project.yml`, `script/build_and_run.sh`, `.codex/environments/environment.toml`
- **Action:** Create the XcodeGen project, app/test targets, sandbox entitlements, Info.plist document declarations, deterministic build script, and Codex Run action.
- **Details:** Set macOS 26.0, arm64, Swift 6 strict concurrency, `.scanphoto` package UTI, and user-selected read/write entitlement. The run script must support `--debug`, `--logs`, `--telemetry`, and `--verify`.
- **Dependencies:** None
- **Verification:** Generate the project, build an empty app, run `./script/build_and_run.sh --verify`, and confirm the process exists.
- **Complexity:** Medium
- **Risk:** Medium because project metadata and document declarations must agree.
- **Idempotence & Recovery:** Regenerating from `project.yml` must produce the same project. Delete only the generated `.xcodeproj` when regeneration is necessary.

#### Step 1.2 — Define models and geometry primitives

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Models`, `ScanPhotoEditor/Support/Geometry`
- **Action:** Implement the manifest, source, region, processing-state, export-option, normalized-point, and quadrilateral types.
- **Details:** Centralize Vision, Core Image, and SwiftUI coordinate conversions. Validate clockwise ordering, minimum area, clamping, and non-intersection.
- **Dependencies:** 1.1
- **Verification:** Unit tests cover all eight EXIF orientations, coordinate round trips, invalid polygons, and corner ordering.
- **Complexity:** High
- **Risk:** High because coordinate errors can silently produce incorrect crops.
- **Idempotence & Recovery:** Pure value-model work; revert the affected files if tests expose an invalid convention.

#### Step 1.3 — Implement project-package persistence

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Documents/PhotoProjectDocument.swift`
- **Action:** Implement the reference document, package reader/writer, schema validation, staging of unsaved imports, and thumbnail recovery.
- **Details:** Write `manifest.json` atomically. Preserve regular-file wrappers for unchanged originals. Missing thumbnails must be regenerated; missing originals must produce a visible project error.
- **Dependencies:** 1.2
- **Verification:** Save, close, and reopen a package containing multiple sources and regions; confirm IDs, geometry, ordering, and copied bytes are unchanged.
- **Complexity:** High
- **Risk:** High due to large-file persistence and autosave behavior.
- **Idempotence & Recovery:** Save through a temporary package and replace only after validation. Retain the previous package if writing fails.

#### Step 1.G — Foundation gate

- **Agent:** `review-agent`
- **Location:** Entire Phase 1
- **Action:** Review project generation, model invariants, and package round trips.
- **Details:** Confirm the phase leaves a buildable app and a valid document format.
- **Dependencies:** 1.1, 1.2, 1.3
- **Verification:** Run the arm64 build and model/document tests. Confirm a `.scanphoto` package opens as one Finder document.
- **Complexity:** Medium
- **Risk:** Low

### Phase 2 — Import and Automatic Processing

#### Step 2.1 — Implement drag-and-drop discovery and import

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/ImageImportService.swift`
- **Action:** Accept dropped URLs, recursively discover supported images, acquire security-scoped access, and copy originals into project staging.
- **Details:** Skip hidden files, packages, symlinks, unsupported formats, and duplicate URLs. Use the first frame of multi-frame images. Return an import report listing imported and skipped files.
- **Dependencies:** 1.G
- **Verification:** Drop mixed files and nested folders; supported files import once and unsupported files appear in the summary.
- **Complexity:** Medium
- **Risk:** Medium because sandbox access expires.
- **Idempotence & Recovery:** Copy to a temporary filename and rename after success. Remove incomplete copies after failure.

#### Step 2.2 — Implement orientation-safe image loading

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/ImageLoader.swift`
- **Action:** Decode metadata, normalize orientation, create 512-pixel thumbnails, and create detection/preview images with bounded dimensions.
- **Details:** Detection images use a maximum dimension of 2048 pixels; editor previews use 1600 pixels. Full-resolution decoding is deferred to export.
- **Dependencies:** 2.1
- **Verification:** Portrait and mirrored fixture images display upright and map identical normalized points to their source pixels.
- **Complexity:** High
- **Risk:** High because double-applied EXIF orientation corrupts geometry.
- **Idempotence & Recovery:** Derived images are disposable and may be regenerated.

#### Step 2.3 — Implement multi-region rectangle detection

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/RectangleDetectionService.swift`
- **Action:** Run Vision detection, convert observations into canonical quadrilaterals, validate/deduplicate them, and return ordered candidates.
- **Details:** Apply all accepted regions automatically. If none survive validation, create one full-frame `Needs Review` region.
- **Dependencies:** 2.2
- **Verification:** Synthetic one-photo and multi-photo fixtures produce valid regions; blank and irregular fixtures produce a review fallback without crashing.
- **Complexity:** High
- **Risk:** High because natural backgrounds may produce false positives.
- **Idempotence & Recovery:** Detection is deterministic for the same input and settings and can be rerun safely.

#### Step 2.4 — Implement the batch processing coordinator

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/ProcessingCoordinator.swift`
- **Action:** Queue imports, limit processing to two sources, publish per-source progress, support cancellation, and isolate individual failures.
- **Details:** One failed source must not stop the batch. Completed regions become immediately selectable while remaining sources continue.
- **Dependencies:** 2.2, 2.3
- **Verification:** Process at least 20 generated sources; cancellation stops pending work, completed items remain valid, and failures are reported per source.
- **Complexity:** High
- **Risk:** Medium due to memory and cancellation behavior.
- **Idempotence & Recovery:** Restart only queued, cancelled, or failed sources; never duplicate completed regions.

#### Step 2.G — Processing gate

- **Agent:** `review-agent`
- **Location:** Entire Phase 2
- **Action:** Review import safety, orientation correctness, detection behavior, concurrency, and cancellation.
- **Details:** Confirm automatic processing starts directly after a valid drop.
- **Dependencies:** 2.1, 2.2, 2.3, 2.4
- **Verification:** Drag a folder containing HEIC, JPEG, PNG, TIFF, unsupported files, and nested folders. Confirm automatic processing begins without confirmation.
- **Complexity:** Medium
- **Risk:** Low

### Phase 3 — Geometry Editor

#### Step 3.1 — Build the document workspace

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Views/ProjectRootView.swift`
- **Action:** Create a native sidebar-detail-inspector workspace.
- **Details:** Sidebar groups sources and extracted regions with thumbnails and statuses. The detail area shows source editor and corrected preview side-by-side. The inspector contains geometry-only actions and metadata.
- **Dependencies:** 2.G
- **Verification:** Selection remains stable during background processing and project reopening.
- **Complexity:** Medium
- **Risk:** Low

#### Step 3.2 — Build the interactive quadrilateral canvas

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Views/Editor/GeometryCanvasView.swift`
- **Action:** Render all regions over the source and implement selection, four corner handles, four edge handles, 8×8 grid, zoom, and pan.
- **Details:** Clamp handles to image bounds, reject self-intersection, enforce minimum area, and update the corrected preview during dragging.
- **Dependencies:** 3.1
- **Verification:** Corner and edge drags produce valid perspective previews at multiple zoom levels and window sizes.
- **Complexity:** High
- **Risk:** High because pointer coordinates must remain accurate under scaling and panning.
- **Idempotence & Recovery:** All edits use reversible model mutations through the undo manager.

#### Step 3.3 — Implement geometry operations and ordering

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Stores/ProjectEditingStore.swift`
- **Action:** Add region creation/deletion, reset, rerun detection, rotate, flip, source removal, and drag reordering.
- **Details:** New regions start as centered 80% rectangles. Rerun detection replaces untouched automatic regions; if manual edits exist, require confirmation before replacing them. Global region order controls export and PDF order.
- **Dependencies:** 3.2
- **Verification:** Each operation supports Command-Z and Command-Shift-Z and survives save/reopen.
- **Complexity:** High
- **Risk:** Medium because destructive reruns could discard manual work.
- **Idempotence & Recovery:** Use undo groups and retain prior region arrays for replacement operations.

#### Step 3.4 — Add desktop commands and status feedback

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/App`, `ScanPhotoEditor/Views/Components`
- **Action:** Add toolbar/menu actions, keyboard shortcuts, drop highlighting, progress, cancellation, errors, and empty states.
- **Details:** Drag and drop remains the primary import path. Commands include rotate, delete region, toggle grid, rerun detection, undo/redo, and export.
- **Dependencies:** 3.1, 3.3
- **Verification:** All core actions are reachable by pointer and keyboard; failures do not block editing successful items.
- **Complexity:** Medium
- **Risk:** Low

#### Step 3.G — Editor gate

- **Agent:** `review-agent`
- **Location:** Entire Phase 3
- **Action:** Perform interaction and accessibility review.
- **Details:** Verify geometry-only controls are discoverable and keyboard accessible.
- **Dependencies:** 3.1, 3.2, 3.3, 3.4
- **Verification:** Import an image, adjust every handle, add/delete a region, reorder outputs, undo all changes, and reopen the project.
- **Complexity:** Medium
- **Risk:** Low

### Phase 4 — Rendering and Export

#### Step 4.1 — Implement the geometry-only renderer

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/PerspectiveRenderer.swift`
- **Action:** Apply canonical geometry at preview and full resolution using `CIPerspectiveCorrection`, then explicit rotation and flips.
- **Details:** Reuse a bounded-memory `CIContext`; use autorelease pools around full-resolution batch work. Do not resize the corrected extent.
- **Dependencies:** 3.G
- **Verification:** A full-frame identity region produces pixels matching the orientation-normalized source within color-management tolerance.
- **Complexity:** High
- **Risk:** High because rendering must prove it makes no hidden visual corrections.
- **Idempotence & Recovery:** Rendering is stateless and safely repeatable.

#### Step 4.2 — Implement image export

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/ImageExportService.swift`
- **Action:** Encode JPEG, HEIC, PNG, and TIFF through ImageIO.
- **Details:** JPEG and HEIC quality default to 0.95; PNG is lossless; TIFF uses LZW. Name outputs `<source-name>_<region-number>`, adding a numeric suffix on conflicts. Strip GPS/device metadata and normalize orientation to upright.
- **Dependencies:** 4.1
- **Verification:** Decode every exported format and confirm dimensions, orientation, color profile, and corrected geometry.
- **Complexity:** High
- **Risk:** Medium because encoder support and metadata vary by format.
- **Idempotence & Recovery:** Write temporary sibling files and rename after successful finalization.

#### Step 4.3 — Implement PDF and export workflow

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditor/Services/PDFExportService.swift`, `ScanPhotoEditor/Views/Export`
- **Action:** Build one ordered multi-page PDF and an export sheet supporting all or selected regions.
- **Details:** Use 300-DPI-equivalent page dimensions while preserving each image’s aspect ratio. Default export enables JPEG images and the combined PDF. Provide progress, cancellation, final destination reveal, and per-file failures.
- **Dependencies:** 4.1, 4.2
- **Verification:** PDF page count and order match the region list; cancelled exports leave no incomplete files.
- **Complexity:** High
- **Risk:** Medium due to potentially large batches.
- **Idempotence & Recovery:** Build the PDF at a temporary URL and move it only after the final page succeeds.

#### Step 4.G — Export gate

- **Agent:** `review-agent`
- **Location:** Entire Phase 4
- **Action:** Review output fidelity and prohibited-filter compliance.
- **Details:** Verify every output path uses the same geometry-only rendering invariant.
- **Dependencies:** 4.1, 4.2, 4.3
- **Verification:** Export every format and inspect the PDF. Search production source for automatic adjustment, white balance, color control, exposure, sharpening, denoising, and restoration APIs; expected result is no matches.
- **Complexity:** Medium
- **Risk:** Low

### Phase 5 — Hardening and Delivery

#### Step 5.1 — Complete automated tests

- **Agent:** `coding-agent`
- **Location:** `ScanPhotoEditorTests`, `ScanPhotoEditorUITests`
- **Action:** Add model, coordinate, document, import, detection, rendering, export, cancellation, and core UI-flow tests.
- **Details:** Generate test images programmatically so tests do not depend on personal files.
- **Dependencies:** 4.G
- **Verification:** All tests pass repeatedly on arm64 macOS 26.
- **Complexity:** High
- **Risk:** Low

#### Step 5.2 — Performance and recovery hardening

- **Agent:** `coding-agent`
- **Location:** Processing, persistence, and export services
- **Action:** Profile a 100-image batch, remove unbounded caches, verify cancellation, and add recovery for corrupt manifests or missing originals.
- **Details:** Target responsive scrolling/editing while processing and avoid retaining full-resolution decoded images after each operation.
- **Dependencies:** 5.1
- **Verification:** A 100-image synthetic batch completes without termination or continuously increasing memory; a damaged project produces a recoverable error.
- **Complexity:** High
- **Risk:** Medium because workload depends on source dimensions.
- **Idempotence & Recovery:** Performance changes must preserve package schema and output behavior.

#### Step 5.3 — Document usage and architecture

- **Agent:** `documentation-agent`
- **Location:** `README.md`, `PLANS.md`
- **Action:** Document drag-and-drop import, automatic processing, manual geometry controls, project packages, exports, build commands, and the strict no-enhancement guarantee.
- **Details:** Keep user instructions concise while documenting implementation invariants needed by future agents.
- **Dependencies:** 5.2
- **Verification:** A new user can build, run, import, adjust, save, reopen, and export using only the documentation.
- **Complexity:** Low
- **Risk:** Low

#### Step 5.G — Final acceptance gate

- **Agent:** `review-agent`
- **Location:** Entire repository
- **Action:** Perform final build, test, launch, behavior, and plan-compliance review.
- **Details:** Verify the complete user flow and all non-negotiable image-preservation requirements.
- **Dependencies:** 5.1, 5.2, 5.3
- **Verification:**
  1. Run XcodeGen.
  2. Build and test the arm64 app.
  3. Run `./script/build_and_run.sh --verify`.
  4. Drop a folder with multiple formats.
  5. Confirm automatic multi-photo processing.
  6. Correct geometry manually.
  7. Save and reopen the project.
  8. Export all image formats and an ordered PDF.
  9. Confirm no visual enhancement occurs.
- **Complexity:** Medium
- **Risk:** Low

## Risks and Mitigations

1. **False or missed rectangle detections:** Allow immediate manual add/delete/edit and retain a full-frame fallback.
2. **Orientation and coordinate errors:** Use one canonical coordinate system and exhaustive EXIF tests.
3. **Memory pressure:** Limit processing concurrency to two, use bounded previews, and decode full resolution only during export.
4. **Large package saves:** Reuse unchanged wrappers, write temporary packages, and atomically replace validated output.
5. **Unexpected color changes:** Ban enhancement filters and add identity-render pixel regression tests.
6. **Lost manual work:** Use undo groups, autosave, and confirmation before replacing edited regions.
7. **Expired sandbox access:** Copy dropped files while security-scoped access is active.

## Success Criteria

- [ ] Dragging files or folders starts processing automatically.
- [ ] Multiple photographs can be extracted from one source.
- [ ] Perspective correction works without tone or color changes.
- [ ] Every detected region can be corrected through the GUI.
- [ ] Projects reopen with originals, edits, thumbnails, and ordering intact.
- [ ] Batch exports succeed as JPEG, HEIC, PNG, TIFF, and combined PDF.
- [ ] Cancellation and per-file failures leave valid completed work.
- [ ] The app builds, tests, and launches on arm64 macOS 26.

## Progress

- [ ] Step 1.1: Project scaffold
- [ ] Step 1.2: Models and geometry
- [ ] Step 1.3: Project persistence
- [ ] Step 1.G: Foundation gate
- [ ] Step 2.1: Drag-and-drop import
- [ ] Step 2.2: Image loading
- [ ] Step 2.3: Rectangle detection
- [ ] Step 2.4: Batch coordinator
- [ ] Step 2.G: Processing gate
- [ ] Step 3.1: Workspace
- [ ] Step 3.2: Geometry canvas
- [ ] Step 3.3: Editing operations
- [ ] Step 3.4: Commands and feedback
- [ ] Step 3.G: Editor gate
- [ ] Step 4.1: Perspective renderer
- [ ] Step 4.2: Image export
- [ ] Step 4.3: PDF export
- [ ] Step 4.G: Export gate
- [ ] Step 5.1: Automated tests
- [ ] Step 5.2: Hardening
- [ ] Step 5.3: Documentation
- [ ] Step 5.G: Final acceptance

Completed entries must include a UTC timestamp.

## Decision Log

- **Decision:** Corrections are geometry-only; visual enhancements are prohibited.
  **Rationale:** The app must preserve the photographed image’s appearance.
  **Date:** 2026-06-24
- **Decision:** Processing starts automatically after drag and drop.
  **Rationale:** Manual review occurs after initial batch correction.
  **Date:** 2026-06-24
- **Decision:** One source may contain multiple independently editable photo regions.
  **Rationale:** Supports photographing several old prints at once.
  **Date:** 2026-06-24
- **Decision:** Originals are copied into portable project packages.
  **Rationale:** Saved projects must not break when source files move.
  **Date:** 2026-06-24

## Surprises and Discoveries

- None yet.

## Outcomes and Retrospective

- Not started.
