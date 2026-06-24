# ScanPhotoEditor

ScanPhotoEditor is an offline macOS 26 app for extracting printed photographs from smartphone captures. It detects multiple rectangular photographs, corrects perspective, permits manual corner refinement, and exports images or an ordered PDF without applying visual enhancement.

## Build and run

Requirements:

- Apple Silicon Mac running macOS 26 or later
- Xcode 26.5 or later
- XcodeGen 2.45.4

```sh
xcodegen generate
./script/build_and_run.sh --verify
```

The Codex Run action invokes the same build script.

## Usage

1. Create or open a `.scanphoto` document.
2. Optionally set **ScanPhotoEditor → Settings → Maximum detections per image**. The default is 1.
3. Drop image files or folders anywhere in the document window.
4. Select detected regions in the sidebar.
5. Drag corner or edge handles over the source image. Use the toolbar to rotate, flip, add, delete, reset, or rerun detection.
6. Save the document. Originals, thumbnails, geometry, and order remain inside the package.
7. Choose **File → Export** to export selected or all regions as JPEG, HEIC, PNG, TIFF, and/or an ordered PDF.

Supported imports are HEIC/HEIF, JPEG, PNG, and TIFF. Hidden files, packages, and symlinks are skipped during recursive folder import.

## Image-preservation guarantee

The rendering pipeline is restricted to EXIF orientation normalization, perspective correction, explicit rotation, explicit flips, and encoder-required color-profile handling. It does not perform tone, color, restoration, sharpening, denoising, or other automatic enhancement.
