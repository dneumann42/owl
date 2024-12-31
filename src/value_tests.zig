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
    const dict = try gc.create(.{ .dictionary = v.Dictionary.init(gc.allocator) });
    try dict.dictionary.put(gc.symAlloc("hello"), gc.num(123.0));
    try dict.dictionary.put(gc.num(69.0), gc.num(420.0));
    const value = dict.dictionary.get(gc.symAlloc("hello")) orelse unreachable;
    const value2 = dict.dictionary.get(gc.num(69.0)) orelse unreachable;
    try expectEq(123.0, value.number);
    try expectEq(420.0, value2.number);
}
