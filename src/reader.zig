const v = @import("values.zig");

pub fn read() v.Value {
    return v.Value{ .number = 3.1415926 };
}
