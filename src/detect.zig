const std = @import("std");

const pdf = @import("pdf.zig");
const table = @import("table.zig");
const text = @import("text.zig");

// ─── Format auto-detection ───
// Uses magic bytes, file extensions, and content heuristics.

pub fn andParse(alloc: std.mem.Allocator, data: []const u8, file: []const u8) !void {
    // PDF magic bytes
    if (std.mem.startsWith(u8, data, "%PDF")) {
        std.debug.print("\x1b[1;34mPDF\x1b[0m — extracting text\n\n", .{});
        return pdf.extract(alloc, data);
    }

    // ZIP magic bytes (DOCX, XLSX, PPTX are ZIP archives)
    if (data.len >= 4 and data[0] == 0x50 and data[1] == 0x4B and data[2] == 0x03 and data[3] == 0x04) {
        const ext = fileExtension(file);
        if (std.mem.eql(u8, ext, "xlsx") or std.mem.eql(u8, ext, "xls")) {
            std.debug.print("\x1b[1;32mXLSX\x1b[0m (Excel spreadsheet)\n", .{});
            std.debug.print("Tip: unzip -p {s} xl/sharedStrings.xml | docparse text -\n", .{file});
        } else if (std.mem.eql(u8, ext, "docx") or std.mem.eql(u8, ext, "doc")) {
            std.debug.print("\x1b[1;35mDOCX\x1b[0m (Word document)\n", .{});
            std.debug.print("Tip: unzip -p {s} word/document.xml | docparse text -\n", .{file});
        } else if (std.mem.eql(u8, ext, "pptx") or std.mem.eql(u8, ext, "ppt")) {
            std.debug.print("\x1b[1;33mPPTX\x1b[0m (PowerPoint presentation)\n", .{});
            std.debug.print("Tip: unzip -p {s} ppt/slides/slide*.xml | docparse text -\n", .{file});
        } else {
            std.debug.print("\x1b[1mZIP\x1b[0m archive\n", .{});
        }
        return;
    }

    // Heuristic: scan first 512 bytes for delimiters
    const head = data[0 .. @min(data.len, 512)];

    // CSV: commas present
    if (std.mem.indexOfScalar(u8, head, ',') != null) {
        std.debug.print("\x1b[1;36mCSV\x1b[0m — parsing table\n\n", .{});
        return table.parse(data, ',');
    }

    // TSV: tabs present
    if (std.mem.indexOfScalar(u8, head, '\t') != null) {
        std.debug.print("\x1b[1;36mTSV\x1b[0m — parsing table\n\n", .{});
        return table.parse(data, '\t');
    }

    // JSON: starts with { or [
    if (head.len > 0 and (head[0] == '{' or head[0] == '[')) {
        std.debug.print("\x1b[1;33mJSON\x1b[0m\n\n", .{});
        return text.print(data);
    }

    // Fallback: plain text
    std.debug.print("\x1b[1;37mText\x1b[0m — extracting content\n\n", .{});
    return text.extract(data);
}

fn fileExtension(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '.') return path[i + 1 ..];
    }
    return "";
}
