const v = @import("values.zig");
const std = @import("std");

pub const GcError = error{
    Invalid,
};

pub const Gc = struct {
    const GcHeader = struct {
        marked: bool,
    };

    const GcRoot = struct {
        environment: *v.Environment,
    };

    const AlignedPair = struct {
        value: v.Value,
        header: GcHeader,
    };

    depth: i64,
    allocator: std.mem.Allocator,
    topEnv: *v.Environment,

    values: std.ArrayList(*v.Value),

    root: GcRoot,

    nothingValue: ?*v.Value,

    pub fn init(allocator: std.mem.Allocator) Gc {
        const environment = v.Environment.init(allocator) catch unreachable;
        return .{
            .allocator = allocator,
            .values = std.ArrayList(*v.Value).init(allocator),
            .nothingValue = null,
            .root = .{
                .environment = environment,
            },
            .depth = 0,
            .topEnv = environment,
        };
    }

    pub fn env(self: *Gc) *v.Environment {
        return self.topEnv;
    }

    pub fn push(self: *Gc) Gc {
        return self.pushEnv(self.topEnv);
    }

    // this is busted, en could be the environment from the function
    // we need en to be the top and not the next
    pub fn pushEnv(self: *Gc, en: *v.Environment) Gc {
        const new_environment = v.Environment.init(self.allocator) catch unreachable;
        new_environment.next = en;

        const g = Gc{
            .allocator = self.allocator,
            .values = self.values,
            .nothingValue = self.nothingValue,
            .root = self.root,
            .depth = self.depth + 1,
            .topEnv = new_environment,
        };

        return g;
    }

    pub fn withEnv(self: *Gc, en: *v.Environment) Gc {
        const g = Gc{
            .allocator = self.allocator,
            .values = self.values,
            .nothingValue = self.nothingValue,
            .root = self.root,
            .depth = self.depth + 1,
            .topEnv = en,
        };
        return g;
    }

    pub fn newEnv(self: *Gc, en: *v.Environment) !*Gc {
        const next = try self.allocator.create(Gc);
        next.* = self.withEnv(en);
        return next;
    }

    pub fn deinit(self: *Gc) void {
        self.destroyAll();
        self.values.deinit();
        self.root.environment.deinit();
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

    pub fn num(self: *Gc, n: f64) *v.Value {
        return self.create(.{ .number = n }) catch unreachable;
    }

    pub fn sym(self: *Gc, s: []const u8) *v.Value {
        return self.create(.{ .symbol = s }) catch unreachable;
    }

    pub fn str(self: *Gc, s: []const u8) *v.Value {
        return self.create(.{ .string = s }) catch unreachable;
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
