const std = @import("std");
const v = @import("values.zig");
const g = @import("gc.zig");
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqual = std.testing.expectEqual;

const allocator = std.testing.allocator;

test "defining a variable" {
    var env = try v.Environment.init(allocator);
    defer env.deinit();
    var gc = g.Gc.init(allocator);
    defer gc.deinit();
    try env.define("hello", gc.num(123.0));
    const hello = env.find("hello") orelse unreachable;
    try expectEqual(123.0, hello.*.number);
}
