const std = @import("std");

// ─── PDF text extraction ───
// Extracts text from PDF streams. Handles BT/ET text objects and raw ASCII.

pub fn extract(alloc: std.mem.Allocator, data: []const u8) !void {
    if (!std.mem.startsWith(u8, data, "%PDF")) {
        std.debug.print("Not a PDF file\n", .{});
        return;
    }

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();

    // Scan for stream...endstream blocks
    var pos: usize = 0;
    while (pos < data.len) {
        if (std.mem.indexOf(u8, data[pos..], "stream")) |s| {
            const start = pos + s + 6;
            // Skip newline after 'stream'
            var cs = start;
            while (cs < data.len and (data[cs] == '\r' or data[cs] == '\n')) : (cs += 1) {}

            if (std.mem.indexOf(u8, data[cs..], "endstream")) |e| {
                try extractStream(data[cs .. cs + e], &out);
                pos = cs + e;
                continue;
            }
        }
        pos += 1;
    }

    if (out.items.len == 0) {
        std.debug.print("No text content found\n", .{});
        return;
    }

    // Clean: collapse >2 consecutive newlines
    var clean = std.ArrayList(u8).init(alloc);
    defer clean.deinit();
    var nl_count: usize = 0;
    for (out.items) |b| {
        if (b == '\n' or b == '\r') {
            nl_count += 1;
            if (nl_count <= 2) try clean.append('\n');
        } else {
            nl_count = 0;
            try clean.append(b);
        }
    }
    std.debug.print("{s}\n", .{clean.items});
}

fn extractStream(stream: []const u8, out: *std.ArrayList(u8)) !void {
    // Method 1: Extract (text) Tj inside BT...ET blocks
    var pos: usize = 0;
    var in_text = false;

    while (pos < stream.len) {
        // BT = Begin Text
        if (!in_text and pos + 2 <= stream.len and
            stream[pos] == 'B' and stream[pos + 1] == 'T' and
            isWS(stream[pos -| 1]))
        {
            in_text = true;
            pos += 2;
            continue;
        }

        // ET = End Text
        if (in_text and pos + 2 <= stream.len and
            stream[pos] == 'E' and stream[pos + 1] == 'T' and
            isWS(stream[pos -| 1]))
        {
            in_text = false;
            pos += 2;
            continue;
        }

        // (text) Tj — extract parenthesized string
        if (in_text and stream[pos] == '(') {
            var end = pos + 1;
            while (end < stream.len) : (end += 1) {
                if (stream[end] == '\\' and end + 1 < stream.len) {
                    end += 1; // Skip escaped char
                    continue;
                }
                if (stream[end] == ')') {
                    try out.appendSlice(stream[pos + 1 .. end]);
                    try out.append('\n');
                    break;
                }
            }
        }

        pos += 1;
    }

    // Method 2: Fallback — extract printable ASCII sequences
    if (out.items.len == 0) {
        var consecutive_binary: usize = 0;
        for (stream) |b| {
            if (b >= 0x20 and b <= 0x7E) {
                consecutive_binary = 0;
                try out.append(b);
            } else if (b == '\n' or b == '\r' or b == '\t') {
                consecutive_binary = 0;
                try out.append(b);
            } else {
                consecutive_binary += 1;
                if (consecutive_binary > 30) return; // Binary blob, stop
            }
        }
    }
}

fn isWS(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\r' or c == '\t' or c == 0;
}
