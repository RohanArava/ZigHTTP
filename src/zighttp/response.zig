const ResponseError = error{HttpVersionNotSupported};

pub const Response = struct {
    version: http.Version,
    statusCode: i32,
    statusText: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    const Config = struct {
        version: http.Version = http.Version.HTTP_1_1,
        statusCode: i32 = 200,
        statusText: []const u8 = "OK",
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Response {
        return Response{
            .version = config.version,
            .statusCode = config.statusCode,
            .statusText = try allocator.dupe(u8, config.statusText),
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = try allocator.dupe(u8, ""),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.statusText);

        self.allocator.free(self.body);

        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn setStatusText(self: *Response, statusText: []u8) void {
        self.allocator.free(self.statusText);
        self.statusText = try self.allocator.dupe(u8, statusText);
    }

    pub fn getHeader(self: *const Response, name: []const u8) ?[]const u8 {
        const lowercase_name = self.allocator.alloc(u8, name.len) catch return null;
        defer self.allocator.free(lowercase_name);

        for (name, 0..) |c, i| {
            lowercase_name[i] = std.ascii.toLower(c);
        }

        return self.headers.get(lowercase_name);
    }

    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
        const lowercase_name = try self.allocator.alloc(u8, name.len);
        for (name, 0..) |c, i| {
            lowercase_name[i] = std.ascii.toLower(c);
        }

        if (self.headers.contains(lowercase_name)) {
            const key = self.headers.getKey(lowercase_name) orelse unreachable;
            const val = self.headers.get(lowercase_name) orelse unreachable;
            defer self.allocator.free(key);
            defer self.allocator.free(val);

            _ = self.headers.remove(lowercase_name);
        }

        const val = try self.allocator.dupe(u8, value);

        try self.headers.put(lowercase_name, val);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        self.allocator.free(self.body);
        self.body = try self.allocator.dupe(u8, body);

        const bodyLen = try std.fmt.allocPrint(self.allocator, "{d}", .{body.len});
        defer self.allocator.free(bodyLen);

        try self.setHeader("content-length", bodyLen);
    }

    pub fn toString(self: *Response) ![]u8 {
        var response_buffer = std.ArrayList(u8).init(self.allocator);
        errdefer response_buffer.deinit();

        try response_buffer.writer().print("{s} {} {s}\r\n", .{ "HTTP/1.1", self.statusCode, self.statusText });

        var header_iter = self.headers.iterator();
        while (header_iter.next()) |entry| {
            try response_buffer.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        try response_buffer.writer().writeAll("\r\n");
        try response_buffer.writer().print("{s}", .{self.body});

        return response_buffer.toOwnedSlice();
    }
};

test "Initialize Default Response" {
    const allocator = std.testing.allocator;

    var resp = try Response.init(allocator, .{});
    defer resp.deinit();

    try std.testing.expectEqual(http.Version.HTTP_1_1, resp.version);
    try std.testing.expectEqual(200, resp.statusCode);
    try std.testing.expectEqualStrings("OK", resp.statusText);
    try std.testing.expectEqual(0, resp.headers.count());
    try std.testing.expectEqualStrings("", resp.body);
}

test "Initialize Response With Config" {
    const allocator = std.testing.allocator;

    var resp = try Response.init(allocator, .{ .statusCode = 404, .statusText = "Not Found" });
    defer resp.deinit();

    try std.testing.expectEqual(http.Version.HTTP_1_1, resp.version);
    try std.testing.expectEqual(404, resp.statusCode);
    try std.testing.expectEqualStrings("Not Found", resp.statusText);
    try std.testing.expectEqual(0, resp.headers.count());
    try std.testing.expectEqualStrings("", resp.body);
}

test "Set Response Headers" {
    const allocator = std.testing.allocator;

    var resp = try Response.init(allocator, .{});
    defer resp.deinit();

    try resp.setHeader("content-length", "20");
    try resp.setHeader("X-Foo", "Bar");

    try std.testing.expectEqualStrings("20", resp.getHeader("Content-Length") orelse "");
    try std.testing.expectEqualStrings("Bar", resp.getHeader("X-Foo") orelse "");

    try resp.setHeader("X-Foo", "BarBar");

    try std.testing.expectEqualStrings("BarBar", resp.getHeader("X-Foo") orelse "");
}

test "Set Response Body" {
    const allocator = std.testing.allocator;

    var resp = try Response.init(allocator, .{});
    defer resp.deinit();

    const body = "Hellow";

    try resp.setBody(body);

    const bodyLen = try std.fmt.allocPrint(allocator, "{d}", .{body.len});
    defer allocator.free(bodyLen);

    try std.testing.expectEqualStrings(bodyLen, resp.getHeader("Content-Length") orelse "");
    try std.testing.expectEqual(body.len, resp.body.len);
    try std.testing.expectEqualStrings(body, resp.body);
}

test "Response To String" {
    const allocator = std.testing.allocator;

    const responseString = "HTTP/1.1 201 Created\r\n" ++
        "content-type: application/json\r\n" ++
        "location: http://example.com/users/123\r\n" ++
        "content-length: 6\r\n" ++
        "\r\n" ++
        "Hellow";
    
    var resp = try Response.init(allocator, .{ .statusCode = 201, .statusText = "Created" });
    defer resp.deinit();

    try resp.setHeader("content-type", "application/json");
    try resp.setHeader("location", "http://example.com/users/123");
    try resp.setBody("Hellow");

    const responseStringActual = try resp.toString();
    defer allocator.free(responseStringActual);
    
    try std.testing.expectEqualStrings(responseString, responseStringActual);
}

const std = @import("std");
const http = @import("./http.zig");
