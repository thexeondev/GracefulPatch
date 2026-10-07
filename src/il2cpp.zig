pub const Allocator = struct {
    byte_array_type: *anyopaque,
    newArray: *const fn (*anyopaque, u32) callconv(.c) *ByteArray,
    newString: *const fn ([*:0]const u8) callconv(.c) *const String,
};

pub const String = opaque {
    pub fn initZ(allocator: *const Allocator, content: [*:0]const u8) *const String {
        return allocator.newString(content);
    }

    pub fn chars(string: *const String) []const u16 {
        const len: *const u32 = @ptrFromInt(@intFromPtr(string) + 16);
        const ptr: [*]const u16 = @ptrFromInt(@intFromPtr(string) + 20);
        return ptr[0..len.*];
    }
};

pub const ByteArray = struct {
    pub fn alloc(allocator: *const Allocator, n: u32) *ByteArray {
        return allocator.newArray(allocator.byte_array_type, n);
    }

    pub fn slice(array: *ByteArray) []u8 {
        const len: *const u32 = @ptrFromInt(@intFromPtr(array) + 24);
        const ptr: [*]u8 = @ptrFromInt(@intFromPtr(array) + 32);
        return ptr[0..len.*];
    }

    pub fn dupe(allocator: *const Allocator, bytes: []const u8) *ByteArray {
        const byte_array: *ByteArray = .alloc(allocator, @intCast(bytes.len));
        @memcpy(byte_array.slice(), bytes);
        return byte_array;
    }
};
