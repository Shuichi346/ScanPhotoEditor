# Changelog

## Unreleased

- Fixed the editor workspace unexpectedly switching from a top-and-bottom layout to a side-by-side layout during use.
- Fixed JPEG thumbnail and export encoding to discard unnecessary alpha data.
- Improved crop precision by making corner handles transparent and adding red crosshairs.
- Added undoable filename sorting for imported images, including export and PDF page ordering.
- Added a persisted setting for the maximum number of detections per image, defaulting to one.
- Fixed source-image scrolling so the full image remains reachable when zoomed above 100%.
- Fixed crop guidelines and handles not following geometry changes during dragging.
- Initial macOS document application.
- Added recursive drag-and-drop import and automatic rectangle detection.
- Added non-destructive geometry editing and multi-format export.
