# SVP System Support — Code Map

A file-by-file map of the repository, grouped by target/module.

---

## Repository Root

| Path | Description |
| --- | --- |
| `README.MD` | Project overview, build/install instructions, troubleshooting. |
| `BUILD-PKG.SH` | Release packaging script. Builds Release config, stages app under `build/pkg/Applications`, produces `build/SVPSystemSupport.pkg`. |
| `SCRIPTS/POSTINSTALL` | PKG post-install script. Registers app and both extensions with Launch Services via `lsregister`. |
| `SVPSYSTEMSUPPORT.XCODEPROJ/` | Xcode project containing all targets. |
| `.GITIGNORE` | Standard Swift/macOS gitignore. |

---

## SVPReader (Swift Package)

Local Swift package at `SVPReader/`. Declared in `PACKAGE.SWIFT` with `swift-tools-version: 5.9`, platform `macOS 14+`. No external dependencies.

### `SVPReader/Package.swift`

Defines two targets (`CZlib`, `SVPReader`) and one test target (`SVPReaderTests`). `SVPReader` depends on `CZlib`. `CZlib` links against system `zlib`.

### `SVPReader/Sources/CZlib/`

| File | Responsibility |
| --- | --- |
| `CZLIB.C` | C shim around system zlib `inflate` API. Exposes `cZlib_inflate_init`, `cZlib_inflate_process`, `cZlib_inflate_end`. Uses raw deflate mode (`inflateInit2` with window bits `-15`). |
| `INCLUDE/CZLIB.H` | Header declaring the three C functions and the opaque `cZlib_stream` type. |

### `SVPReader/Sources/SVPReader/`

| File | Responsibility |
| --- | --- |
| `SVPREADER.SWIFT` | Public `SVPReader` class — the main API surface. Opens a ZIP-based SVP file via `ZipReader`, validates mimetype + manifest, reads manifest metadata, locates primary media, reads transcript text, materializes media to temp directories, and provides generic entry-reading methods for the Inspector. Also defines `SVPLog` (os.Logger wrapper). |
| `ZIPREADER.SWIFT` | Internal `ZipReader` class. Parses ZIP central directory from raw file bytes (no libzip dependency). Supports stored (method 0) and deflated (method 8) entries. Provides entry listing, full reads, extraction to file, byte-range reads via `pread` for stored entries, and streaming inflate. Maintains a second `FileHandle` for concurrent range reads with an `NSLock`-protected cache. |
| `SVPERROR.SWIFT` | Public error enum (`SVPError`) with cases for every failure mode. Also defines public value types: `SVPMediaInfo` (media entry metadata), `SVPManifestInfo` (manifest fields), `SVPReadResult` (materialized media result). All `Sendable`. |

### `SVPReader/Tests/SVPReaderTests/`

Contains package tests. Tests reference a local SVP fixture at a hardcoded path (see README for details).

---

## SVPSystemSupport (Host App)

Main app target at `SVPSystemSupport/`. Agent-style AppKit app with `LSUIElement = true` (no dock icon, no main menu bar). Bundle ID: `com.cueit.svp-system-support`.

### `SVPSystemSupport/Info.plist`

Registers:
- `LSUIElement = true` (agent app).
- Three `NSServices` for Finder right-click actions: `extractVideoService`, `showTranscriptService`, `inspectSVPService`. All scoped to Finder and `.svp` file type.
- `CFBundleDocumentTypes` for `.svp` with role `None` (type registration only, not an editor).
- `UTExportedTypeDeclarations` for `com.semanticvideo.svp` conforming to `com.apple.mediaextension-content`, `public.movie`, `public.audiovisual-content`.

### `SVPSystemSupport/SVPSystemSupport.entitlements`

- `com.apple.developer.mediaextension.formatreader` (true)
- App group `group.com.cueit.svp-system-support`
- User-selected read-write file access

### App Entry & Delegate

| File | Responsibility |
| --- | --- |
| `SVPSYSTEMSUPPORTMAIN.SWIFT` | `@main` struct. Creates `NSApplication`, sets `SVPSystemSupportApp` as delegate and `servicesProvider`, calls `application.run()`. |
| `SVPSYSTEMSUPPORTAPP.SWIFT` | `NSApplicationDelegate` and `servicesProvider` target. Implements all three Finder service methods (`extractVideoService`, `showTranscriptService`, `inspectSVPService`), `application(_:open:)` URL handling, and `applicationShouldHandleReopen`. Retains `SVPInspectorWindowController` instances in an array. Windows are non-modal — both Inspector and Transcript can be open simultaneously. |

### Support Files

