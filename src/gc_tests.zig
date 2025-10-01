const gc_ = @import("gc.zig");
const std = @import("std");
const testing = std.testing;

test "Allocate a new number" {
    var gc = gc_.Gc.init(testing.allocator);
    const num = try gc.alloc(f32);
    num.* = 3.14159;
    testing.expectEqual( //
        num.*, //
        3.14159 //
    );
}
