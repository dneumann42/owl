const std = @import("std");
const reader = @import("reader.zig");
const term = @import("terminal.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const gc = @import("gc.zig");

const Cli = struct {
    run_script: ?[]const u8,
    new_project: ?NewProject,

    fn should_run_repl(self: @This()) bool {
        return self.run_script == null;
    }
};

const ProjectKind = enum { Library, Binary };

const NewProject = struct {
    name: []const u8,
    kind: ProjectKind,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var cli = Cli{ .run_script = null, .new_project = null };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "run")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Run is missing argument\n", .{});
                return;
            }
            cli.run_script = args[i];
        } else if (std.mem.eql(u8, arg, "new")) {
            std.debug.print("TODO!", .{});
            return;
        }
    }

    if (cli.should_run_repl()) {
        try repl(allocator);
    }
    if (cli.run_script) |path| {
        try runScript(allocator, path);
    }
}

pub fn runScript(allocator: std.mem.Allocator, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, comptime std.math.maxInt(usize));
    defer allocator.free(file_content);

    var g = gc.Gc.init(allocator, allocator);
    defer g.deinit();

    const env = try v.Environment.init(&g);
    defer env.deinit();

    const val = try e.eval(env, file_content);
    std.debug.print("{any}\n", .{val});
}

pub fn repl(allocator: std.mem.Allocator) !void {
    var g = gc.Gc.init(allocator, allocator);
    defer g.deinit();
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

            const env = try v.Environment.init(&g);
            try env.set("read-value", try v.Value.nfun(env.gc, readValue));
            const val = try e.eval(env, inp_line);

            std.debug.print("{any}\n", .{val});
        }
    }
}

fn readValue(env: *v.Environment, args0: ?*v.Value) *v.Value {
    const args = args0 orelse unreachable;
    const str = v.car(args) orelse unreachable;
    return switch (str.*) {
        v.Value.string => |s| {
            var r = reader.Reader.initLoad(env.gc, s);
            return r.readExpression() catch {
                return str;
            };
        },
        else => str,
    };
}