| File | Responsibility |
| --- | --- |
| `SVPAPPLOGGER.SWIFT` | `SVPAppLogger` enum. Writes log lines to `svp_extract.log` inside the shared app group container (`group.com.cueit.svp-system-support`). |
| `SVPPASTEBOARDREADER.SWIFT` | `SVPPasteboardReader` enum. Extracts the first `.svp` file URL from an `NSPasteboard` using UTType conformance filtering. |
| `SVPVIDEOEXTRACTOR.SWIFT` | `SVPVideoExtractor` class. Validates SVP, locates primary media, presents `NSSavePanel`, writes extracted media to chosen destination, reveals in Finder. Returns outcome enum (`.extracted`, `.cancelled`, `.failed`). |
| `SVPTRANSCRIPTLOADER.SWIFT` | `SVPTranscriptLoader` class. Wraps `SVPReader.readTranscriptText()` — validates SVP and reads `transcript/words.jsonl`, joining word `text` fields into a single string. |
| `SVPTRANSCRIPTWINDOWPRESENTER.SWIFT` | `SVPTranscriptWindowPresenter` class (`NSWindowDelegate`). Creates and manages non-modal transcript windows with a scrollable text view, title label, and Done button. Retains open windows in an array; removes on close. Uses `NSGlassEffectView` on macOS 26+ or `NSVisualEffectView` on older systems. |

### Inspector (`SVPSystemSupport/Inspector/`)

| File | Responsibility |
| --- | --- |
| `SVPINSPECTORDATA.SWIFT` | `SVPInspectorData` struct. Loads all package contents from an SVP file via `SVPReader`'s generic entry methods. Reads transcript words/summary/speakers/segments, text regions/observations/numeric values/absence, evidence crops + crop images, color observations/summary/absence, shots/scenes/frames, entities/entity tracks, relationships, provenance build/processors/validation, and index manifest. Returns `loadError` string on failure. |
| `SVPINSPECTORSECTIONS.SWIFT` | `SVPInspectorSection` enum (9 cases: overview, transcript, ocr, evidenceCrops, colors, scenes, entities, provenance, index). `SVPInspectorSidebarView` (SwiftUI `List` with SF Symbol icons). `SVPInspectorSplitViewController` (NSSplitViewController with sidebar + detail pane, swaps detail views on selection). `EmptyStateView` and `SVPInspectorErrorView`. |
| `SVPINSPECTORDETAILVIEWS.SWIFT` | All SwiftUI detail views: `OverviewDetailView`, `TranscriptDetailView`, `OCRDetailView`, `ColorsDetailView`, `ScenesDetailView`, `EntitiesDetailView`, `ProvenanceDetailView`, `IndexDetailView`. Each renders section-specific data in sortable tables or formatted layouts. |
| `SVPINSPECTORFORMATTING.SWIFT` | Formatting helpers: `displayString`, `formatValue`, `formatMicroseconds`, `prettyJSON`. `SortValue` (Comparable wrapper for mixed-type sorting). `InspectorRow` (dynamicMemberLookup row wrapper for `[String: Any]` dicts). `makeRows` and `sortedRows` helpers. |
| `SVPEVIDENCECROPS.SWIFT` | `EvidenceCropsDetailView` (SwiftUI grid of crop thumbnails). `EvidenceCropCell` (image + labels, tap to open Quick Look). `EvidenceCropQuickLookController` (QLPreviewPanelDataSource — writes crop images to temp files and serves them to Quick Look). |
| `SVPINSPECTORWINDOWPRESENTER.SWIFT` | `SVPInspectorWindowController` (NSWindowController with split view, toolbar, Quick Look panel support). `SVPInspectorToolbarProvider` (custom NSToolbar with sidebar toggle button and filename label). Window is non-modal, presented via `showWindow`. `onClose` callback for cleanup. Implements `QLPreviewPanelController` informal protocol. |

### Assets

| Path | Description |
| --- | --- |
| `ASSETS.XCASSETS/` | App icon and accent color. |
| `SVPSUPPORT.ICON/` | Custom app icon assets. |

---

## SVPPreview (Quick Look Extension)

Quick Look preview extension at `SVPPreview/`. Bundle product: `SVPPreview.appex`. Extension point: `com.apple.quicklook.preview`.

### `SVPPreview/Info.plist`

Declares `NSExtensionPrincipalClass` as `$(PRODUCT_MODULE_NAME).PreviewProvider`. Supports content type `com.semanticvideo.svp`. Searchable items disabled.

### `SVPPreview/SVPPreview.entitlements`

App group `group.com.cueit.svp-system-support` only.

| File | Responsibility |
| --- | --- |
| `PREVIEWPROVIDER.SWIFT` | `PreviewProvider` (NSViewController, QLPreviewingController). Prepares preview by validating SVP, locating primary media, setting up a custom `AVAssetResourceLoaderDelegate` for byte-range playback without materializing to disk. Uses `AVPlayerView` for video playback. Auto-plays in Quick Look popup, pauses when hidden. Adjusts controls style (floating vs inline) based on window level. Includes extensive playback diagnostics logging. `SVPPreviewContainerView` maintains aspect ratio. |
| `SVPMEDIARESOURCELOADER.SWIFT` | `SVPMediaResourceLoader` (AVAssetResourceLoaderDelegate). Serves byte-range read requests from the SVP ZIP entry using `SVPReader.readMediaDataRange`. Uses two `OperationQueue`s: a 4-concurrent queue for range requests and a 1-concurrent queue for open-ended (stream-to-end) requests. Tracks cancelled requests with a lock-protected set. Logs slow reads and progress. |

