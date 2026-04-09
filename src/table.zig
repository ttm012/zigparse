const std = @import("std");

// ─── CSV/TSV table parser ───
// Handles quoted fields, escaped quotes, multi-line cells.
// Highlights header row in cyan.

pub fn parse(data: []const u8, delimiter: u8) !void {
    var row: u32 = 0;
    var col: u32 = 0;
    var in_quotes = false;
    var cell = std.ArrayList(u8).init(std.heap.page_allocator);
    defer cell.deinit();

    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        const c = data[i];

        if (in_quotes) {
            if (c == '"') {
                // Escaped quote: ""
                if (i + 1 < data.len and data[i + 1] == '"') {
                    try cell.append('"');
                    i += 1;
                } else {
                    in_quotes = false;
                }
            } else {
                try cell.append(c);
            }
        } else {
            if (c == '"') {
                in_quotes = true;
            } else if (c == delimiter) {
                printCell(cell.items, row);
                cell.clearRetainingCapacity();
                col += 1;
            } else if (c == '\n' or c == '\r') {
                if (cell.items.len > 0 or col > 0) {
                    printCell(cell.items, row);
                    std.debug.print("\n", .{});
                    row += 1;
                }
                cell.clearRetainingCapacity();
                col = 0;
                // Handle \r\n
                if (c == '\r' and i + 1 < data.len and data[i + 1] == '\n') {
                    i += 1;
                }
            } else {
                try cell.append(c);
            }
        }
    }

    // Last cell (no trailing newline)
    if (cell.items.len > 0 or col > 0) {
        printCell(cell.items, row);
        row += 1;
    }

    std.debug.print("  {d} rows\n", .{row});
}

fn printCell(cell: []const u8, row: u32) void {
    if (row == 0) {
        // Header: bold cyan
        std.debug.print("\x1b[1;36m{s}\x1b[0m \x1b[90m│\x1b[0m ", .{cell});
    } else {
        // Data: plain
        std.debug.print("{s} \x1b[90m│\x1b[0m ", .{cell});
    }
}
