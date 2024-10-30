const std = @import("std");
const r = @import("reader.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const expect = std.testing.expect;
const expectEq = std.testing.expectEqual;
const gc = @import("gc.zig");

const allocator = std.heap.page_allocator;

test "gc" {
    var G = gc.Gc.init(allocator);
    const n = try G.create(.{ .number = 42.0 });
    try expect(n.number == 42.0);
}

test "evaluating numbers" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G, "123");
    try expect(value.number == 123.0);
}

test "evaluating symbols" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const n = G.num(123.0);
    try G.env().set("hello", n);
    const s = G.sym("hello");
    const value = try e.evaluate(&G, s);
    try expect(value.number == 123.0);
}

test "evaluating math functions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    try expectEq(3, (try e.eval(&G, "1 + 3 + -1")).toNumber());
    try expectEq(12, (try e.eval(&G, "3 * 4")).toNumber());
    try expectEq(1.0 / 3.0, (try e.eval(&G, "1 / 3")).toNumber());
}

test "evaluating code" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const n = G.num(123.0);
    try G.env().set("hello", n);

    const value = try e.eval(&G, "hello");
    try expect(value.number == 123.0);
}

test "evaluating binary expressions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G, "1 + 2");
    try expect(value.number == 3.0);
}

test "evaluating function definitions and calls" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G,
        \\fun a(y) y + 1 end
        \\a(9)
    );
    try expect(value.number == 10.0);
}

test "evaluating function definitions and lambdas" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G,
        \\fun x1(y) y + 1 end
        \\x2 := fun(y) y + 1 end
        \\x3 := fn(y) y + 1
        \\x1(1) + x2(1) + x3(1)
    );
    try expect(value.number == 6.0);
}

test "evaluating recursive functions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G,
        \\fun factorial(n)
        \\  if n < 2 then
        \\    1
        \\  else
        \\    n * factorial(n - 1)
        \\  end
        \\end
        \\factorial(5)
    );
    try expect(value.number == 120);
}

test "evaluating functions out of order" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G,
        \\fun a() b() end
        \\fun b() 69 end
        \\a()
    );
    try expect(value.number == 69);
}

test "evaluating passing functions" {
    var G = gc.Gc.init(allocator);
    defer G.deinit();
    const value = try e.eval(&G,
        \\fun a(b) b() end
        \\fun b() 69 end
        \\a(b)
    );
    try expect(value.number == 69);
}
