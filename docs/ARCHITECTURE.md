# Architecture

## Overview

docparse is a single-purpose CLI tool: read a file, detect its format, extract text. It does one thing and does it without external dependencies.

```
stdin/file → detect.zig → [pdf.zig | table.zig | text.zig] → stdout
```

## Modules

### `main.zig` (75 lines)
CLI entry point. Parses arguments, reads file into memory, dispatches to the correct module. Uses an arena allocator — all memory is freed at once on exit.

### `pdf.zig` (119 lines)
PDF text extraction via two methods:

1. **BT/ET extraction** — scans for `BT`...`ET` blocks and extracts `(text) Tj` patterns. This handles most text-based PDFs.
2. **Raw ASCII fallback** — if no BT/ET blocks found, scans streams for printable ASCII sequences with a 30-byte binary threshold.

Limitations: no image OCR, no complex layout reconstruction, no font decoding. Works for the common case of searchable PDFs.

### `table.zig` (72 lines)
CSV/TSV parser with:
- Quoted field support (`"value with, comma"`)
- Escaped quotes (`""` → `"`)
- Header row highlighting (bold cyan via ANSI codes)
- Row count summary

Single-pass linear scan. No buffering, no AST.

### `text.zig` (41 lines)
Binary-to-text extractor. Replaces non-printable bytes with spaces, collapses multiple spaces, preserves newlines and tabs.

### `detect.zig` (68 lines)
Format auto-detection using:
1. **Magic bytes** — `%PDF` for PDF, `PK\x03\x04` for ZIP-based Office files
2. **File extension** — xlsx, docx, pptx
3. **Content heuristics** — commas → CSV, tabs → TSV, `{`/`[` → JSON

## Memory Model

Arena allocator throughout. The entire file is read into memory (max 50MB), parsed in-place, and everything is freed on exit. No per-object allocation, no GC, no leak tracking.

For a 10MB CSV, peak memory is ~12MB (file + cell buffers).

## Design Tradeoffs

| Decision | Why | Tradeoff |
|----------|-----|----------|
| Arena allocation | Simplicity, speed | Can't free individual objects |
| Linear scan | No AST, no DOM | Incomplete for complex PDFs |
| No dependencies | Portability | Reimplements what libraries do |
| stdout only | Unix philosophy | No interactive mode |
| 50MB file limit | Reasonable for CLI | Won't handle multi-GB files |
