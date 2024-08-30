const std = @import("std");
const gc = @import("gc.zig");

const expect = std.testing.expect;

var G = gc.Gc.init(
    std.testing.allocator,
    std.testing.allocator,
);

test "garbage collection" {}
