const std = @import("std");

// ─── docparse — Fast document parser in Zig ───
// Zero dependencies. Single binary.

const MAX_FILE = 50 * 1024 * 1024; // 50MB

const pdf = @import("pdf.zig");
const table = @import("table.zig");
const text = @import("text.zig");
const detect = @import("detect.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 3) { usage(); std.process.exit(1); }

    const cmd = args[1];
    const file = args[2];
    const data = try readFile(alloc, file);

    if (eq(cmd, "pdf")) try pdf.extract(alloc, data);
    if (eq(cmd, "csv")) try table.parse(data, ',');
    if (eq(cmd, "tsv")) try table.parse(data, '\t');
    if (eq(cmd, "json")) try text.print(data);
    if (eq(cmd, "text")) try text.extract(data);
    if (eq(cmd, "detect")) try detect.andParse(alloc, data, file);
    if (!isValidCmd(cmd)) { std.debug.print("Unknown: {s}\n", .{cmd}); std.process.exit(1); }
}

fn usage() void {
    std.debug.print(
        \\docparse — fast document parser (Zig, 0 deps)
        \\
        \\Usage: docparse <format> <file>
        \\       docparse <format> -        (read from stdin)
        \\
        \\Formats:
        \\  pdf     Extract text from PDF files
        \\  csv     Parse CSV tables (comma-separated)
        \\  tsv     Parse TSV tables (tab-separated)
        \\  json    Output JSON content
        \\  text    Strip binary, keep readable text
        \\  detect  Auto-detect format and parse
        \\
        \\Examples:
        \\  docparse pdf report.pdf
        \\  docparse csv data.csv
        \\  cat data.csv | docparse csv -
        \\  docparse detect unknown_file
        \\
    , .{});
}

fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }

fn isValidCmd(cmd: []const u8) bool {
    const cmds = [_][]const u8{ "pdf", "csv", "tsv", "json", "text", "detect" };
    for (cmds) |c| { if (eq(cmd, c)) return true; }
    return false;
}

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (eq(path, "-")) {
        return std.io.getStdIn().readToEndAlloc(alloc, MAX_FILE);
    }
    const f = try std.fs.openFileAbsolute(path, .{});
    defer f.close();
    return f.readToEndAlloc(alloc, MAX_FILE);
}
