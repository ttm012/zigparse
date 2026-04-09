# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- Relative file paths now work correctly (`std.fs.cwd().openFile` instead of `openFileAbsolute`)
- CLI no longer hangs when stdin is a terminal (exits with helpful error)
- PDF parser uses O(n) single-pass algorithm instead of O(n²) repeated `indexOf` calls
- Hex string extraction (`<text> Tj`) added for PDFs that use hex-encoded text
- PDF escape sequence handling: `\n`, `\r`, `\t`, octal codes (`\123`)
- CSV parser handles UTF-8 BOM at start of files
- `eq()` helper removed — idiomatic `std.mem.eql` used directly

### Changed
- Command dispatch uses Zig `enum` + `switch` instead of `if` chain — no redundant checks
- `text.extract` is now single-pass (strip + collapse in one loop) — 2x fewer allocations
- `table.parse` accepts an `Allocator` parameter for consistency with other modules
- `detect.zig` uses `std.fs.path.extension` instead of manual string search
- Magic bytes extracted as named constants

### Added
- `build.zig` for native Zig build system (`zig build`, `zig build test`, `zig build run`)
- `CHANGELOG.md`

### Removed
- `Makefile` replaced by `build.zig` (kept as thin wrapper for convenience)
