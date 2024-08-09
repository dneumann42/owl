const std = @import("std");
const reader = @import("reader.zig");
const term = @import("terminal.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const gc = @import("gc.zig");
const owlStd = @import("base.zig");

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
    const allocator = std.heap.page_allocator;
    const args = try Args.init(allocator);
    defer args.deinit();

    var g = gc.Gc.init(allocator, allocator);
    defer g.deinit();

    var readr = reader.Reader.initLoad(&g, "{ .x 3 }");
    const exp = try readr.readExpression();
    const key = try v.Value.sym(&g, "x");

    var it = exp.dictionary.keyIterator();

    var hasher1 = std.hash.Wyhash.init(0);
    var hasher2 = std.hash.Wyhash.init(0);

    while (it.next()) |k| {
        std.debug.print("KEY: {any} = {any}: {any}\n", .{ k.*, key, k.*.isEql(key) });
        v.hashValue(key, &hasher1);
        v.hashValue(k.*, &hasher2);
        const hash1 = hasher1.final();
        const hash2 = hasher2.final();

        const value = exp.dictionary.get(key);
        _ = value; // autofix
        const value2 = exp.dictionary.get(k.*);
        _ = value2; // autofix
        _ = value; // autofix

        std.debug.print("HERE: {any} = {any}: {any}", .{ hash1, hash2, hash1 == hash2 });
    }

    //    var cli = Cli{ .run_script = null, .new_project = null };
    //
    //    var it = args.iterator();
    //    while (it.has_next()) : (it.next()) {
    //        if (it.is_arg("run")) {
    //            if (!it.has_next()) {
    //                std.debug.print("Missing argument, expected path to script.", .{});
    //                return;
    //            }
    //            cli.run_script = it.get_value();
    //        } else if (it.is_arg("new")) {
    //            std.debug.print("TODO!", .{});
    //            return;
    //        }
    //    }
    //
    //    if (cli.should_run_repl()) {
    //        try repl(allocator);
    //    }
    //
    //    if (cli.run_script) |path| {
    //        try runScript(allocator, path);
    //    }

}

pub fn runScript(allocator: std.mem.Allocator, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, comptime std.math.maxInt(usize));
    defer allocator.free(file_content);

    var g = gc.Gc.init(allocator, allocator);
    defer g.deinit();

    const env = try v.Environment.init(&g);
    owlStd.installBase(env, &g);
    defer env.deinit();

    _ = try e.eval(env, file_content);
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
            try env.set("read-value", try v.Value.nativeFun(env.gc, readValue));
            const val = try e.eval(env, inp_line);
            const s = try val.toString(allocator);
            defer allocator.free(s);
            std.debug.print("{s}\n", .{s});
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

const Args = struct {
    allocator: std.mem.Allocator,
    arguments: []const [:0]u8,

    pub fn init(allocator: std.mem.Allocator) !Args {
        const args = try std.process.argsAlloc(allocator);
        return .{
            .allocator = allocator,
            .arguments = args,
        };
    }

    const ArgsIter = struct {
        idx: usize,
        arguments: []const [:0]u8,

        pub fn next(self: *ArgsIter) void {
            self.idx += 1;
        }

        pub fn is_arg(self: *const ArgsIter, str: []const u8) bool {
            return std.mem.eql(u8, self.get(), str);
        }

        pub fn has_next(self: *const ArgsIter) bool {
            return self.idx + 1 < self.arguments.len;
        }

        pub fn get(self: *const ArgsIter) []const u8 {
            return self.arguments[self.idx];
        }

        pub fn get_value(self: *ArgsIter) []const u8 {
            self.next();
            return self.get();
        }
    };

    pub fn iterator(self: Args) ArgsIter {
        return .{ .idx = 0, .arguments = self.arguments };
    }

    pub fn len(self: Args) usize {
        return self.arguments.len;
    }

    pub fn nth(self: Args, idx: usize) []const u8 {
        if (idx < 0 or idx >= self.arguments.len)
            return "";
        return self.arguments[idx];
    }

    pub fn deinit(self: Args) void {
        std.process.argsFree(self.allocator, self.arguments);
    }
};
