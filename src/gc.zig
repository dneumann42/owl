const v = @import("values.zig");
const std = @import("std");

pub const GcError = error{
    Invalid,
};

pub const Gc = struct {
    const GcHeader = struct {
        marked: bool,
        // this could store meta information
    };
    const AlignedPair = struct {
        value: v.Value,
        header: GcHeader,
    };
    allocator: std.mem.Allocator,
    listAllocator: std.mem.Allocator,
    values: std.ArrayList(*v.Value),
    nothingValue: ?*v.Value,

    pub fn init(allocator: std.mem.Allocator, listAllocator: std.mem.Allocator) Gc {
        return .{ .allocator = allocator, .listAllocator = listAllocator, .values = std.ArrayList(*v.Value).init(listAllocator), .nothingValue = null };
    }

    pub fn deinit(self: *Gc) void {
        self.destroyAll();
        self.values.deinit();
    }

    fn destroy(self: *Gc, value: *v.Value) void {
        const pair: *AlignedPair = @fieldParentPtr("value", value);
        self.allocator.destroy(pair);
    }

    pub fn nothing(self: *Gc) *v.Value {
        if (self.nothingValue == null) {
            self.nothingValue = self.create(v.Value.nothing) catch unreachable;
        }
        return self.nothingValue.?;
    }

    pub fn create(self: *Gc, default: v.Value) !*v.Value {
        const pair = try self.allocator.create(AlignedPair);
        pair.header = GcHeader{ .marked = false };
        const ptr = &pair.value;
        ptr.* = default;
        try self.values.append(ptr);
        return ptr;
    }

    pub fn getHeader(value: *v.Value) *GcHeader {
        const pair: *AlignedPair = @fieldParentPtr("value", value);
        return &pair.header;
    }

    pub fn destroyAll(self: *Gc) void {
        for (self.values.items) |val| {
            switch (val.*) {
                .dictionary => {
                    val.dictionary.deinit();
                },
                else => {},
            }
            self.destroy(val);
        }
        self.values.resize(0) catch {};
    }

    pub fn mark(self: *Gc, root: *v.Value) void {
        _ = self;
        _ = root;
    }
};
