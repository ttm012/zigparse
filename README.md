# docparse

> Fast document parser written in Zig. ~70KB static binary. Zero dependencies.

Extracts text from PDF, CSV, TSV, JSON, and plain text files — no external libraries, no Python, no Node, no Chrome. Just a single binary that runs anywhere.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange.svg)](https://ziglang.org)
[![No Dependencies](https://img.shields.io/badge/Dependencies-0-brightgreen.svg)]()

---

## The Problem

Need to quickly check what's inside a PDF? Extract a table from a CSV on a server without Python? Read text from a binary log file?

Existing solutions require installing heavy dependencies:

```bash
# Poppler + Python + bindings = ~200MB
pip install pdfplumber poppler-utils

# Or a full Chrome instance
npm install puppeteer
```

## The Solution

```bash
docparse pdf report.pdf
```

One binary. 72KB. Nothing else.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Commands](#commands)
  - [PDF Extraction](#pdf-extraction)
  - [CSV/TSV Parsing](#csvtsv-parsing)
  - [Text Extraction](#text-extraction)
  - [Auto-Detection](#auto-detection)
- [Pipes & Redirection](#pipes--redirection)
- [Building from Source](#building-from-source)
- [Architecture](#architecture)
- [Performance](#performance)
- [What This Is NOT](#what-this-is-not)
- [Changelog](#changelog)
- [License](#license)

---

## Quick Start

```bash
# Extract text from a PDF
docparse pdf annual_report.pdf

# Parse a CSV table (headers highlighted in cyan)
docparse csv sales_2024.csv

# Auto-detect format and parse
docparse detect mystery_file

# Pipe data directly
cat export.csv | docparse csv -
```

---

## Installation

### Option 1: Download a release (recommended)

Check the [Releases](https://github.com/ttm012/docparse/releases) page for pre-built binaries for your platform.

### Option 2: Build from source

Requires [Zig 0.13.0+](https://ziglang.org/download/):

```bash
git clone https://github.com/ttm012/docparse.git
cd docparse
zig build -Doptimize=ReleaseSmall
./zig-out/bin/docparse --help
```

### Option 3: Install globally

```bash
zig build -Doptimize=ReleaseSmall
sudo cp zig-out/bin/docparse /usr/local/bin/
```

---

## Commands

### `docparse pdf <file>`

Extracts readable text from PDF files.

**How it works:**
1. Scans PDF streams for `BT`...`ET` (Begin/End Text) blocks
2. Extracts literal strings: `(Hello World) Tj`
3. Extracts hex strings: `<48656c6c6f> Tj`
4. Falls back to raw ASCII if no text operators found

```bash
docparse pdf document.pdf
```

**Handles:**
- Literal strings with escape sequences (`\n`, `\r`, `\123` octal)
- Hex-encoded text
- Compressed streams with readable ASCII
- Multi-line text objects

**Doesn't handle:**
- Scanned images (need OCR — try Tesseract)
- FlateDecode-compressed binary streams
- Form fields and annotations

### `docparse csv <file>`

Parses comma-separated files and prints a formatted table with highlighted headers.

```bash
$ docparse csv employees.csv
name             │ department    │ salary   │
Alice Johnson    │ Engineering   │ 95000    │
Bob Smith        │ Marketing     │ 72000    │
Carol Williams   │ Engineering   │ 98000    │
  4 rows
```

**Handles:**
- Quoted fields: `"Smith, Jr",25,"New York"`
- Escaped quotes: `"He said ""hello"""`
- Multi-line cells (newlines inside quotes)
- UTF-8 BOM at the start of the file
- Windows (`\r\n`) and Unix (`\n`) line endings

### `docparse tsv <file>`

Same as CSV, but tab-delimited. Identical feature set.

```bash
docparse tsv export.tsv
```

### `docparse json <file>`

Outputs JSON content as-is. Useful as part of a pipeline:

```bash
docparse json config.json | jq '.database.host'
```

### `docparse text <file>`

Strips non-printable bytes from any file, collapses consecutive whitespace. Useful for reading binary files that contain embedded text.

```bash
docparse text binary_blob.dat
```

### `docparse detect <file>`

Auto-detects the file format using magic bytes, file extension, and content heuristics — then parses accordingly.

```bash
$ docparse detect unknown_file
PDF — extracting text

... text output ...
```

**Detection strategy:**
1. Magic bytes (`%PDF` → PDF, `PK\x03\x04` → ZIP-based Office)
2. File extension (`.xlsx`, `.docx`, `.pptx`)
3. Content heuristics (commas → CSV, tabs → TSV, `{`/`[` → JSON)

For Office files (DOCX, XLSX, PPTX), docparse detects the format and prints the correct `unzip` command to extract the XML content.

---

## Pipes & Redirection

docparse follows the Unix philosophy — read from stdin, write to stdout.

```bash
# Chain with other tools
docparse csv data.csv | grep "Engineering"

# Pipe from curl
curl -s https://example.com/data.csv | docparse csv -

# Pipe from unzip (for Office files)
unzip -p report.docx word/document.xml | docparse text -

# Combine with jq
docparse json data.json | jq '.items[] | .name'

# Save output
docparse pdf report.pdf > report.txt
```

The `-` argument tells docparse to read from stdin instead of a file.

---

## Building from Source

### Standard build

```bash
# Release build (~70KB)
zig build -Doptimize=ReleaseSmall

# Debug build (with stack traces)
zig build -Doptimize=Debug
```

### Development workflow

```bash
# Build and run in one command
zig build run -- pdf my_file.pdf

# Run the test suite
zig build test

# Clean build artifacts
rm -rf zig-out zig-cache
```

### Makefile (optional)

A thin wrapper around `zig build` is provided:

```bash
make          # build release
make test     # build + run tests
make install  # copy to /usr/local/bin
make clean    # remove build artifacts
make debug    # build with debug symbols
```

---

## Architecture

docparse is organized as a set of focused modules, each responsible for one format:

```
src/
├── main.zig        CLI entry point, argument parsing, file I/O
├── pdf.zig         PDF text extraction (BT/ET, hex strings, ASCII fallback)
├── table.zig       CSV/TSV parser with quoted field support
├── text.zig        Binary-to-text extractor (single-pass)
└── detect.zig      Format auto-detection (magic bytes + heuristics)
```

### Data flow

```
stdin / file
    │
    ▼
┌─────────────┐
│   main.zig  │  reads file into memory (max 50MB)
└──────┬──────┘
       │ dispatch (enum switch)
       ├──────────┬──────────┬──────────┐
       ▼          ▼          ▼          ▼
  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
  │ pdf.zig│ │table.zig│ │text.zig│ │detect.zig│
  └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘
      │          │          │          │
      └──────────┴──────────┴──────────┘
                         │
                         ▼
                    stdout output
```

For detailed design decisions and tradeoffs, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Performance

| Metric | Value | Notes |
|--------|-------|-------|
| Binary size | **72KB** | ReleaseSmall + strip |
| Startup time | **<5ms** | Static binary, no init |
| RAM usage | **<2MB** | Arena allocator |
| PDF extraction | **~1ms/MB** | O(n) linear scan |
| CSV parsing | **~0.5ms/MB** | Single-pass |
| 10K row CSV | **~50ms** | Including formatting |
| Dependencies | **0** | Only Zig stdlib |

### Why so fast?

- **No AST, no DOM** — single-pass linear scans
- **No GC** — arena allocation, freed on exit
- **No dynamic linking** — fully static binary
- **No runtime init** — main() is the first thing that runs

---

## What This Is NOT

| Not this | Use instead |
|----------|-------------|
| Complete PDF parser (forms, annotations, layout) | [poppler-utils](https://poppler.freedesktop.org/) |
| OCR for scanned documents | [Tesseract](https://github.com/tesseract-ocr/tesseract) |
| Spreadsheet calculator (formulas, charts) | [pandas](https://pandas.pydata.org/) |
| Word processor (formatting, styles) | [LibreOffice](https://www.libreoffice.org/) |
| XML parser for DOCX internals | `unzip` + standard XML tools |

docparse covers the 80% case: *"What text is in this file?"* — fast, reliably, with zero setup.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history.

---

## License

[MIT](LICENSE) — do whatever you want with it.
