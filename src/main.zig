const std = @import("std");
const reader = @import("reader2.zig");
const term = @import("terminal.zig");
const v = @import("values.zig");
const e = @import("evaluation.zig");
const gc = @import("gc.zig");
const owlStd = @import("base.zig");
const dot = @import("ast_dot.zig");
const ast = @import("ast.zig");

const Cli = struct {
    run_script: ?[]const u8,
    new_project: ?NewProject,
    output_ast: bool,

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

    var cli = Cli{ .run_script = null, .new_project = null, .output_ast = false };

    var it = args.iterator();
    while (it.has_next()) : (it.next()) {
        if (it.is_arg("run")) {
            if (!it.has_next()) {
                std.debug.print("Missing argument, expected path to script.", .{});
                return;
            }
            cli.run_script = it.get_value();
        } else if (it.is_arg("new")) {
            std.debug.print("New is a work in progress, this command will generate projects, librarys and scripts", .{});
            return;
        } else if (it.is_arg("output-ast")) {
            cli.output_ast = true;
        }
    }

    if (cli.should_run_repl()) {
        try runScript(allocator, "scripts/repl2.owl", cli.output_ast);
    }

    if (cli.run_script) |path| {
        try runScript(allocator, path, cli.output_ast);
    }
}

pub fn runScript(allocator: std.mem.Allocator, path: []const u8, output_ast: bool) !void {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, comptime std.math.maxInt(usize));
    defer allocator.free(file_content);

    var g = gc.Gc.init(allocator);
    defer g.deinit();
    owlStd.installBase(&g);

    if (output_ast) {
        var r = reader.Reader.init(g.allocator, file_content) catch {
            return error.ParseError;
        };
        const node = switch (r.read()) {
            .success => |val| val,
            .failure => {
                return error.ParseError;
            },
        };
        try dot.buildAndWriteGraphvizFromAst(g.allocator, node);
        defer ast.deinit(node, g.allocator);
    }

    const val = try e.eval(&g, file_content);
    std.debug.print("{s}\n", .{val.toStr()});
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
