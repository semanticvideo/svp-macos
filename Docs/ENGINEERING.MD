# SVP System Support — Engineering Document

This document explains the engineering decisions behind SVP System Support — why things are built the way they are, what's in the stack, and the trade-offs that shaped the architecture.

---

## Project Identity

SVP System Support is a macOS support app for Semantic Video Package (`.svp`) files. An SVP file is a ZIP archive containing video media, transcript data, OCR/text analysis, color analysis, timeline metadata, entity recognition, provenance info, and a search index. The app does not create or edit SVP files — it provides system-level support so macOS can preview, play, inspect, and extract from them.

The app ships as a `.pkg` installer containing three bundles:

- **SVPSystemSupport.app** — Agent-style host app with Finder Services
- **SVPPreview.appex** — Quick Look preview extension
- **SVPMediaReader.appex** — MediaExtension format reader

---

## Stack Overview

| Layer | Technology |
| --- | --- |
| Language | Swift 5.9+ (with one Objective-C file for MediaExtension sample cursor) |
| UI Framework | AppKit + SwiftUI (hybrid in the Inspector) |
| Media | AVFoundation, AVKit, MediaExtension, CoreMedia |
| Quick Look | Quartz framework (`QLPreviewingController`, `QLPreviewPanel`) |
| ZIP Parsing | Custom Swift implementation (no libzip) |
| Compression | System zlib via a small C shim (`CZlib`) |
| Logging | `os.Logger` (unified logging) + file-based logging to app group container |
| Packaging | `xcodebuild` + `pkgbuild`/`productbuild` via `BUILD-PKG.SH` |
| Minimum OS | macOS 14 for SVPReader package, macOS 15.6 for MediaExtension target |

---

## Architectural Decisions

### 1. Agent App, Not a Document Editor

The host app has `LSUIElement = true`, meaning it has no dock icon and no main menu bar. It exists primarily as a container for system integrations — Finder Services, file type registration, and as the parent bundle for the two app extensions. When a user right-clicks an `.svp` file in Finder and selects a service, the app launches, handles the request, and stays alive only as long as windows are open.

**Why:** SVP files are not meant to be "edited" in a traditional document app. The app's job is to provide quick actions (extract video, show transcript, inspect contents) and system-level type registration. An agent app is the right fit — it's lightweight, doesn't clutter the dock, and can be invoked on-demand by Finder.

### 2. Non-Modal Window Presentation

Both the Inspector and Transcript windows are presented non-modally using `showWindow(nil)` and `makeKeyAndOrderFront(nil)`. The app delegate retains references to `SVPInspectorWindowController` instances in an array, and `SVPTranscriptWindowPresenter` retains its own window array. Cleanup happens via `windowWillClose` callbacks.

**Why:** Previously, both windows used `NSApp.runModal(for:)`, which blocked the event loop and prevented opening a second window while one was already open. Switching to non-modal presentation lets users have Inspector and Transcript open at the same time, or multiple Inspectors for different files. The app remains alive as long as any window is retained.

### 3. Custom ZIP Parser Instead of libzip

`ZipReader` in the SVPReader package parses ZIP central directory entries directly from file bytes. It reads the End of Central Directory record, walks central directory entries, parses local file headers, and supports both stored (method 0) and deflated (method 8) entries. Deflate decompression goes through `CZlib`, a minimal C shim around system zlib's `inflate` API.

**Why:** Adding libzip as a dependency would mean pulling in a C library with its own build system, potential security surface, and version management. The ZIP format is well-understood and the subset needed here (central directory parsing + stored/deflated entries) is straightforward. The custom parser is ~480 lines of Swift and gives full control over memory and I/O patterns. The `CZlib` shim is ~50 lines of C and links against the system-provided zlib, so there's no third-party code to audit or maintain.

### 4. Dual FileHandle with pread for Byte-Range Reads

`ZipReader` opens two `FileHandle` objects on the same file. The primary handle is used for sequential reads (entry data, local headers). The secondary handle is used exclusively for `pread`-based random access reads on stored entries. A `NSLock`-protected cache stores the data offset and size of stored entries so repeated range reads don't need to re-parse local headers.

**Why:** Quick Look's `AVAssetResourceLoaderDelegate` and MediaExtension's `MESampleCursor` both need random-access byte reads from the media data inside the ZIP. Using `pread` on a separate file handle avoids seeking conflicts with the primary sequential read path. This is critical for video playback where AVFoundation requests many small byte ranges in rapid succession.

### 5. Quick Look: Byte-Range Playback Without Materialization

The Quick Look extension (`SVPPreview`) does not extract the media file to disk. Instead, it uses a custom `AVAssetResourceLoaderDelegate` (`SVPMediaResourceLoader`) that serves byte-range read requests directly from the stored ZIP entry via `SVPReader.readMediaDataRange`. The media URL uses a custom scheme (`svp-preview-media://primary/filename.mp4`) so AVFoundation routes all resource loading through the delegate.

