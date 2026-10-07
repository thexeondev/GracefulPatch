const Interception = @This();
const MemoryProtection = @import("MemoryProtection.zig");

address: usize,
previous_bytes: [Trampoline.size]u8,

const Trampoline = packed struct(u96) {
    pub const size = 12;

    mov_prefix: u16 = 0xB848,
    address: u64,
    push: u8 = 0x50,
    ret: u8 = 0xC3,
};

pub const Error = MemoryProtection.SwapError;

pub fn replace(address: usize, comptime replacementFn: anytype) Error!Interception {
    var int: Interception = undefined;
    int.address = address;
    @memcpy(&int.previous_bytes, @as(*const [Trampoline.size]u8, @ptrFromInt(address)));

    const trampoline: Trampoline = .{ .address = @intFromPtr(&replacementFn) };

    try MemoryProtection.swapAndWrite(
        address,
        @as([*]const u8, @ptrCast(&trampoline))[0..Trampoline.size],
    );

    return int;
}

pub fn revert(int: *const Interception) Error!void {
    try MemoryProtection.swapAndWrite(int.address, &int.previous_bytes);
}
