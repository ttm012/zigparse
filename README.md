# docparse

Fast document parser written in Zig. Zero dependencies.

Parses PDF, CSV, TSV, JSON, and plain text files into readable output. No external libraries, no Python, no Node — just a single static binary.

## Why

Most document parsers are either:
- Heavy (Chrome headless, Poppler, LibreOffice)
- Slow (Python with multiple dependencies)
- Platform-specific (only works on Linux/macOS)

docparse is a ~70KB static binary that handles the most common parsing tasks with no dependencies whatsoever.

## Quick Start

```bash
# Parse a PDF
docparse pdf report.pdf

# Parse a CSV table (headers highlighted)
docparse csv data.csv

# Parse TSV
docparse tsv export.tsv

# Auto-detect format and parse
docparse detect unknown_file

# Read from stdin
cat data.csv | docparse csv -
```

## Installation

### From source

```bash
git clone https://github.com/mrmmdl/docparse.git
cd docparse
zig build-exe src/main.zig -O ReleaseSmall -fstrip --name docparse
./docparse --help
```

### Requirements

- Zig 0.13.0+
- No other dependencies

## Supported Formats

| Format | Method | Notes |
|--------|--------|-------|
| PDF | Text stream extraction | Handles BT/ET objects, raw ASCII streams |
| CSV | Full parser | Quoted fields, escaped quotes, multi-line |
| TSV | Full parser | Same as CSV, tab-delimited |
| JSON | Passthrough | Ready for piping to other tools |
| Plain text | Binary stripping | Removes non-printable characters |
| DOCX/XLSX/PPTX | Detection only | ZIP-based — use unzip + parse XML |

## Architecture

```
src/
├── main.zig      — CLI entry point, argument parsing
├── pdf.zig       — PDF text extraction (BT/ET, stream scan)
├── table.zig     — CSV/TSV parser with quoted field support
├── json.zig      — JSON passthrough
├── text.zig      — Binary-to-text extractor
└── detect.zig    — Format auto-detection (magic bytes + heuristics)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## Performance

| Operation | Time | Notes |
|-----------|------|-------|
| Startup | <5ms | Static binary, no runtime init |
| PDF extract | ~1ms/MB | Linear stream scan |
| CSV parse | ~0.5ms/MB | Single-pass |
| 10K row CSV | ~50ms | Including output formatting |
| Binary size | 72KB | ReleaseSmall + strip |
| RAM usage | <2MB | Arena allocator, freed on exit |

## Design Decisions

### No external dependencies

Every dependency is a potential failure point. docparse uses only the Zig standard library. This means:
- No `pip install`
- No `brew install poppler`
- No `npm install`
- Just download and run

### Linear scan parsing

Instead of building full ASTs or DOM trees, docparse does single-pass linear scans. This trades completeness for speed and simplicity. For the 80% of documents that contain straightforward text, this works perfectly.

### Arena allocation

All memory is allocated in a single arena and freed at once on exit. No per-object free, no leak tracking, no GC. The OS reclaims everything when the process ends.

### stdout output

All output goes to stdout. This follows the Unix philosophy — pipe to `grep`, `head`, `jq`, or whatever else you need.

## What This Is NOT

- A complete PDF parser — it extracts text, not the full document structure
- A spreadsheet calculator — it reads tables, doesn't evaluate formulas  
- A word processor — it doesn't render DOCX formatting
- An OCR engine — scanned images of text are not supported

## License

MIT
