const std = @import("std");
const e = @import("evaluation.zig");
const v = @import("values.zig");
const g = @import("gc.zig");
const a = @import("ast.zig");
const owl_std = @import("base.zig");
const r = @import("reader.zig");

pub const Library = struct {
    gc: g.Gc,
    evaluator: e.Eval,
    allocator: std.mem.Allocator,
    modules: std.ArrayList(v.Module),
    visited_paths: std.ArrayList([]const u8),
    module_asts: std.StringHashMap(*a.Ast),

    pub fn init(allocator: std.mem.Allocator) Library {
        var gc = g.Gc.init(allocator);
        owl_std.installBase(&gc);
        return Library{
            .gc = gc, //
            .evaluator = e.Eval.init(allocator),
            .allocator = allocator,
            .modules = std.ArrayList(v.Module).init(allocator),
            .visited_paths = std.ArrayList([]const u8).init(allocator),
            .module_asts = std.StringHashMap(*a.Ast).init(allocator),
        };
    }

    pub fn isModuleLoaded(self: *Library, name: []const u8) bool {
        for (self.modules) |module| {
            if (std.mem.eql(u8, module.name, name)) {
                return true;
            }
        }
        return false;
    }

    // first parse entry ast, find module uses, for each module check if in load list, if not
    // recursively load the modules

    pub fn getModuleAst(self: *Library, path: []const u8) !*a.Ast {
        var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            std.log.err("File not found '{s}' current working directory '{s}'", .{ path, cwd });
            return err;
        };
        defer file.close();
        const file_content = try file.readToEndAlloc(self.allocator, comptime std.math.maxInt(usize));
        // TODO: need to give the ownership of the source file somewhere
        // probably to the ast, but I need to think about this more
        // defer self.allocator.free(file_content);

        var reader = r.Reader.init(self.allocator, file_content) catch {
            return error.ParseError;
        };
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

    pub fn loadModuleDependencies(self: *Library, path: []const u8) !void {
        if (self.module_asts.contains(path)) {
            return;
        }

        const ast = try self.getModuleAst(path);
        try self.module_asts.put(path, ast);

        const deps = try self.getModuleDependencies(ast);
        const dir = std.fs.path.dirname(path) orelse "";

        for (deps.items) |use| {
            const dep_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.owl", .{ dir, use.name });
            try self.loadModuleDependencies(dep_path);
        }

        for (self.modules.items) |module| {
            try self.gc.env().define(module.name, module.value);
        }

        const value = self.evaluator.evalNode(&self.gc, ast) catch |err| {
            const log = self.evaluator.getErrorLog();
            std.log.err("{any}: {s}\n", .{ err, log });
            return;
        };

        const name = std.fs.path.basename(path);
        const slice = name[0 .. name.len - 4];
        try self.modules.append(v.Module{ .name = slice, .value = value });
    }

    pub fn installCoreLibrary(self: *Library, path: []const u8) !void {
        const ast = try self.getModuleAst(path);
        const value = self.evaluator.evalNode(&self.gc, ast) catch |err| {
            const log = self.evaluator.getErrorLog();
            std.log.err("{any}: {s}\n", .{ err, log });
            return;
        };

        var iterator = value.dictionary.keyIterator();
        while (iterator.next()) |key| {
            const val = value.dictionary.get(key.*) orelse continue;
            try self.gc.env().define(key.*.symbol, val);
        }
    }

    pub fn loadEntry(self: *Library, path: []const u8) !void {
        try self.installCoreLibrary("lib/core.owl");
        try self.loadModuleDependencies(path);
    }
};