**Why:** Materializing a large video file to a temp directory takes time and disk space. For Quick Look, where the user just wants to peek at the video, byte-range serving from the ZIP is faster and uses no extra disk. The trade-off is that this only works for stored (uncompressed) entries — compressed media would need decompression per range, which isn't practical for random access. The code explicitly checks `!mediaInfo.isCompressed` and throws an error for compressed media.

### 6. MediaExtension: Init Segment + Sample Table Parsing

The MediaExtension format reader (`SVPMediaReader`) takes a different approach than Quick Look. It writes the full SVP ByteSource to a temp file, then extracts just the `ftyp` and `moov` boxes into a standalone init segment using `SVPMP4InitializationSegmentWriter`. It then parses the `moov` box with `SVPMP4SampleTableParser` to build a complete sample table (offsets, sizes, PTS, DTS, durations, sync flags). The sample cursor returns `MESampleLocation` objects that point back into the original `MEByteSource` with adjusted offsets (media data offset + sample offset within the media).

**Why:** MediaExtension requires a proper `MEFormatReader` with track readers and sample cursors. AVFoundation needs an init segment (`ftyp` + `moov`) to create an `AVURLAsset`, but the actual sample data can be served from the original byte source. By parsing the sample table ourselves, we can map each sample's file offset (relative to the extracted media) to its absolute offset within the SVP ZIP file. This lets the system read samples directly from the ZIP without materializing the full media file.

The init segment is small (typically a few hundred KB for `moov`), so the materialization cost is minimal. The full SVP file is written to temp only because `MEByteSource` provides bytes asynchronously through a callback API, and `SVPReader` needs random file access — the temp file bridges that gap.

### 7. Interprocess Materialization Lock

`SVPFormatReader` uses a `flock`-based lock on a temp file (`svp-media-reader-materialize.lock`) to ensure only one MediaExtension process materializes media at a time.

**Why:** macOS may spawn multiple MediaExtension processes for different playback sessions. Without coordination, two processes could simultaneously write temp files and parse the same SVP, wasting CPU and disk I/O. The lock is non-blocking (`LOCK_NB`) — if another process is already materializing, the second one fails fast rather than waiting.

### 8. Objective-C for Sample Cursor

`SVPSampleCursorObjC` is implemented in Objective-C despite the rest of the MediaExtension target being Swift.

