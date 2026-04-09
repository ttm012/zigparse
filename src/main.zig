const std = @import("std");

const pdf = @import("pdf.zig");
const table = @import("table.zig");
const text = @import("text.zig");
const detect = @import("detect.zig");

const MAX_FILE = 50 * 1024 * 1024; // 50MB

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 3) {
        usage();
        std.process.exit(1);
    }

    const cmd = args[1];
    const file = args[2];
    const data = try readFile(alloc, file);

    try switch (parseCmd(cmd)) {
        .pdf => pdf.extract(alloc, data),
        .csv => table.parse(alloc, data, ','),
        .tsv => table.parse(alloc, data, '\t'),
        .json => text.print(data),
        .text => text.extract(alloc, data),
        .detect => detect.andParse(alloc, data, file),
        .unknown => {
            std.debug.print("Unknown command: {s}\n\n", .{cmd});
            usage();
            std.process.exit(1);
        },
    };
}

const Cmd = enum { pdf, csv, tsv, json, text, detect, unknown };

fn parseCmd(s: []const u8) Cmd {
    if (std.mem.eql(u8, s, "pdf")) return .pdf;
    if (std.mem.eql(u8, s, "csv")) return .csv;
    if (std.mem.eql(u8, s, "tsv")) return .tsv;
    if (std.mem.eql(u8, s, "json")) return .json;
    if (std.mem.eql(u8, s, "text")) return .text;
    if (std.mem.eql(u8, s, "detect")) return .detect;
    return .unknown;
}

fn usage() void {
    std.debug.print(
        \\zigparse — fast document parser (Zig, 0 deps)
        \\
        \\Usage: zigparse <format> <file>
        \\       zigparse <format> -        (read from stdin)
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
        \\  zigparse pdf report.pdf
        \\  zigparse csv data.csv
        \\  cat data.csv | zigparse csv -
        \\  zigparse detect unknown_file
        \\
    , .{});
}

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.mem.eql(u8, path, "-")) {
        const stdin = std.io.getStdIn();
        // Don't block if stdin is a terminal
        if (stdin.isTty()) {
            std.debug.print("Error: stdin is a terminal. Pipe data or provide a file.\n", .{});
            std.process.exit(1);
        }
        return stdin.readToEndAlloc(alloc, MAX_FILE);
    }
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(alloc, MAX_FILE);
}
