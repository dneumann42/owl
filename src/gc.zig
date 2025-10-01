const std = @import("std");

pub const Gc = struct {
    const Header = struct {
        refs: i32,
        marked: i32,
    };

    allocator: std.mem.Allocator,
    heap: std.ArrayList(u8),
    global: *anyopaque,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){ //
            .allocator = allocator,
            .heap = std.ArrayList(u8),
            .global = null,
        };
    }

    pub fn alloc(self: *Gc, comptime T: type) !*T {
        const total_size = @sizeOf(Header) + @sizeOf(T);
        try self.heap.resize(self.allocator, self.heap.items.len + total_size);
        const ptr: *anyopaque = @ptrFromInt(@intFromPtr(self.heap.items) + total_size);
        const header_ptr: *Header = @ptrCast(ptr);
        header_ptr.* = Header{ .refs = 0, .marked = 0 };
        return @ptrCast(ptr + @sizeOf(Header));
    }

    pub fn getHeader(comptime T: type, payload: *T) *Header {
        const header_ptr: *Header = @ptrFromInt(@intFromPtr(payload) - @sizeOf(Header));
        return header_ptr;
    }
};
