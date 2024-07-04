const std = @import("std");
const reader = @import("reader.zig");
const term = @import("terminal.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");

pub fn repl() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    term.Terminal.clear();

    const outw = std.io.getStdOut().writer();
    try outw.print(
        \\ ~___~  Owl (0.0.0-dev)
        \\ {{O,o}}  run with 'help' for list of commands
        \\/)___)  enter '?' to show help for repl
        \\  ' '"
    , .{});

    const running = true;

    try outw.print("\n", .{});
    while (running) {
        try outw.print("> ", .{});

        var stdin = std.io.getStdIn().reader();
        const line = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024);
        if (line) |l| {
            const inp_line = std.mem.trimRight(u8, l, "\r\n");

            const env = try v.Environment.init(allocator);
            const val = try e.eval(env, inp_line);

            std.debug.print("{any}\n", .{val});
        }
    }
}

pub fn main() !void {
    try repl();
}
