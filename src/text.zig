const std = @import("std");

// ─── Plain text extraction ───
// Strips non-printable characters, collapses whitespace.

pub fn extract(data: []const u8) !void {
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();

    for (data) |b| {
        if (b >= 0x20 and b <= 0x7E) {
            try buf.append(b);
        } else if (b == '\n' or b == '\r' or b == '\t') {
            try buf.append(b);
        } else if (buf.items.len > 0 and buf.items[buf.items.len - 1] != ' ') {
            try buf.append(' ');
        }
    }

    // Collapse multiple spaces/tabs
    var clean = std.ArrayList(u8).init(std.heap.page_allocator);
    defer clean.deinit();
    var prev_space = false;
    for (buf.items) |b| {
        if (b == ' ' or b == '\t') {
            if (!prev_space) {
                try clean.append(' ');
                prev_space = true;
            }
        } else {
            prev_space = false;
            try clean.append(b);
        }
    }

    std.debug.print("{s}\n", .{clean.items});
}

pub fn print(data: []const u8) !void {
    std.debug.print("{s}\n", .{data});
}
