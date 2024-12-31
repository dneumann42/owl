const std = @import("std");
const e = @import("evaluation.zig");
const v = @import("values.zig");
const g = @import("gc.zig");
const a = @import("ast.zig");
const owl_std = @import("base.zig");
const r = @import("reader.zig");

pub const Library = struct {
    gc: *g.Gc,
    env: *v.Environment,
    evaluator: e.Eval,
    allocator: std.mem.Allocator,
    modules: std.StringHashMap(v.Module),

    pub fn init(allocator: std.mem.Allocator) Library {
        // var gc = g.Gc.init(allocator);

        const gc = allocator.create(g.Gc) catch unreachable;
        gc.* = g.Gc.init(allocator);

        const env = v.Environment.init(allocator) catch unreachable;
        return Library{
            .gc = gc, //
            .env = env,
            .evaluator = e.Eval.init(gc),
            .allocator = allocator,
            .modules = std.StringHashMap(v.Module).init(allocator),
        };
    }

    pub fn deinit(self: *Library) void {
        self.gc.deinit();
        self.allocator.destroy(self.gc);
        self.modules.deinit();
        self.env.deinit();
        self.evaluator.deinit();
        owl_std.deinitReadline();
    }

    pub fn getModuleAst(self: *Library, path: []const u8) !*a.Ast {
        var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            std.log.err("File not found '{s}' current working directory '{s}'", .{ path, cwd });
            return err;
        };
        defer file.close();
        const file_content = try file.readToEndAlloc(self.allocator, comptime std.math.maxInt(usize));
        defer self.allocator.free(file_content);

        var reader = r.Reader.init(self.allocator, file_content) catch {
            return error.ParseError;
        };
        defer reader.deinit();
        return switch (reader.read()) {
            .success => |val| val,
            .failure => {
                return error.ParseError;
            },
        };
    }

    pub fn getModuleDependencies(self: *Library, ast: *a.Ast) !std.ArrayList(a.Use) {
        var uses = std.ArrayList(a.Use).init(self.allocator);
        for (ast.block.items) |node| {
            switch (node.*) {
                .use => |use| {
                    try uses.append(use);
                },
                else => {},
            }
        }
        return uses;
    }

    pub fn loadModuleDependencies(self: *Library, path: []const u8, log_values: bool) !void {
        if (self.modules.contains(path)) {
            return;
        }

        const ast = try self.getModuleAst(path);
        defer a.deinit(ast, self.allocator);
        const deps = try self.getModuleDependencies(ast);
        const dir = std.fs.path.dirname(path) orelse "";

        for (deps.items) |use| {
            const dep_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.owl", .{ dir, use.name });
            try self.loadModuleDependencies(dep_path, log_values);
        }

        var iterator = self.modules.valueIterator();
        while (iterator.next()) |module| {
            try self.env.define(module.name, module.value);
        }

        const value = self.evaluator.evalNode(self.env, ast) catch |err| {
            const log = self.evaluator.getErrorLog();
            std.log.err("{any}: {s}\n", .{ err, log });
            return;
        };

        if (log_values) {
            std.log.info("{s}", .{v.toStr(value)});
        }

        const name = std.fs.path.basename(path);
        const slice = name[0 .. name.len - 4];
        try self.modules.put(path, v.Module{ .name = slice, .value = value });
    }

    pub fn installCoreLibrary(self: *Library, path: []const u8) !void {
        const ast = try self.getModuleAst(path);
        const value = self.evaluator.evalNode(self.env, ast) catch |err| {
            const log = self.evaluator.getErrorLog();
            std.log.err("{any}: {s}\n", .{ err, log });
            return;
        };

        var iterator = value.dictionary.keyIterator();
        while (iterator.next()) |key| {
            const val = value.dictionary.get(key.*) orelse continue;
            try self.env.define(key.*.symbol, val);
        }
    }

    pub fn loadEntry(self: *Library, path: []const u8, opts: struct {
        install_core: bool = true,
        install_base: bool = true,
        log_values: bool = false,
    }) !void {
        if (opts.install_core) {
            try self.installCoreLibrary("lib/core.owl");
        }
        if (opts.install_base) {
            owl_std.installBase(self.gc, self.env);
        }
        try self.loadModuleDependencies(path, opts.log_values);
    }
};
