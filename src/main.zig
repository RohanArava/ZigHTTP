pub fn main() !void {
    std.debug.print("Type of Request: {s}\n", .{@typeName(ZigHTTP.Request)});
    std.debug.print("Type of Request: {s}\n", .{@typeName(ZigHTTP.Response)});
}

const std = @import("std");

const ZigHTTP = @import("ZigHTTP");
