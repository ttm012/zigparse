# Architecture

## Overview

zigparse is a single-purpose CLI tool: read a file, detect its format, extract text. It does one thing and does it without external dependencies.

```
stdin/file → main.zig → dispatch → [pdf.zig | table.zig | text.zig | detect.zig] → stdout
```

## Modules

### `main.zig` — CLI entry point
Handles argument parsing, file I/O, and dispatches to the correct module via a Zig `enum`-based command parser. Uses an arena allocator — all memory is freed at once on exit.

Key decisions:
- `std.fs.cwd().openFile()` — supports both absolute and relative paths
- stdin mode check — exits cleanly instead of hanging when no data is piped
- `switch` dispatch — single lookup, no redundant checks

### `pdf.zig` — PDF text extraction
Extracts text from PDF streams using three methods, tried in order:

1. **BT/ET literal strings** — scans for `BT`...`ET` blocks and extracts `(text) Tj` patterns with full escape sequence handling (`\n`, `\r`, octal `\123`, etc.)
2. **BT/ET hex strings** — extracts `<48656c6c6f> Tj` patterns and decodes hex to ASCII
3. **Raw ASCII fallback** — if no BT/ET blocks found, scans streams for printable ASCII sequences with a 30-byte binary threshold

The algorithm is a single O(n) pass through the file. It uses `std.mem.eql` on a sliding 6-byte window to find `stream` keywords — no repeated `indexOf` calls.

Limitations: no image OCR, no complex layout reconstruction, no font decoding, no FlateDecode decompression. Works for the common case of searchable, uncompressed PDFs.

### `table.zig` — CSV/TSV parser
Single-pass table parser with:
- Quoted field support (`"value with, comma"`)
- Escaped quotes (`""` → `"`)
- Multi-line cells (newlines inside quoted fields)
- UTF-8 BOM handling
- Header row highlighting (bold cyan via ANSI codes)
- Row count summary

The parser is a simple state machine with two states: inside quotes / outside quotes. It processes one byte at a time with no lookahead beyond the immediate next byte (for `""` detection).

### `text.zig` — Binary-to-text extractor
Single-pass stripper: replaces non-printable bytes with spaces, collapses consecutive spaces/newlines, preserves tab/newline structure. Used as a fallback for unknown file types.

### `detect.zig` — Format auto-detection
Uses a three-tier detection strategy:

1. **Magic bytes** — `%PDF` for PDF, `PK\x03\x04` for ZIP-based Office files
2. **File extension** — xlsx, docx, pptx (via `std.fs.path.extension`)
3. **Content heuristics** — commas → CSV, tabs → TSV, `{`/`[` → JSON

The heuristic scan is limited to the first 512 bytes — no need to scan the entire file just to guess the format.

## Memory Model

Arena allocator throughout. The entire file is read into memory (max 50MB), parsed in-place, and everything is freed on exit. No per-object allocation, no GC, no leak tracking.

For a 10MB CSV, peak memory is ~12MB (file + cell buffers). The text extractor uses a single pass with a single output buffer — no intermediate allocations.

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| PDF stream scan | O(n) | Single pass, sliding window |
| CSV parse | O(n) | Single pass, byte-at-a-time |
| text.extract | O(n) | Single pass, in-place collapse |
| detect | O(1) | Magic bytes + 512-byte scan |

## Design Tradeoffs

| Decision | Why | Tradeoff |
|----------|-----|----------|
| Arena allocation | Simplicity, speed | Can't free individual objects |
| Linear scan | No AST, no DOM | Incomplete for complex PDFs |
| No dependencies | Portability | Reimplements what libraries do |
| stdout only | Unix philosophy | No interactive mode |
| 50MB file limit | Reasonable for CLI | Won't handle multi-GB files |
| Single-pass text | Fewer allocations | Less control over output format |