---

## SVPMediaReader (MediaExtension Format Reader)

MediaExtension format reader extension at `SVPMediaReader/`. Bundle product: `SVPMediaReader.appex`. Extension point: `com.apple.mediaextension.formatreader`.

### `SVPMediaReader/Info.plist`

Declares `EXPrincipalClass` as `SVPFormatReaderExtension`. Supports `com.semanticvideo.svp`. Also exports the UTType (with `public.zip-archive` conformance). `LSMinimumSystemVersion = 15.6`.

### `SVPMediaReader/SVPMediaReader.entitlements`

- `com.apple.developer.mediaextension.formatreader` (true)
- App sandbox enabled
- App group `group.com.cueit.svp-system-support`
- User-selected read-only file access

### `SVPMediaReader/SVPMediaReader-Bridging-Header.h`

Bridges `SVPSampleCursorObjC.h` for use from Swift.

| File | Responsibility |
| --- | --- |
| `SVPFORMATREADEREXTENSION.SWIFT` | `SVPFormatReaderExtension` (MEFormatReaderExtension). Entry point for MediaExtension. Creates `SVPFormatReader` from `MEByteSource`. |
| `SVPFORMATREADER.SWIFT` | `SVPFormatReader` (MEFormatReader). Lazily materializes media: writes ByteSource to temp SVP file, validates, extracts `ftyp`+`moov` boxes into an init segment via `SVPMP4InitializationSegmentWriter`, parses sample tables, creates `AVURLAsset`. Uses `InterprocessMaterializationLock` (flock-based) to prevent concurrent materialization. Filters disabled audio tracks to prevent phase doubling. Implements `loadFileInfo`, `loadMetadata`, `loadTrackReaders`. Cleans up temp dir in `deinit`. |
| `SVPTRACKREADER.SWIFT` | `SVPTrackReader` (METrackReader). Wraps an `AVAssetTrack` and its pre-parsed sample records. Loads track properties (format descriptions, natural size, transform, frame rate, timescale). Creates `SVPSampleCursorObjC` cursors for seek/step operations. |
| `SVPSAMPLECURSOROBJC.H` | Objective-C header. Declares `SVPSampleRecord` (offset, size, pts, dts, duration, sync) and `SVPSampleCursorObjC` (MESampleCursor). Also declares `svpObjCTry` helper for catching ObjC exceptions. |
| `SVPSAMPLECURSOROBJC.M` | Objective-C implementation of `SVPSampleCursorObjC`. Maintains a sample index into the pre-parsed sample array. Implements seek, step in decode/presentation order, step by time, `sampleLocationReturningError` (returns `MESampleLocation` with byte range into the original `MEByteSource`), `copyWithZone`. Frame reordering flags set to YES. `loadSampleBufferContainingSamples` returns `MEErrorLocationNotAvailable` (data served via sample location, not sample buffers). |
| `SVPMP4INITIALIZATIONSEGMENTWRITER.SWIFT` | Extracts `ftyp` and `moov` boxes from a media file into a standalone init segment. Reads top-level MP4 box headers (handles 32-bit, 64-bit extended, and zero-terminator sizes). Copies boxes byte-by-byte to output. |
| `SVPMP4SAMPLETABLE.SWIFT` | `SVPMP4SampleTableParser`. Parses the `moov` box from an MP4 init segment to extract sample tables. Reads `stts` (durations), `ctts` (composition offsets), `stss` (sync samples), `stsz` (sample sizes), `stco`/`co64` (chunk offsets), `stsc` (sample-to-chunk mapping), `mdhd` (timescale), `hdlr` (media type). Builds `SVPMP4Sample` records with offset, size, DTS, PTS, duration, and sync flag. |

---

## Test Targets

| Path | Description |
| --- | --- |
| `SVPSYSTEMSUPPORTTESTS/` | App test target. Contains `SVPSYSTEMSUPPORTTESTS.SWIFT` and `RESOURCES/SVP-TEST.SVP` fixture. |
| `SVPSYSTEMSUPPORTUITESTS/` | UI test target. Contains `SVPSYSTEMSUPPORTUITESTS.SWIFT` and `SVPSYSTEMSUPPORTUITESTSLAUNCHTESTS.SWIFT`. Default template tests. |

---

## Build Artifacts

| Path | Description |
| --- | --- |
| `BUILD/` | Output directory for `BUILD-PKG.SH`. Contains `DerivedData/`, `pkg/` staging, and `SVPSystemSupport.pkg`. |
