const std = @import("std");

/// Extracts text from PDF files by scanning stream objects.
///
/// Two methods are used:
///   1. BT/ET text objects — extracts (text) Tj and <> Tj patterns
///   2. Raw ASCII fallback — prints readable bytes from non-binary streams

pub fn extract(alloc: std.mem.Allocator, data: []const u8) !void {
    if (!std.mem.startsWith(u8, data, "%PDF")) {
        std.debug.print("Not a PDF file\n", .{});
        return;
    }

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();

    // Single-pass linear scan for stream...endstream blocks — O(n)
    var pos: usize = 0;
    while (pos + 6 <= data.len) {
        if (std.mem.eql(u8, data[pos .. pos + 6], "stream")) {
            const content_start = blk: {
                var cs = pos + 6;
                while (cs < data.len and (data[cs] == '\r' or data[cs] == '\n')) : (cs += 1) {}
                break :blk cs;
            };

            if (std.mem.indexOf(u8, data[content_start..], "endstream")) |e| {
                try extractStream(data[content_start .. content_start + e], &out);
                pos = content_start + e + 9; // "endstream".len == 9
                continue;
            }
        }
        pos += 1;
    }

    if (out.items.len == 0) {
        std.debug.print("No text content found\n", .{});
        return;
    }

    // Clean: collapse more than 2 consecutive newlines into 2
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
    // Method 1: Extract text from BT...ET blocks
    // Supports both literal strings (text) Tj and hex strings <text> Tj
    var pos: usize = 0;
    var in_text = false;

    while (pos < stream.len) {
        // Check for BT (Begin Text)
        if (!in_text and
            stream[pos] == 'B' and
            pos + 1 < stream.len and stream[pos + 1] == 'T' and
            (pos == 0 or isWhitespace(stream[pos - 1])) and
            (pos + 2 >= stream.len or isWhitespace(stream[pos + 2])))
        {
            in_text = true;
            pos += 2;
            continue;
        }

        // Check for ET (End Text)
        if (in_text and
            stream[pos] == 'E' and
            pos + 1 < stream.len and stream[pos + 1] == 'T' and
            (pos == 0 or isWhitespace(stream[pos - 1])) and
            (pos + 2 >= stream.len or isWhitespace(stream[pos + 2])))
        {
            in_text = false;
            pos += 2;
            continue;
        }

        // Literal string: (text) Tj or (text) '
        if (in_text and stream[pos] == '(') {
            pos = try extractLiteralString(stream, pos, out);
            continue;
        }

        // Hex string: <text> Tj
        if (in_text and stream[pos] == '<' and pos + 1 < stream.len and stream[pos + 1] != '<') {
            pos = try extractHexString(stream, pos, out);
            continue;
        }

        pos += 1;
    }

    // Method 2: Fallback — extract printable ASCII from the stream
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
                if (consecutive_binary > 30) return; // Binary blob, abort
            }
        }
    }
}

/// Extract text from a PDF literal string: (hello world)
/// Returns the position after the closing paren.
fn extractLiteralString(stream: []const u8, start: usize, out: *std.ArrayList(u8)) !usize {
    var pos = start + 1; // skip opening (
    while (pos < stream.len) {
        if (stream[pos] == '\\' and pos + 1 < stream.len) {
            // Handle escape sequences
            pos += 1;
            const escaped = stream[pos];
            switch (escaped) {
                'n' => try out.append('\n'),
                'r' => try out.append('\r'),
                't' => try out.append('\t'),
                'b' => try out.append(8),
                'f' => try out.append(12),
                '(', ')' => try out.append(escaped),
                '\\' => try out.append('\\'),
                '0'...'7' => {
                    // Octal escape: \123
                    var code: u8 = escaped - '0';
                    if (pos + 1 < stream.len and stream[pos + 1] >= '0' and stream[pos + 1] <= '7') {
                        pos += 1;
                        code = code * 8 + (stream[pos] - '0');
                        if (pos + 1 < stream.len and stream[pos + 1] >= '0' and stream[pos + 1] <= '7') {
                            pos += 1;
                            code = code * 8 + (stream[pos] - '0');
                        }
                    }
                    try out.append(code);
                },
                else => try out.append(escaped),
            }
        } else if (stream[pos] == ')') {
            try out.append('\n');
            return pos + 1;
        } else {
            try out.append(stream[pos]);
        }
        pos += 1;
    }
    return pos;
}

/// Extract text from a PDF hex string: <48656c6c6f>
/// Returns the position after the closing >.
fn extractHexString(stream: []const u8, start: usize, out: *std.ArrayList(u8)) !usize {
    var pos = start + 1; // skip opening <
    var hex_buf: [2]u8 = undefined;
    var hex_pos: usize = 0;

    while (pos < stream.len) {
        const c = stream[pos];
        if (c == '>') {
            // Process remaining nibble if odd number of hex chars
            if (hex_pos == 1) {
                hex_buf[1] = '0';
                const byte = try parseHexByte(&hex_buf);
                if (byte >= 0x20 and byte <= 0x7E) try out.append(byte);
            }
            try out.append('\n');
            return pos + 1;
        }
        if (isHexChar(c)) {
            hex_buf[hex_pos] = c;
            hex_pos += 1;
            if (hex_pos == 2) {
                const byte = try parseHexByte(&hex_buf);
                if (byte >= 0x20 and byte <= 0x7E) try out.append(byte);
                hex_pos = 0;
            }
        }
        pos += 1;
    }
    return pos;
}

fn parseHexByte(hex: *const [2]u8) !u8 {
    const hi = try std.fmt.charToDigit(hex[0], 16);
    const lo = try std.fmt.charToDigit(hex[1], 16);
    return hi * 16 + lo;
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0;
}

fn isHexChar(c: u8) bool {
    return (c >= '0' and c <= '9') or
           (c >= 'a' and c <= 'f') or
           (c >= 'A' and c <= 'F');
}
