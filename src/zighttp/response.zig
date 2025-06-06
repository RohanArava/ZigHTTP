pub const Response = struct {
    version: []const u8,
    statusCode: i32,
    statusText: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Response {
        return Response{
            .version = "HTTP/1.1",
            .statusCode = 200,
            .statusText = "OK", 
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Response) void {
        self.headers.deinit();
    }
    
    pub fn setVersion(self: *Response, version: []const u8) void {
        self.version = version;
    }
   
    pub fn setStatusCode(self: *Response, statusCode: i32) void {
        self.statusCode = statusCode;
    }
    
    pub fn setStatusText(self: *Response, statusText: []const u8) void {
        self.statusText = statusText;
    }
    
    pub fn setHeader(self: *Response, name: []const u8) HeaderSetter {
        return HeaderSetter{
            .response = self,
            .name = name,
        };
    }
    
    pub const HeaderSetter = struct {
        response: *Response,
        name: []const u8,
        
        pub fn value(self: HeaderSetter, val: []const u8) !void {
            try self.response.headers.put(self.name, val);
        }
    };
    
    pub fn setBody(self: *Response, body: []const u8) void {
        self.body = body;
    }
    
    pub fn toString(self: *Response, allocator: std.mem.Allocator) ![]u8 {
        var response_buffer = std.ArrayList(u8).init(allocator);
        errdefer response_buffer.deinit(); 
        
        try response_buffer.writer().print("{s} {} {s}\r\n", .{ self.version, self.statusCode, self.statusText });
        
        var header_iter = self.headers.iterator();
        while (header_iter.next()) |entry| {
            try response_buffer.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        
        try response_buffer.writer().print("\r\n");
        try response_buffer.writer().print("{s}", .{self.body});
        
        return response_buffer.toOwnedSlice();
    }
};

const std = @import("std");
