const std = @import("std");
const owl = @import("owl");
const reading = @import("reading.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) {
            std.debug.print("Memory leak detected.", .{});
        }
    }

    const allocator = gpa.allocator();

    var reader = reading.Reader.init(allocator);
    defer reader.deinit();

    try reader.tokenize("123");
}
