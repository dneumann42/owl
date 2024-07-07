const std = @import("std");
const v = @import("values.zig");

const GarbageCollectorError = error{Invalid};

pub const GarbageCollector = struct {
    allocator: std.mem.Allocator,

    root: ?*v.Value = null,

    pub fn init(allocator: std.mem.Allocator) GarbageCollector {
        return .{ .allocator = allocator };
    }

    pub fn create() !*v.Value {
        return error.Invalid;
    }
};
