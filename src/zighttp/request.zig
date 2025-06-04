const ParseError = error{ NoRequestLine, MethodNotFound, UnrecognizedRequestFormat, InvalidHttpVersion, InvalidContentLength, HeadersTooLarge, BodyTooLarge, ReaderError } || std.mem.Allocator.Error || std.fs.File.ReadError || error{EndOfStream};

pub const Request = struct {
    method: http.Method,
    target: []const u8,
    version: http.Version,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.target);

        self.allocator.free(self.body);

        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn getHeader(self: *const Request, name: []const u8) ?[]const u8 {
        const lowercase_name = self.allocator.alloc(u8, name.len) catch return null;
        defer self.allocator.free(lowercase_name);

        for (name, 0..) |c, i| {
            lowercase_name[i] = std.ascii.toLower(c);
        }

        return self.headers.get(lowercase_name);
    }

    pub fn parse(reader: anytype, allocator: std.mem.Allocator) ParseError!Request {
        var headers_buffer = std.ArrayList(u8).init(allocator);
        defer headers_buffer.deinit();

        const max_headers_size = 8192;

        while (headers_buffer.items.len < max_headers_size) {
            const byte = reader.readByte() catch |err| switch (err) {
                error.EndOfStream => break,
                // else => return ParseError.ReaderError
            };

            try headers_buffer.append(byte);

            // Check for \r\n\r\n pattern
            if (headers_buffer.items.len >= 4) {
                const last_four = headers_buffer.items[headers_buffer.items.len - 4 ..];
                if (std.mem.eql(u8, last_four, "\r\n\r\n")) {
                    break;
                }
            }
        } else {
            return ParseError.HeadersTooLarge;
        }

        const headers_str = headers_buffer.items[0 .. headers_buffer.items.len - 4];
        var lines = std.mem.tokenizeSequence(u8, headers_str, "\r\n");

        const request_line = lines.next() orelse return ParseError.NoRequestLine;

        var tokens = std.mem.tokenizeSequence(u8, request_line, " ");
        const method_str = tokens.next() orelse return ParseError.UnrecognizedRequestFormat;
        const target_str = tokens.next() orelse return ParseError.UnrecognizedRequestFormat;
        const version_str = tokens.next() orelse return ParseError.UnrecognizedRequestFormat;

        if (tokens.next()) |_| return ParseError.UnrecognizedRequestFormat;

        const method = parseMethod(method_str) orelse return ParseError.MethodNotFound;
        const version = parseVersion(version_str) orelse return ParseError.InvalidHttpVersion;
        const target = try allocator.dupe(u8, target_str);
        errdefer allocator.free(target);

        var headers = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var iter = headers.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            headers.deinit();
        }

        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
                const key = std.mem.trim(u8, line[0..colon_pos], " \t");
                const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");

                const key_copy = try allocator.dupe(u8, key);
                for (key_copy) |*c| {
                    c.* = std.ascii.toLower(c.*);
                }
                const value_copy = try allocator.dupe(u8, value);
                try headers.put(key_copy, value_copy);
            }
        }

        const content_length: ?usize = if (headers.get("content-length")) |content_length|
            std.fmt.parseInt(usize, content_length, 10) catch return ParseError.InvalidContentLength
        else
            null;

        var body: []u8 = &[_]u8{};
        if (content_length) |len| {
            if (len > 0) {
                const max_body_size = 10 * 1024 * 1024; // 10MB limit
                if (len > max_body_size) return ParseError.BodyTooLarge;

                body = try allocator.alloc(u8, len);
                try reader.readNoEof(body);
            }
        }

        return Request{
            .method = method,
            .target = target,
            .version = version,
            .headers = headers,
            .body = body,
            .allocator = allocator,
        };
    }
};

fn parseMethod(method_str: []const u8) ?http.Method {
    if (std.mem.eql(u8, method_str, "GET")) return http.Method.GET;
    if (std.mem.eql(u8, method_str, "POST")) return http.Method.POST;
    if (std.mem.eql(u8, method_str, "PUT")) return http.Method.PUT;
    if (std.mem.eql(u8, method_str, "DELETE")) return http.Method.DELETE;
    if (std.mem.eql(u8, method_str, "PATCH")) return http.Method.PATCH;
    if (std.mem.eql(u8, method_str, "HEAD")) return http.Method.HEAD;
    if (std.mem.eql(u8, method_str, "OPTIONS")) return http.Method.OPTIONS;
    return null;
}

fn parseVersion(version_str: []const u8) ?http.Version {
    if (std.mem.eql(u8, version_str, "HTTP/1.1")) return http.Version.HTTP_1_1;
    return null;
}

test "Parse HTTP Version 1.1" {
    try std.testing.expectEqual(http.Version.HTTP_1_1, parseVersion("HTTP/1.1") orelse null);
    try std.testing.expectEqual(null, parseVersion("HTTP/1.0") orelse null);
}

test "Parse HTTP Method" {
    try std.testing.expectEqual(http.Method.GET, parseMethod("GET") orelse null);
    try std.testing.expectEqual(http.Method.POST, parseMethod("POST") orelse null);
    try std.testing.expectEqual(http.Method.PUT, parseMethod("PUT") orelse null);
    try std.testing.expectEqual(http.Method.DELETE, parseMethod("DELETE") orelse null);
    try std.testing.expectEqual(http.Method.PATCH, parseMethod("PATCH") orelse null);
    try std.testing.expectEqual(http.Method.HEAD, parseMethod("HEAD") orelse null);
    try std.testing.expectEqual(http.Method.OPTIONS, parseMethod("OPTIONS") orelse null);
    try std.testing.expectEqual(null, parseMethod("CONNECT") orelse null);
}

test "Parse HTTP Requests Without Body" {
    const request_string = "GET /hello HTTP/1.1\r\n" ++
        "Host: localhost:3668\r\n" ++
        "User-Agent: curl/7.81.0\r\n" ++
        "Accept: */*\r\n" ++
        "\r\n";

    var stream = std.io.fixedBufferStream(request_string);
    const reader = stream.reader();
    var request = try Request.parse(reader, std.testing.allocator);
    defer request.deinit();

    try std.testing.expectEqual(http.Method.GET, request.method);
    try std.testing.expectEqual(http.Version.HTTP_1_1, request.version);
    try std.testing.expectEqualStrings("/hello", request.target);
    try std.testing.expectEqual(0, request.body.len);
    try std.testing.expectEqualStrings("*/*", request.getHeader("Accept").?);
}

test "Parse HTTP Requests With Body" {
    const request_string = "POST / HTTP/1.1\r\n" ++
        "content-length: 9\r\n" ++
        "accept-encoding: gzip, deflate, br\r\n" ++
        "Accept: */*\r\n" ++
        "User-Agent: Thunder Client (https://www.thunderclient.com)\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Host: localhost:3668\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "Hello bro";

    var stream = std.io.fixedBufferStream(request_string);
    const reader = stream.reader();
    var request = try Request.parse(reader, std.testing.allocator);
    defer request.deinit();

    try std.testing.expectEqual(http.Method.POST, request.method);
    try std.testing.expectEqual(http.Version.HTTP_1_1, request.version);
    try std.testing.expectEqualStrings("/", request.target);
    try std.testing.expectEqual(9, request.body.len);
    try std.testing.expectEqualStrings("Hello bro", request.body);
    try std.testing.expectEqualStrings("text/plain", request.getHeader("Content-Type").?);
    try std.testing.expectEqualStrings("9", request.getHeader("Content-Length").?);
}

const std = @import("std");
const http = @import("./http.zig");
