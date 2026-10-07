const MemoryProtection = @This();
const std = @import("std");
const mem = std.mem;
const PAGE = std.os.windows.PAGE;

const common = @import("common.zig");
const fatal = common.fatal;

page: PAGE,

pub const rx: MemoryProtection = .{ .page = .{ .EXECUTE_READ = true } };
pub const rwx: MemoryProtection = .{ .page = .{ .EXECUTE_READWRITE = true } };

pub const SwapError = error{ProtectVirtualMemoryFail};

pub fn swap(mp: MemoryProtection, address: usize, bytes: usize) SwapError!MemoryProtection {
    const w = std.os.windows;

    const start_page = mem.alignBackward(usize, address, std.heap.page_size_min);
    const end_page = mem.alignForward(usize, address + bytes, std.heap.page_size_min);
    var start_address: ?*anyopaque = @ptrFromInt(start_page);
    var number_of_bytes = end_page - start_page;

    const current_process: w.HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    var old_page_protection: PAGE = undefined;

    return switch (w.ntdll.NtProtectVirtualMemory(
        current_process,
        &start_address,
        &number_of_bytes,
        mp.page,
        &old_page_protection,
    )) {
        .SUCCESS => .{ .page = old_page_protection },
        else => return error.ProtectVirtualMemoryFail,
    };
}

pub fn swapAndWrite(addr: usize, data: []const u8) SwapError!void {
    const prev: MemoryProtection = try .swap(.rwx, addr, data.len);
    defer _ = prev.swap(addr, data.len) catch {};

    @memcpy(@as([*]u8, @ptrFromInt(addr))[0..data.len], data);
}

pub fn removeVmpWatchdog() !void {
    const w = std.os.windows;

    var ntdll_handle: w.PVOID = undefined;
    switch (w.ntdll.LdrGetDllHandle(
        null,
        null,
        &.initZ(&.{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' }),
        &ntdll_handle,
    )) {
        .SUCCESS => {},
        else => fatal("failed to get ntdll handle", .{}),
    }

    var protect_virtual_memory: w.PVOID = undefined;
    switch (w.ntdll.LdrGetProcedureAddress(
        ntdll_handle,
        &.initZ("NtProtectVirtualMemory"),
        0,
        &protect_virtual_memory,
    )) {
        .SUCCESS => {},
        else => fatal("NtProtectVirtualMemory not found in ntdll", .{}),
    }

    var query_section: w.PVOID = undefined;
    switch (w.ntdll.LdrGetProcedureAddress(
        ntdll_handle,
        &.initZ("NtQuerySection"),
        0,
        &query_section,
    )) {
        .SUCCESS => {},
        else => fatal("NtQuerySection not found in ntdll", .{}),
    }

    const prev: MemoryProtection = try .swap(.rwx, @intFromPtr(protect_virtual_memory), 1);
    defer _ = prev.swap(@intFromPtr(protect_virtual_memory), 1) catch {};

    @as(*align(1) u64, @ptrCast(protect_virtual_memory)).* =
        (@as(*align(1) u64, @ptrCast(query_section)).* & 0xFFFFFF00FFFFFFFF) |
        @as(u64, @as(*align(1) u32, @ptrFromInt(@intFromPtr(query_section) + 4)).* - 1) << 32;
}
