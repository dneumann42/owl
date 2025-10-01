const std = @import("std");

pub const Value = union(enum) { //
    Symbol: []const u8,
    Number: f64,
    Boolean: bool,
    List: struct { value: *Value, next: *Value },
    Dict: struct { value: *Value, key: *Value, next: *Value },
};

pub fn isEqual(a: *Value, b: *Value) bool {
    if (std.meta.Tag(a) != std.meta.Tag(b)) {
        return false;
    }
    return switch (a) {
        .Boolean => |av| av == b.Boolean,
        .Number => |nv| nv == b.Number,
        .Symbol => |sv| sv == b.Symbol,
        // TODO: need to make up my mind about collections
        .List => false,
        .Dict => false,
    };
}
