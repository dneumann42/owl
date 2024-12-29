const std = @import("std");
const r = @import("reader.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const expect = std.testing.expect;
const expectEq = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqStr = std.testing.expectEqualStrings;
const g = @import("gc.zig");

test "dictionaries" {
    var gc = g.Gc.init(std.testing.allocator);
    defer gc.deinit();
    var dict = v.Dictionary.init(gc.allocator);
    defer dict.deinit();
    try dict.put(gc.sym("hello"), gc.num(123.0));
    try dict.put(gc.num(69.0), gc.num(420.0));
    const value = dict.get(gc.sym("hello")) orelse unreachable;
    const value2 = dict.get(gc.num(69.0)) orelse unreachable;
    try expectEq(123.0, value.number);
    try expectEq(420.0, value2.number);
}
