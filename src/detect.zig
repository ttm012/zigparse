const std = @import("std");

const pdf = @import("pdf.zig");
const table = @import("table.zig");
const text = @import("text.zig");

// Magic byte signatures
const MAGIC_PDF = "%PDF";
const MAGIC_ZIP = "\x50\x4B\x03\x04"; // PK\x03\x04

pub fn andParse(alloc: std.mem.Allocator, data: []const u8, file: []const u8) !void {
    // PDF
    if (std.mem.startsWith(u8, data, MAGIC_PDF)) {
        std.debug.print("\x1b[1;34mPDF\x1b[0m — extracting text\n\n", .{});
        return pdf.extract(alloc, data);
    }

    // ZIP-based Office formats (DOCX, XLSX, PPTX)
    if (data.len >= 4 and std.mem.startsWith(u8, data, MAGIC_ZIP)) {
        return detectOfficeFormat(file);
    }

    // Content heuristics on first 512 bytes
    const head = data[0 .. @min(data.len, 512)];

    // CSV: commas present
    if (std.mem.indexOfScalar(u8, head, ',') != null) {
        std.debug.print("\x1b[1;36mCSV\x1b[0m — parsing table\n\n", .{});
        return table.parse(alloc, data, ',');
    }

    // TSV: tabs present
    if (std.mem.indexOfScalar(u8, head, '\t') != null) {
        std.debug.print("\x1b[1;36mTSV\x1b[0m — parsing table\n\n", .{});
        return table.parse(alloc, data, '\t');
    }

    // JSON: starts with { or [
    if (head.len > 0 and (head[0] == '{' or head[0] == '[')) {
        std.debug.print("\x1b[1;33mJSON\x1b[0m\n\n", .{});
        return text.print(data);
    }

    // Fallback: plain text
    std.debug.print("\x1b[1;37mText\x1b[0m — extracting content\n\n", .{});
    return text.extract(alloc, data);
}

fn detectOfficeFormat(file: []const u8) void {
    const ext = std.fs.path.extension(file);

    // Strip leading dot and compare
    const name = if (ext.len > 0) ext[1..] else ext;

    if (std.mem.eql(u8, name, "xlsx") or std.mem.eql(u8, name, "xls")) {
        std.debug.print("\x1b[1;32mXLSX\x1b[0m (Excel spreadsheet)\n", .{});
        std.debug.print("Tip: unzip -p {s} xl/sharedStrings.xml | zigparse text -\n", .{file});
    } else if (std.mem.eql(u8, name, "docx") or std.mem.eql(u8, name, "doc")) {
        std.debug.print("\x1b[1;35mDOCX\x1b[0m (Word document)\n", .{});
        std.debug.print("Tip: unzip -p {s} word/document.xml | zigparse text -\n", .{file});
    } else if (std.mem.eql(u8, name, "pptx") or std.mem.eql(u8, name, "ppt")) {
        std.debug.print("\x1b[1;33mPPTX\x1b[0m (PowerPoint presentation)\n", .{});
        std.debug.print("Tip: unzip -p {s} ppt/slides/slide*.xml | zigparse text -\n", .{file});
    } else {
        std.debug.print("\x1b[1mZIP\x1b[0m archive\n", .{});
    }
}
