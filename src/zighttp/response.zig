pub const Response = struct {
    version: http.Version,
    statusCode: i32,
    statusText: []u8,
    headers: std.StringHashMap([]const u8),
    body: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Response {
        return Response{
            .version = http.Version.HTTP_1_1,
            .statusCode = 200,
            .statusText = try allocator.dupe(u8, "OK"),
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

    pub fn setVersion(self: *Response, version: http.Version) void {
        if (version == http.Version.HTTP_1_1)
            self.version = version;
    }

    pub fn setStatusCode(self: *Response, statusCode: i32) void {
        self.statusCode = statusCode;
    }

    pub fn setStatusText(self: *Response, statusText: []const u8) !void {
        self.allocator.free(self.statusText);
        self.statusText = try self.allocator.dupe(u8, statusText);
    }

    pub fn setHeaderField(self: *Response, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);

        try self.headers.put(key_copy, value_copy);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        self.allocator.free(self.body);
        self.body = try self.allocator.dupe(u8, body);
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

test "Initialize default Response and set fields" {
    var allocator = std.testing.allocator;

    var resp = try Response.init(allocator);
    defer resp.deinit();

    try std.testing.expectEqual(http.Version.HTTP_1_1, resp.version);
    try std.testing.expectEqual(@as(i32, 200), resp.statusCode);
    try std.testing.expect(std.mem.eql(u8, resp.statusText, "OK"));
    try std.testing.expectEqual(@as(usize, 0), resp.headers.count());
    try std.testing.expect(std.mem.eql(u8, resp.body, ""));

    // Test setStatusCode
    resp.setStatusCode(404);
    try std.testing.expectEqual(@as(i32, 404), resp.statusCode);

    // Test setStatusText
    try resp.setStatusText("Not Found");
    try std.testing.expect(std.mem.eql(u8, resp.statusText, "Not Found"));

    // Test setHeaderField
    try resp.setHeaderField("Content-Type", "text/plain");
    try std.testing.expectEqual(@as(usize, 1), resp.headers.count());
    const ct = resp.headers.get("Content-Type");
    try std.testing.expect(ct != null);
    try std.testing.expect(std.mem.eql(u8, ct.?, "text/plain"));

    // Test adding another header
    try resp.setHeaderField("ETag", "84238dfc");
    try std.testing.expectEqual(@as(usize, 2), resp.headers.count());
    const etag = resp.headers.get("ETag");
    try std.testing.expect(etag != null);
    try std.testing.expect(std.mem.eql(u8, etag.?, "84238dfc"));

    // Test setBody
    try resp.setBody("Hello, Zig!");
    try std.testing.expect(std.mem.eql(u8, resp.body, "Hello, Zig!"));

    // Test toString
    const response_str = try resp.toString();
    defer allocator.free(response_str);

    // Should contain status line, headers, blank line, and body
    try std.testing.expect(std.mem.containsAtLeast(u8, response_str, 1, "HTTP/1.1 404 Not Found\r\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, response_str, 1, "Content-Type: text/plain\r\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, response_str, 1, "ETag: 84238dfc\r\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, response_str, 1, "\r\nHello, Zig!"));
}

const std = @import("std");
const http = @import("./http.zig");
