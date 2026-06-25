<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# ScanPhotoEditor

ScanPhotoEditor is an offline macOS document app for extracting individual printed photographs from smartphone captures. It automatically detects multiple photos, corrects perspective, provides precise manual geometry controls, and exports full-resolution images or an ordered PDF without applying automatic image enhancement.

## Screenshots

<table>
  <tr>
    <td align="center">
      <img src="githubreadme/demo-00.png" alt="A new ScanPhotoEditor document ready for dropped photos" width="350"><br>
      <sub>Drop image files or folders into a new project.</sub>
    </td>
    <td align="center">
      <img src="githubreadme/demo-01.png" alt="ScanPhotoEditor geometry editor and corrected preview" width="350"><br>
      <sub>Refine detected corners while viewing the corrected result.</sub>
    </td>
    <td align="center">
      <img src="githubreadme/demo-02.png" alt="An ordered PDF exported by ScanPhotoEditor" width="350"><br>
      <sub>Export corrected regions as an ordered multi-page PDF.</sub>
    </td>
  </tr>
</table>

## Features

- Recursively imports HEIC/HEIF, JPEG, PNG, and TIFF files from drag-and-dropped files or folders.
- Detects multiple rectangular photographs in each source image with Apple Vision.
- Provides draggable corner and edge handles, an optional 8×8 grid, and zoomable source previews.
- Supports manual regions, detection reruns, full-frame reset, quarter-turn rotation, and horizontal or vertical flips.
- Keeps geometry edits, region creation and deletion, source removal, and ordering changes undoable.
- Reorders sources and regions by drag and drop, or sorts source images by filename using natural numeric order.
- Saves copied originals, thumbnails, geometry, and export order in a portable `.scanphoto` package.
- Exports all regions or the selected region as JPEG, HEIC, PNG, TIFF, and/or an ordered multi-page PDF.
- Provides separate JPEG, HEIC, and PDF quality settings, export progress, cancellation, failure reporting, and conflict-safe filenames.
- Processes photos locally with no cloud upload or third-party runtime dependencies.

## Image-preservation policy

The rendering pipeline is intentionally geometry-only:

1. EXIF orientation normalization
2. Perspective correction
3. Explicit quarter-turn rotation
4. Explicit horizontal or vertical flips
5. Color-profile handling required by the encoder

ScanPhotoEditor does not apply automatic exposure, white balance, contrast, saturation, sharpening, denoising, restoration, OCR, or face analysis. Imported originals are copied into the project package and are never modified.

## Requirements

- Apple Silicon Mac
- macOS 26.0 or later
- Xcode 26.5 or later
- XcodeGen 2.45.4 when regenerating the Xcode project

## Build and run

The checked-in `ScanPhotoEditor.xcodeproj` is the primary project. Open it in Xcode and run the `ScanPhotoEditor` scheme, or build and launch from Terminal:

```sh
./script/build_and_run.sh
```

To regenerate the project after changing `project.yml`:

```sh
xcodegen generate
```

The build script also supports `--debug`, `--logs`, `--telemetry`, and `--verify`.

## Usage

1. Create a new document or open an existing `.scanphoto` project.
2. Drop supported image files or folders anywhere in the document window.
3. Select a detected region in the sidebar.
4. Drag its corner or edge handles to refine the crop. Use the grid and corrected preview to check alignment.
5. Rotate, flip, add, delete, reset, reorder, or rerun detection as needed.
6. Save the document to preserve copied originals and non-destructive edits.
7. Choose **File → Export…**, select the output formats and regions, then choose a destination folder.

If no rectangle is detected, the app creates a full-frame region marked **Needs Review** so it can be corrected manually.

## Project format

A `.scanphoto` document is a package containing the project manifest, copied original files, and generated thumbnails:

```text
Example.scanphoto/
├── manifest.json
├── Originals/
└── Thumbnails/
```

Editing uses preview-sized images. Full-resolution originals are decoded only during export, and PDF pages are rendered one at a time to keep memory use bounded.

## Development

The app uses:

- SwiftUI for the document interface, editor, inspector, settings, and export workflow
- Vision for rectangle detection
- Core Image for perspective correction
- ImageIO for image decoding and encoding
- Core Graphics for streamed PDF generation
- `ReferenceFileDocument` and `FileWrapper` for `.scanphoto` packages
- XCTest and XCUITest for automated coverage

Run the test suite with:

```sh
xcodebuild \
  -project ScanPhotoEditor.xcodeproj \
  -scheme ScanPhotoEditor \
  -destination 'platform=macOS,arch=arm64' \
  test
```

## License

ScanPhotoEditor is available under the [MIT License](LICENSE).
