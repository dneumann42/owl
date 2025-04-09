const std = @import("std");
const v = @import("value.zig");
const Value = v.Value;
const Environment = v.Environment;

const HEAP_SIZE = 1024 * 8;
const NOTHING_INDEX = 0;

pub const Gc = struct {
    allocator: std.mem.Allocator,

    values: [HEAP_SIZE]Value,
    headers: [HEAP_SIZE]Header,
    symbols: std.StringHashMap(usize),

    environment: *Environment,

    const Header = struct {
        used: bool = false,
        marked: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return @This(){ //
            .allocator = allocator,
            .environment = try Environment.init(allocator),
            .symbols = std.StringHashMap(usize).init(allocator),
            .values = [_]Value{.nothing} ** HEAP_SIZE,
            .headers = [_]Header{Header{}} ** HEAP_SIZE,
        };
    }

    pub fn deinit(self: *Gc) void {
        self.environment.deinit();
        self.symbols.deinit();
        self.allocator.destroy(self.environment);
        for (0..self.values.len) |i| {
            const value = self.values[i];
            if (!self.headers[i].used) {
                continue;
            }
            switch (value) {
                .string, .symbol => |s| self.allocator.free(s),
                .list => |xs| xs.deinit(),
                .fun => |func| {
                    for (func.params.items) |s| {
                        self.allocator.free(s);
                    }
                    func.params.deinit();
                },
                else => {},
            }
        }
    }

    pub fn push(self: *Gc) void {
        _ = self;
    }

    pub fn pop() void {}

    pub fn find(self: *Gc, key: usize) ?usize {
        return self.environment.find(key);
    }

    pub fn put(self: *Gc, key: usize, value: usize) !void {
        return self.environment.put(key, value);
    }

    fn findUnused(self: Gc) ?usize {
        for (1..self.values.len) |i| {
            if (!self.headers[i].used) {
                return i;
            }
        }
        return null;
    }

    pub fn getValue(self: *Gc, index: usize) *Value {
        return &self.values[index];
    }

    pub fn getHeader(self: *Gc, index: usize) *Header {
        return &self.headers[index];
    }

    pub fn nothing(self: *Gc) usize {
        if (self.headers[NOTHING_INDEX].used) {
            return NOTHING_INDEX;
        }
        self.headers[NOTHING_INDEX] = .{ .used = true, .marked = false };
        self.values[NOTHING_INDEX] = .nothing;
        return NOTHING_INDEX;
    }

    pub fn number(self: *Gc, n: f64) usize {
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .number = n };
        return i;
    }

    pub fn boolean(self: *Gc, b: bool) usize {
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .boolean = b };
        return i;
    }

    pub fn string(self: *Gc, s: []const u8) usize {
        const str = self.allocator.alloc(u8, s.len) catch @panic("Out of memory");
        @memcpy(str, s);
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .string = str };
        return i;
    }

    pub fn symbol(self: *Gc, s: []const u8) usize {
        if (self.symbols.contains(s)) {
            return self.symbols.get(s).?;
        }
        const str = self.allocator.alloc(u8, s.len) catch @panic("Out of memory");
        @memcpy(str, s);
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .symbol = str };
        self.symbols.put(str, i) catch @panic("Out of memory");
        return i;
    }

    pub fn list(self: *Gc, xs: std.ArrayList(usize)) usize {
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .list = xs };
        return i;
    }

    pub fn ffun(self: *Gc, ff: v.ForeignFunction) usize {
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .ffun = ff };
        return i;
    }

    pub fn fun(self: *Gc, env: *Environment, params: std.ArrayList([]const u8), body: usize) usize {
        const i = self.findUnused() orelse @panic("Out of memory");
        self.headers[i] = .{ .used = true, .marked = false };
        self.values[i] = .{ .fun = v.Function{ .body = body, .env = env, .params = params } };
        return i;
    }
};
