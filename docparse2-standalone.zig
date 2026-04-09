const std = @import("std");

// ─── docparse2 — Pure Zig PDF + table parser ───
// Zero deps. No macOS tools. Minimal core.
// PDF text extraction, CSV/TSV tables, JSON, plain text.

const MAX_FILE = 50 * 1024 * 1024;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 3) { usage(); std.process.exit(1); }

    const cmd = args[1];
    const file = args[2];
    const data = readfile(alloc, file);

    if (eq(cmd, "pdf")) try pdf(alloc, data);
    if (eq(cmd, "csv")) try csv(data, ',');
    if (eq(cmd, "tsv")) try csv(data, '\t');
    if (eq(cmd, "json")) try json(alloc, data);
    if (eq(cmd, "text")) try text(data);
    if (eq(cmd, "detect")) try detect(alloc, data, file);
    if (!(eq(cmd, "pdf") or eq(cmd, "csv") or eq(cmd, "tsv") or eq(cmd, "json") or eq(cmd, "text") or eq(cmd, "detect"))) {
        std.debug.print("Unknown: {s}\n", .{cmd}); std.process.exit(1);
    }
}

fn usage() void {
    std.debug.print(
        \\docparse2 — pure zig parser (0 deps)
        \\usage: docparse2 <fmt> <file>
        \\fmts: pdf csv tsv json text detect
        \\
    , .{});
}

// ═══ Helpers ═══

fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn readfile(alloc: std.mem.Allocator, path: []const u8) []const u8 {
    if (std.mem.eql(u8, path, "-")) {
        return std.io.getStdIn().readToEndAlloc(alloc, MAX_FILE) catch {
            std.debug.print("Cannot read stdin\n", .{});
            std.process.exit(1);
        };
    }
    const f = std.fs.openFileAbsolute(path, .{}) catch {
        std.debug.print("Cannot open: {s}\n", .{path});
        std.process.exit(1);
    };
    defer f.close();
    return f.readToEndAlloc(alloc, MAX_FILE) catch {
        std.debug.print("Too large or unreadable\n", .{});
        std.process.exit(1);
    };
}

// ═══ PDF: extract text from streams ═══

fn pdf(alloc: std.mem.Allocator, data: []const u8) !void {
    if (!std.mem.startsWith(u8, data, "%PDF")) { std.debug.print("Not PDF\n", .{}); return; }
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    var pos: usize = 0;
    while (pos < data.len) {
        if (std.mem.indexOf(u8, data[pos..], "stream")) |s| {
            const start = pos + s + 6;
            var cs = start;
            while (cs < data.len and (data[cs] == '\r' or data[cs] == '\n')) : (cs += 1) {}
            if (std.mem.indexOf(u8, data[cs..], "endstream")) |e| {
                try streamText(data[cs .. cs + e], &out);
                pos = cs + e;
                continue;
            }
        }
        pos += 1;
    }
    if (out.items.len == 0) { std.debug.print("No text\n", .{}); return; }
    // Clean: collapse >2 newlines
    var c = std.ArrayList(u8).init(alloc);
    defer c.deinit();
    var nl: usize = 0;
    for (out.items) |b| {
        if (b == '\n' or b == '\r') { nl += 1; if (nl <= 2) try c.append('\n'); }
        else { nl = 0; try c.append(b); }
    }
    std.debug.print("{s}\n", .{c.items});
}

fn streamText(stream: []const u8, out: *std.ArrayList(u8)) !void {
    // Method 1: (text) Tj inside BT...ET
    var pos: usize = 0;
    var bt = false;
    while (pos < stream.len) {
        if (!bt and pos + 2 <= stream.len and stream[pos] == 'B' and stream[pos + 1] == 'T' and ws(stream[pos -| 1])) { bt = true; pos += 2; continue; }
        if (bt and pos + 2 <= stream.len and stream[pos] == 'E' and stream[pos + 1] == 'T' and ws(stream[pos -| 1])) { bt = false; pos += 2; continue; }
        if (bt and stream[pos] == '(') {
            var end = pos + 1;
            while (end < stream.len) : (end += 1) {
                if (stream[end] == '\\' and end + 1 < stream.len) { end += 1; continue; }
                if (stream[end] == ')') { try out.appendSlice(stream[pos + 1 .. end]); try out.append('\n'); break; }
            }
        }
        pos += 1;
    }
    // Method 2: raw printable ASCII
    if (out.items.len == 0) {
        var bad: usize = 0;
        for (stream) |b| {
            if (b >= 0x20 and b <= 0x7E) { bad = 0; try out.append(b); }
            else if (b == '\n' or b == '\r' or b == '\t') { bad = 0; try out.append(b); }
            else { bad += 1; if (bad > 30) return; }
        }
    }
}

