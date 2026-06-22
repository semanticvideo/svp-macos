# SVP System Support — Verification Report

**Date:** June 21, 2026  
**Project:** svp-system-support  
**Target:** macOS 15.6+ (built on macOS 26.5, Xcode 26.4)

---

## 1. Architecture Summary

### Components Built

| Component | Type | Bundle ID | Status |
|-----------|------|-----------|--------|
| SVPReader | Local Swift Package | — | ✅ PASS |
| svp-system-support | Host app (carrier) | `com.cueit.svp-system-support` | ✅ PASS |
| svp-preview | Quick Look Preview Extension | `com.cueit.svp-system-support.svp-preview` | ✅ PASS |
| svp-media-reader | MediaExtension Format Reader | `com.cueit.svp-system-support.svp-media-reader` | ✅ PASS |

### Key Design Decisions

- **Pure Swift ZIP reader** — No libzip dependency; uses `FileHandle` + custom `ZipReader` with C zlib wrapper (`CZlib`) for deflate decompression. Safe for sandboxed extensions.
- **Materialization strategy** — Both Quick Look and MediaExtension extract the embedded media file (`media/original/source_000.MOV`) to a temp directory, then play via `AVFoundation`. Temp files are cleaned up on deinit.
- **UTType registration** — `com.semanticvideo.svp` declared in host app `Info.plist` via `UTExportedTypeDeclarations`, conforming to `public.movie`, `public.audiovisual-content`, `public.zip-archive`.
- **MediaExtension** — Implements `MEFormatReaderExtension` protocol. Materializes media, creates `AVURLAsset`, and wraps its tracks in `SVPTrackReader` / `SVPSampleCursor` stubs.

---

## 2. Build Results

### SVPReader Swift Package

```
$ cd SVPReader && swift build
Build complete! (0.99s)
```

**Result:** ✅ PASS

### Xcode Project (Debug)

```
$ xcodebuild -project svp-system-support.xcodeproj -scheme svp-system-support -configuration Debug build
** BUILD SUCCEEDED **
```

**Result:** ✅ PASS — All 5 targets compile (host app, tests, UI tests, Quick Look extension, MediaExtension).

### Xcode Project Targets

```
$ xcodebuild -project svp-system-support.xcodeproj -list
Targets:
    svp-system-support
    svp-system-supportTests
    svp-system-supportUITests
    svp-preview
    svp-media-reader
```

**Result:** ✅ PASS — All targets recognized, SVPReader local package resolved.

---

## 3. Test Results

### SVPReader Unit Tests

```
$ cd SVPReader && swift test
Test Case 'testInvalidFile' passed (0.003 seconds)
Test Case 'testLocatePrimaryMedia' passed (0.001 seconds)
Test Case 'testMaterializePrimaryMedia' passed (0.274 seconds)
Test Case 'testOpenAndMaterialize' passed (0.105 seconds)
Test Case 'testOpenAndValidateSVP' passed (0.009 seconds)
Test Case 'testReadManifest' passed (0.014 seconds)
Executed 6 tests, with 0 failures (0 unexpected) in 0.406 seconds
```

**Result:** ✅ PASS — 6/6 tests passed

### Test Details

| Test | Verifies | Result |
|------|----------|--------|
| `testInvalidFile` | Non-ZIP file is rejected | ✅ PASS |
| `testOpenAndValidateSVP` | SVP mimetype + manifest validation | ✅ PASS |
| `testReadManifest` | manifest.json fields (svp_version, package_id, primary_media_id) | ✅ PASS |
| `testLocatePrimaryMedia` | Media path `media/original/source_000.MOV`, extension, playability | ✅ PASS |
| `testMaterializePrimaryMedia` | Media extraction to temp dir, file exists, size > 0 | ✅ PASS |
| `testOpenAndMaterialize` | Full pipeline: validate → manifest → locate → extract | ✅ PASS |

---

## 4. PKG Installer

### Build Script

```
$ ./build-pkg.sh
```

**Result:** ✅ PASS — Script builds Release configuration and creates `SVPSystemSupport.pkg` using `pkgbuild`.

### Post-Install

The `scripts/postinstall` script registers the host app and both extensions with Launch Services via `lsregister`.

---

## 5. Quick Look Preview

### Implementation

- **File:** `svp-preview/PreviewViewController.swift`
- **Approach:** `QLPreviewingController` with `AVPlayerView` for inline video playback
- **Flow:** Open SVP → validate → locate media → extract to temp → create `AVPlayer` → auto-play
- **Cleanup:** Temp directory removed on `deinit`
- **Error UI:** Shows centered error message for invalid files or unsupported codecs

### Info.plist

- `QLSupportedContentTypes`: `["com.semanticvideo.svp"]`
- `NSExtensionPointIdentifier`: `com.apple.quicklook.preview`
- `NSExtensionPrincipalClass`: `$(PRODUCT_MODULE_NAME).PreviewViewController`

**Result:** ✅ PASS (compiles, code signing required for runtime testing)

---

## 6. MediaExtension Format Reader

### Implementation

- **Files:** `svp-media-reader/SVPFormatReaderExtension.swift`, `SVPFormatReader.swift`, `SVPTrackReader.swift`, `SVPSampleCursor.swift`
- **Protocol:** `MEFormatReaderExtension` with `@objc(SVPFormatReaderExtension)` principal class
- **Flow:** Receive `MEByteSource` → open SVP from file path → validate → extract media → create `AVURLAsset` → expose tracks via `SVPTrackReader`
- **Entitlement:** `com.apple.developer.mediaextension.formatreader` in `svp-media-reader.entitlements`

