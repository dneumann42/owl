const std = @import("std");

const r = @import("reader.zig");
const g = @import("gc.zig");
const e = @import("evaluator.zig");
const v = @import("value.zig");

const p = @import("lib/prelude.zig");
const toString = p.toString;
const prelude = p.prelude;

pub const Sushi = struct {
    evaluator: e.Evaluator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var evaluator = try e.Evaluator.init(allocator, .{ .dumpAst = true });
        try evaluator.installLibrary(prelude());
        return @This(){ .evaluator = evaluator, .allocator = allocator };
    }

    pub fn deinit(self: *Sushi) void {
        self.evaluator.deinit();
    }

    pub fn eval(self: *Sushi, code: []const u8) !*v.Value {
        return self.evaluator.evalString(code);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) {
        std.log.info("LEAKED", .{});
    };

    const outw = std.io.getStdOut().writer();

    var s = try Sushi.init(allocator);
    defer s.deinit();

    const value = s.eval(
        \\ (define (add-one x) (+ x 1))
        \\ (echo (add-one 100) x)
    ) catch {
        std.log.err("{s}\n", .{s.evaluator.error_message});
        return;
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const value_string = try toString(value, &s.evaluator.gc, arena.allocator());
    try outw.print("{s}\n", .{value_string});
}
