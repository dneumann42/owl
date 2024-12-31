const v = @import("values.zig");
const std = @import("std");
const gc = @import("gc.zig");

const expect = std.testing.expect;

test "garbage collection" {
    var g = gc.Gc.init(std.testing.allocator);
    defer g.deinit();
    var d = try g.create(.{ .dictionary = v.Dictionary.init(g.allocator) });

    const hello = "hello";
    const sym = try g.allocator.alloc(u8, hello.len);
    @memcpy(sym, hello);
    try d.dictionary.put(g.sym(sym), g.num(123.0));
}
