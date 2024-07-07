const v = @import("values.zig");
const std = @import("std");

pub const GcError = error{
    Invalid,
};

pub const Gc = struct {
    const GcHeader = struct {
        marked: bool,
    };
    const AlignedPair = struct {
        value: v.Value,
        header: GcHeader,
        // this could store line and meta information
    };
    allocator: std.mem.Allocator,
    values: std.ArrayList(*v.Value),

    pub fn init(allocator: std.mem.Allocator) Gc {
        return .{ .allocator = allocator, .values = std.ArrayList(*v.Value).init(allocator) };
    }

    pub fn destroy(self: *Gc, value: *v.Value) void {
        const pair: *AlignedPair = @fieldParentPtr("value", value);
        self.allocator.destroy(pair);
    }

    pub fn create(self: Gc, default: v.Value) !*v.Value {
        const pair = try self.allocator.create(AlignedPair);
        pair.header = GcHeader{ .marked = false };
        const ptr = &pair.value;
        ptr.* = default;
        return ptr;
    }

    pub fn getHeader(value: *v.Value) *GcHeader {
        const pair: *AlignedPair = @fieldParentPtr("value", value);
        return &pair.header;
    }

    pub fn destroyAll(self: *Gc) void {
        for (self.values.items) |val| {
            self.allocator.destroy(val);
        }
    }

    pub fn mark(self: *Gc, root: *v.Value) void {
        _ = self;
        _ = root;
    }
};