fn ws(c: u8) bool { return c == ' ' or c == '\n' or c == '\r' or c == '\t' or c == 0; }

// ═══ CSV/TSV: table parser with header colors ═══

fn csv(data: []const u8, delim: u8) !void {
    var row: u32 = 0;
    var col: u32 = 0;
    var iq = false;
    var cell = std.ArrayList(u8).init(std.heap.page_allocator);
    defer cell.deinit();
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        const c = data[i];
        if (iq) {
            if (c == '"') { if (i + 1 < data.len and data[i + 1] == '"') { try cell.append('"'); i += 1; } else iq = false; }
            else try cell.append(c);
        }
        if (!iq) {
            if (c == '"') iq = true;
            if (c == delim and !iq) { pcell(cell.items, row); cell.clearRetainingCapacity(); col += 1; }
            if ((c == '\n' or c == '\r') and !iq) {
                if (cell.items.len > 0 or col > 0) { pcell(cell.items, row); row += 1; std.debug.print("\n", .{}); }
                cell.clearRetainingCapacity(); col = 0;
                if (c == '\r' and i + 1 < data.len and data[i + 1] == '\n') i += 1;
            }
            if (c != '"' and c != delim and c != '\n' and c != '\r' and !iq) try cell.append(c);
        }
    }
    if (cell.items.len > 0 or col > 0) { pcell(cell.items, row); }
    std.debug.print("  {d} rows\n", .{row + 1});
}

fn pcell(cell: []const u8, row: u32) void {
    if (row == 0) std.debug.print("\x1b[1;36m{s}\x1b[0m │ ", .{cell})
    else std.debug.print("{s} │ ", .{cell});
}

// ═══ JSON: pretty print ═══

fn json(alloc: std.mem.Allocator, data: []const u8) !void {
    _ = alloc;
    // Just print raw JSON — pretty print not available in std.json.stringify 0.13
    std.debug.print("{s}\n", .{data});
}

// ═══ Text: strip binary, keep readable ═══

fn text(data: []const u8) !void {
    var o = std.ArrayList(u8).init(std.heap.page_allocator);
    defer o.deinit();
    for (data) |b| {
        if (b >= 0x20 and b <= 0x7E) { try o.append(b); }
        else if (b == '\n' or b == '\r' or b == '\t') { try o.append(b); }
        else if (o.items.len > 0 and o.items[o.items.len - 1] != ' ') { try o.append(' '); }
    }
    var c = std.ArrayList(u8).init(std.heap.page_allocator);
    defer c.deinit();
    var ps = false;
    for (o.items) |b| {
        if (b == ' ' or b == '\t') { if (!ps) { try c.append(' '); ps = true; } }
        else { ps = false; try c.append(b); }
    }
    std.debug.print("{s}\n", .{c.items});
}

// ═══ Detect + auto-parse ═══

fn detect(alloc: std.mem.Allocator, data: []const u8, file: []const u8) !void {
    if (std.mem.startsWith(u8, data, "%PDF")) { std.debug.print("📄 PDF\n\n", .{}); return pdf(alloc, data); }
    if (data.len >= 4 and data[0] == 0x50 and data[1] == 0x4B) {
        if (std.mem.endsWith(u8, file, ".xlsx") or std.mem.endsWith(u8, file, ".xls")) { std.debug.print("📊 XLSX — unzip xl/sharedStrings.xml then parse\n", .{}); return; }
        if (std.mem.endsWith(u8, file, ".docx") or std.mem.endsWith(u8, file, ".doc")) { std.debug.print("📝 DOCX — unzip word/document.xml then parse\n", .{}); return; }
        std.debug.print("📦 ZIP-based format\n", .{});
        return;
    }
    const head = data[0..@min(data.len, 512)];
    if (std.mem.indexOfScalar(u8, head, ',') != null) { std.debug.print("📋 CSV\n\n", .{}); return csv(data, ','); }
    if (std.mem.indexOfScalar(u8, head, '\t') != null) { std.debug.print("📋 TSV\n\n", .{}); return csv(data, '\t'); }
    if (head.len > 0 and (head[0] == '{' or head[0] == '[')) { std.debug.print("📊 JSON\n\n", .{}); return json(alloc, data); }
    std.debug.print("📄 Plain text\n\n", .{});
    try text(data);
}
