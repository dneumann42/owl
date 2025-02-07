const std = @import("std");
const v = @import("values.zig");

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
    };

    allocator: std.mem.Allocator,
    values: std.ArrayList(*v.Value),
    nothing_value: ?*v.Value,

    pub fn init(allocator: std.mem.Allocator) Gc {
        return .{
            .allocator = allocator,
            .values = std.ArrayList(*v.Value).init(allocator),
            .nothing_value = null,
        };
    }

    pub fn deinit(self: *Gc) void {
        for (self.values.items) |value| {
            self.deinitValue(value);
        }
        self.values.deinit();
    }

    pub fn deinitValue(self: *Gc, value: *v.Value) void {
        switch (value.*) {
            .string => |s| {
                self.allocator.free(s);
            },
            .symbol => |s| {
                self.allocator.free(s);
            },
            .list => |xs| {
                xs.deinit();
            },
            .function => |f| {
                f.deinit();
            },
            .dictionary => |*d| {
                d.deinit();
            },
            else => {},
        }
        self.destroy(value);
    }

    fn destroy(self: *Gc, value: *v.Value) void {
        const pair: *AlignedPair = @fieldParentPtr("value", value);
        self.allocator.destroy(pair);
    }

    pub fn nothing(self: *Gc) *v.Value {
        if (self.nothing_value == null) {
            self.nothing_value = self.create(v.Value.nothing) catch unreachable;
        }
        return self.nothing_value.?;
    }

    pub fn create(self: *Gc, default: v.Value) !*v.Value {
        const pair = try self.allocator.create(AlignedPair);
        pair.header = GcHeader{ .marked = false };
        const ptr = &pair.value;
        ptr.* = default;
        try self.values.append(ptr);
        return ptr;
    }

    pub fn num(self: *Gc, n: f64) *v.Value {
        return self.create(.{ .number = n }) catch unreachable;
    }

    pub fn sym(self: *Gc, s: []const u8) *v.Value {
        return self.create(.{ .symbol = s }) catch unreachable;
    }

    pub fn str(self: *Gc, s: []const u8) *v.Value {
        return self.create(.{ .string = s }) catch unreachable;
    }

    pub fn symAlloc(self: *Gc, s: []const u8) *v.Value {
        const copy = self.allocator.alloc(u8, s.len) catch unreachable;
        std.mem.copyForwards(u8, copy, s);
        return self.create(.{ .symbol = copy }) catch unreachable;
    }

    pub fn strAlloc(self: *Gc, s: []const u8) *v.Value {
        const copy = self.allocator.alloc(u8, s.len) catch unreachable;
        std.mem.copyForwards(u8, copy, s);
        return self.create(.{ .string = copy }) catch unreachable;
    }

    pub fn boolean(self: *Gc, b: bool) *v.Value {
        return self.create(.{ .boolean = b }) catch unreachable;
    }

    pub fn nfun(self: *Gc, f: v.NativeFunction) *v.Value {
        return self.create(.{ .nativeFunction = f }) catch unreachable;
    }

    pub fn T(self: *Gc) *v.Value {
        return self.boolean(true);
    }

    pub fn F(self: *Gc) *v.Value {
        return self.boolean(false);
    }

    pub fn getHeader(value: *v.Value) *GcHeader {
        const pair: *AlignedPair = @fieldParentPtr("value", value);
        return &pair.header;
    }

    pub fn mark(self: *Gc, root: *v.Value) void {
        _ = self;
        _ = root;
    }
};