### Info.plist

- `EXExtensionPointIdentifier`: `com.apple.mediaextension.formatreader`
- `EXPrincipalClass`: `$(PRODUCT_MODULE_NAME).SVPFormatReaderExtension`
- `MTUTTypeArray`: `["com.semanticvideo.svp"]`
- `MTFileNameExtensionArray`: `["svp"]`
- `UTExportedTypeDeclarations`: `com.semanticvideo.svp` conforming to `com.apple.mediaextension-content`, `public.movie`, `public.audiovisual-content`

### Known Limitations

- `SVPSampleCursor` is a stub implementation. `loadSampleBufferContainingSamples` returns `MEError.noSamples`. Full sample buffer delivery requires implementing `AVAssetReader`-based sample extraction.
- `SVPTrackReader` uses synchronous `AVAssetTrack` properties (deprecated but functional on macOS 15.6).

**Result:** ✅ PASS (compiles, requires entitlement provisioning for runtime testing)

---

## 7. File Type Registration

### UTType: `com.semanticvideo.svp`

| Property | Value |
|----------|-------|
| Identifier | `com.semanticvideo.svp` |
| Description | Semantic Video Package |
| Conforms To | `public.movie`, `public.audiovisual-content`, `public.zip-archive` |
| Extension | `.svp` |
| MIME Type | `application/vnd.svp+zip` |

Declared in:
- Host app `Info.plist` (`UTExportedTypeDeclarations`)
- MediaExtension `Info.plist` (`UTExportedTypeDeclarations`)

**Result:** ✅ PASS

---

## 8. Acceptance Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| Quick Look preview of embedded video | ✅ PASS | Code complete, compiles. Runtime test requires installation + code signing. |
| QuickTime direct open | ⚠️ BLOCKED | MediaExtension compiles. Runtime blocked by: (1) entitlement provisioning for `com.apple.developer.mediaextension.formatreader`, (2) `SVPSampleCursor` stub needs full `AVAssetReader` implementation for sample buffer delivery. |
| No standalone player app | ✅ PASS | Host app is carrier only, no playback UI. |
| No manual extraction | ✅ PASS | Media extracted to temp automatically. |
| `.pkg` installer | ✅ PASS | `build-pkg.sh` produces `SVPSystemSupport.pkg`. |
| UTType registration | ✅ PASS | `com.semanticvideo.svp` declared in Info.plist. |
| Pure Swift ZIP reader | ✅ PASS | No libzip; uses `FileHandle` + CZlib. |
| SVP format not redesigned | ✅ PASS | Reads existing format as-is. |

---

## 9. Build & Install Instructions

### Build

```bash
# Build SVPReader package
cd SVPReader && swift build

# Run SVPReader tests
swift test

# Build Xcode project
xcodebuild -project svp-system-support.xcodeproj -scheme svp-system-support -configuration Debug build

# Build PKG installer (Release config)
./build-pkg.sh
```

### Install

```bash
sudo installer -pkg build/SVPSystemSupport.pkg -target /
```

After installation, log out and log back in to activate Quick Look and MediaExtension.

### Verify UTType Registration

```bash
mdls -name kMDItemContentType /path/to/file.svp
# Expected: com.semanticvideo.svp
```

---

## 10. Debugging & Logging

All components use `os.Logger` with subsystem `com.cueit.svp-system-support`:

| Component | Category |
|-----------|----------|
| SVPReader | `SVPReader` |
| Quick Look | `QuickLook` |
| MediaExtension | `MediaExtension` |

View logs:

```bash
log stream --predicate 'subsystem == "com.cueit.svp-system-support"' --level debug
```

---

## 11. Test SVP File

Sample SVP file used for testing:

```
/Users/domesposito/Projects/svp/build/local-code-svp/CODE.svp
```

- **Package ID:** `svp_CODE_pkg`
- **SVP Version:** `1.0-rc.2`
- **Primary Media:** `media/original/source_000.MOV` (139,314,379 bytes, deflate compressed)
- **MIME Type:** `application/vnd.svp+zip`

To create a minimal valid SVP:

```bash
mkdir /tmp/test-svp
echo "application/vnd.svp+zip" > /tmp/test-svp/mimetype
echo '{"primary_media_id":"media_000001","svp_version":"1.0-rc.2","package_id":"test"}' > /tmp/test-svp/manifest.json
mkdir -p /tmp/test-svp/media/original
cp /path/to/video.mov /tmp/test-svp/media/original/source_000.MOV
cd /tmp/test-svp && zip -r /tmp/test.svp mimetype manifest.json media/
```

---

## 12. Blockers & Next Steps

### QuickTime Direct Open — BLOCKED

**Blocker 1: Entitlement Provisioning**
The `com.apple.developer.mediaextension.formatreader` entitlement requires Apple Developer provisioning. The entitlement is declared in `svp-media-reader.entitlements` but needs a valid provisioning profile with the MediaExtension capability enabled.

**Blocker 2: Sample Buffer Delivery**
`SVPSampleCursor.loadSampleBufferContainingSamples(to:completionHandler:)` currently returns `MEError.noSamples`. To fully support QuickTime playback, this must be implemented using `AVAssetReader` to extract `CMSampleBuffer` objects from the materialized media file and deliver them to the MediaExtension runtime.

**Next Steps:**
1. Obtain Apple Developer provisioning with MediaExtension format reader capability.
2. Implement `AVAssetReader`-based sample buffer extraction in `SVPSampleCursor`.
3. Test with QuickTime Player opening a `.svp` file directly.
