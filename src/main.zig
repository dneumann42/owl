const std = @import("std");

const reader = @import("reader.zig");
const Reader = reader.Reader;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            std.log.err("LEAKED MEMORY\n", .{});
        }
    }

    const code: []const u8 =
        \\ 1 + 2
    ;
    var rdr = Reader.init(allocator, code);
    defer rdr.deinit();

    _ = try rdr.read();
}