**Why:** The `MESampleCursor` protocol has properties and methods that are tricky to implement correctly in Swift, particularly around `CMTime` as a property (Swift property wrappers don't map cleanly to ObjC protocol requirements) and `copyWithZone:` conformance. Objective-C provides direct control over memory management, `CMTime` as a struct property, and `NSCopying` behavior without Swift's bridging complexity. The `svpObjCTry` helper also catches ObjC exceptions that MediaExtension might throw, which Swift can't catch natively.

### 9. Disabled Audio Track Filtering

`SVPFormatReader.loadTrackReaders` filters out disabled audio tracks before creating track readers. It loads `isEnabled` for each track and excludes tracks where it returns `false`. There's a fallback: if all tracks of a type are disabled, it includes all of them anyway.

**Why:** Some video files (particularly iPhone captures) contain secondary spatial/ambisonic audio tracks that are marked as disabled. If both the primary and disabled audio tracks are played simultaneously, the result is phase doubling — an audio artifact where the same sound plays twice slightly out of phase. Filtering disabled tracks prevents this. The fallback handles edge-case files where the enabled flag is incorrectly set on all tracks.

### 10. Hybrid AppKit + SwiftUI Inspector

The Inspector uses `NSSplitViewController` as the container, with SwiftUI views hosted inside via `NSHostingController`. The sidebar is a SwiftUI `List`, and each detail pane is a SwiftUI view. The window controller and toolbar are AppKit. Quick Look panel integration uses the `QLPreviewPanelController` informal protocol on the AppKit window controller.

**Why:** SwiftUI's `Table` view and `List` with selection binding are well-suited for the Inspector's sortable tables and sidebar navigation. But Quick Look panel integration (`QLPreviewPanel`) requires responder chain participation and `acceptsPreviewPanelControl` — this is much easier in AppKit where you have direct control over the responder chain. The hybrid approach gets the best of both: SwiftUI for layout and tables, AppKit for window management and Quick Look.

### 11. App Group Container for Logging

`SVPAppLogger` writes log lines to `svp_extract.log` inside the shared app group container (`group.com.cueit.svp-system-support`). The MediaExtension target uses `os.Logger` with the same subsystem. Quick Look uses `fputs` to `stderr`.

**Why:** The app group container is the only shared writable location between the host app and its extensions (Quick Look runs in a separate process, MediaExtension in another). Writing to the app group container lets the host app's logs be inspected from one place. MediaExtension uses `os.Logger` because it's the recommended approach for system extensions and integrates with Console.app. Quick Look extensions have more restricted sandboxing, so `stderr` is the most reliable output channel.

### 12. Post-Install Launch Services Registration

The `SCRIPTS/POSTINSTALL` script runs `lsregister` for the app and both extensions after the `.pkg` installs. It registers the app at `/Applications/SVPSystemSupport.app` and each `.appex` inside the `PlugIns` directory.

**Why:** macOS can be slow to pick up new UTType declarations and service registrations, especially for agent apps that don't have a normal launch cycle. Explicit `lsregister` calls force the system to recognize the new file type, services, and extensions immediately. Users may still need to log out and back in for Finder and Quick Look to fully update, but the registration step removes most of the friction.

---

## SVP File Format

An SVP file is a ZIP archive with the following structure:

```
mimetype                          — "application/vnd.svp+zip" (stored, first entry)
manifest.json                     — Package metadata (svp_version, package_id, created_utc, primary_media_id, timebase)
media/original/<filename>         — Primary video file (stored, not compressed)
transcript/words.jsonl            — One JSON object per word with "text" field
transcript/transcript.json        — Transcript summary
transcript/speakers.jsonl         — Speaker identities
transcript/speaker_segments.jsonl — Speaker turn segments
text/text_regions.jsonl           — OCR text regions
text/text_observations.jsonl      — Text observation details
text/numeric_values.jsonl         — Extracted numeric values
text/text_absence.json            — Text absence declaration
text/evidence_crops.jsonl         — Evidence crop metadata (with crop_file_path)
text/<crop files>                 — Evidence crop image data
colors/color_observations.jsonl   — Color observations
colors/color_summary.json         — Color summary
colors/color_absence.json         — Color absence declaration
timeline/shots.jsonl              — Shot boundaries
timeline/scenes.jsonl             — Scene boundaries
timeline/frames.jsonl             — Frame-level metadata
entities/entities.jsonl           — Named entities
entities/entity_tracks.jsonl      — Entity tracking across frames
relationships/relationships.jsonl — Entity relationships
provenance/build.json             — Build provenance
provenance/processors.jsonl       — Processing pipeline history
provenance/validation.json        — Validation report
index/index.sqlite                — Search index database
index/index_manifest.json         — Index metadata
```

The `mimetype` entry must be the first entry in the ZIP and must be stored (not compressed). This follows the EPUB convention and allows quick identification without decompression. The `manifest.json` must also be present. Primary media lives under `media/original/` and must be stored (not compressed) for byte-range access.

---

## What's Working

- **File type registration:** `.svp` files appear with the correct icon and type in Finder.
- **Quick Look:** Spacebar preview shows video playback with controls, auto-play in popup, pause when hidden.
- **MediaExtension:** System-level media access so QuickTime and other AVFoundation-based apps can open `.svp` files directly.
- **Finder Services:** Three right-click actions — Extract Video from SVP, Show SVP Transcript, SVP Inspector. All non-modal, can coexist.
- **SVP Inspector:** Full package browser with 9 sections, sortable tables, evidence crop gallery with Quick Look, all read-only from the ZIP.
- **Video Extraction:** Save panel to extract the embedded video to a user-chosen location.
- **Transcript Viewer:** Scrollable window showing joined transcript text.
- **Logging:** Both file-based (app group) and unified logging (`os.Logger`) for debugging.
- **Packaging:** `BUILD-PKG.SH` produces a signed `.pkg` installer with post-install Launch Services registration.

---

## Known Constraints

- **Compressed media not supported for playback:** Both Quick Look and MediaExtension require stored (uncompressed) media entries. Compressed media will throw `unsupportedCodec`. This is a fundamental limitation — random access into deflated data isn't practical.
- **MediaExtension requires macOS 15.6+:** The `LSMinimumSystemVersion` in the MediaExtension Info.plist is set to 15.6. The SVPReader package itself supports macOS 14+.
- **Quick Look auto-play depends on window level:** The extension checks `window.level.rawValue > 0` to determine if it's in a popup (auto-play) vs full preview (no auto-play). This is a heuristic based on Quick Look's window behavior.
- **Inspector reads everything at once:** `SVPInspectorData.load` reads all package entries synchronously when the Inspector opens. For very large packages this could be slow, but in practice SVP files are small enough that this is not a problem.
- **Evidence crops written to temp for Quick Look:** `EvidenceCropQuickLookController` writes crop images to `~/tmp/svp-evidence-crops/` because `QLPreviewPanel` needs file URLs. These temp files are not explicitly cleaned up (the OS handles temp directory cleanup).

---

## Build & Deploy

The project builds via `xcodebuild` using the `SVPSystemSupport` scheme. `BUILD-PKG.SH` automates the full release build:

1. Runs `xcodebuild build` with Release configuration.
2. Stages the built app into `build/pkg/Applications/`.
3. Runs `pkgbuild` to create component packages.
4. Runs `productbuild` to create the final `build/SVPSystemSupport.pkg` with the post-install script.

The post-install script registers all three bundles with Launch Services using `lsregister -f -r`, ensuring the UTType, services, and extensions are recognized immediately after installation.

---

## Entitlements Summary

| Target | Key Entitlements |
| --- | --- |
| SVPSystemSupport.app | `mediaextension.formatreader`, app group, user-selected read-write |
| SVPPreview.appex | App group only |
| SVPMediaReader.appex | `mediaextension.formatreader`, app sandbox, app group, user-selected read-only |

The app group (`group.com.cueit.svp-system-support`) is shared across all three targets, enabling the file-based logging path to work from any process.
