const std = @import("std");

pub fn log_errors(comptime T: type, logs: std.ArrayList(T), opts: struct {
    prefix: ?[]const u8 = "",
}) void {
    for (logs.items) |log| {
        if (opts.prefix) |p| {
            std.log.err("{s}:{d}: {s}\n", .{ p, log.line, log.message });
        } else {
            std.log.err("{d}: {s}\n", .{ log.line, log.message });
        }
    }
}
