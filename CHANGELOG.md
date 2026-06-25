# Changelog

## Unreleased

- Fixed crashes when creating, saving, or reopening projects caused by forcing SwiftUI document callbacks onto the main actor.
- Fixed multi-region export crashes, moved full-resolution export off the main actor, and streamed PDF pages to keep memory bounded.
- Changed project originals to file-backed temporary storage and copied imports while security-scoped access remains active.
- Fixed progressive import updates, cancellation, failed-detection fallback regions, source/region reordering, and rerun-detection races.
- Added manifest/original validation, missing-thumbnail regeneration, source removal, stricter geometry validation, and polygon-IoU deduplication.
- Enabled App Sandbox with user-selected read/write access.
- Added separate JPEG, HEIC, and PDF image-quality settings, defaulting to 80%.
- Reduced PDF export size by embedding JPEG-compressed page images instead of raw full-resolution bitmap streams.
- Fixed the editor workspace unexpectedly switching from a top-and-bottom layout to a side-by-side layout during use.
- Fixed JPEG thumbnail and export encoding to discard unnecessary alpha data.
- Improved crop precision by making corner handles transparent and adding red crosshairs.
- Added undoable filename sorting for imported images, including export and PDF page ordering.
- Added a persisted setting for the maximum number of detections per image, defaulting to eight.
- Fixed source-image scrolling so the full image remains reachable when zoomed above 100%.
- Fixed crop guidelines and handles not following geometry changes during dragging.
- Initial macOS document application.
- Added recursive drag-and-drop import and automatic rectangle detection.
- Added non-destructive geometry editing and multi-format export.
