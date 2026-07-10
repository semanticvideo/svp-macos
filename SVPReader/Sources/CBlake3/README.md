Official BLAKE3 C implementation, pinned to upstream release 1.8.2.

Source: https://github.com/BLAKE3-team/BLAKE3/tree/1.8.2/c
License: CC0-1.0 or Apache-2.0 (see LICENSE_CC0 and LICENSE_A2).

Only the portable implementation is compiled; SIMD backends are disabled by
SwiftPM C defines. SVPReader uses this target only to verify Embedded SVPI
Transport payloads.
