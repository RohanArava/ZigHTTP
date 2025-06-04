const ParseError = error{ NoResponseLine, UnrecognizedResponseFormat, InvalidHttpVersion, InvalidStatusCode, InvalidContentLength, HeadersTooLarge, ReaderError } || std.mem.Allocator.Error || std.fs.File.ReadError || error{EndOfStream};


pub const Response = struct {
    version: http.Version,
    status: i32,
    description: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.description);

        self.allocator.free(self.body);

        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn getHeader(self: *Response, name: []const u8) ?[]const u8{
        const lowercase_name = self.allocator.alloc(u8, name.len) catch return null;
        defer self.allocator.free(lowercase_name);

        for (name, 0..) |c, i| {
            lowercase_name[i] = std.ascii.toLower(c);
        }

        return self.headers.get(lowercase_name);
    }

    pub fn parse(reader: anytype, allocator: std.mem.Allocator) ParseError!Response{
        var headers_buffer = std.ArrayList(u8).init(allocator);
        defer headers_buffer.deinit();

        const max_headers_size = 8192;

        while (headers_buffer.items.len < max_headers_size) {
            const byte = reader.readByte() catch |err|{
                if (err == error.EndOfStream) break;
                return ParseError.ReaderError;
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

        const response_line = lines.next() orelse return ParseError.NoResponseLine;

        const first_space_pos = std.mem.indexOf(u8, response_line, " ") orelse
            return ParseError.UnrecognizedResponseFormat;

        const remaining_after_pos = response_line[first_space_pos + 1..];
        const second_space_pos = std.mem.indexOf(u8, remaining_after_pos, " ") orelse
            return ParseError.UnrecognizedResponseFormat;
        
        const version_str = response_line[0..first_space_pos];
        const status_str = response_line[first_space_pos + 1..first_space_pos + 1 + second_space_pos];
        const description_str = response_line[first_space_pos + 1 + second_space_pos + 1..];

        const version = parseVersion(version_str) orelse return ParseError.InvalidHttpVersion;
        const status = std.fmt.parseInt(i32, status_str, 10) catch 
            return ParseError.InvalidStatusCode;
        if (status < 100 or status > 599) {
            return ParseError.InvalidStatusCode;
        }
        const description = try allocator.dupe(u8, description_str);
        errdefer allocator.free(description);

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

                body = try allocator.alloc(u8, len);
                try reader.readNoEof(body);
            }
        }

        return Response{
            .version = version,
            .status = status,
            .description = description,
            .headers = headers,
            .body = body,
            .allocator = allocator,
        };
    }
};

fn parseVersion(version_str: []const u8) ?http.Version {
    if (std.mem.eql(u8, version_str, "HTTP/1.1")) return http.Version.HTTP_1_1;
    return null;
}

test "Parse HTTP Version 1.1" {
    try std.testing.expectEqual(http.Version.HTTP_1_1, parseVersion("HTTP/1.1") orelse null);
    try std.testing.expectEqual(null, parseVersion("HTTP/1.0") orelse null);
}

test "Parse HTTP Response With Body" {
    const response_string = "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 26\r\n" ++
        "Server: nginx/1.18.0\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "Date: Wed, 04 Jun 2025 10:30:00 GMT\r\n" ++
        "\r\n" ++
        "{\"message\": \"Hello World\"}";
        
    var stream = std.io.fixedBufferStream(response_string);
    const reader = stream.reader();
    var response = try Response.parse(reader, std.testing.allocator);
    defer response.deinit();
    
    try std.testing.expectEqual(http.Version.HTTP_1_1, response.version);
    try std.testing.expectEqual(@as(i32, 200), response.status);
    try std.testing.expectEqualStrings("OK", response.description);
    try std.testing.expectEqual(26, response.body.len);
    try std.testing.expectEqualStrings("{\"message\": \"Hello World\"}", response.body);
    try std.testing.expectEqualStrings("application/json", response.getHeader("Content-Type").?);
    try std.testing.expectEqualStrings("26", response.getHeader("Content-Length").?);
    try std.testing.expectEqualStrings("nginx/1.18.0", response.getHeader("Server").?);
}

const std = @import("std");
const http = @import("./http.zig");