const std = @import("std");

/// Extracts readable text from any file by stripping non-printable bytes.
/// Single-pass: strips binary and collapses whitespace simultaneously.

pub fn extract(alloc: std.mem.Allocator, data: []const u8) !void {
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();

    var prev_space = false;
    for (data) |b| {
        if (b >= 0x20 and b <= 0x7E) {
            // Printable ASCII
            prev_space = false;
            try out.append(b);
        } else if (b == '\n' or b == '\r') {
            // Newlines preserved (collapse multiples)
            if (out.items.len > 0 and
                out.items[out.items.len - 1] != '\n' and
                out.items[out.items.len - 1] != '\r')
            {
                try out.append('\n');
            }
            prev_space = false;
        } else if (b == '\t') {
            // Tabs become spaces
            if (!prev_space) {
                try out.append(' ');
                prev_space = true;
            }
        } else {
            // Binary byte → space (collapse multiples)
            if (!prev_space) {
                try out.append(' ');
                prev_space = true;
            }
        }
    }

    std.debug.print("{s}\n", .{out.items});
}

/// Pass-through: print data as-is. Used for JSON and similar formats.
pub fn print(data: []const u8) void {
    std.debug.print("{s}\n", .{data});
}
