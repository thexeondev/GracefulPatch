const std = @import("std");
const mem = std.mem;
const Thread = std.Thread;

const common = @import("common.zig");
const fatal = common.fatal;

const MemoryProtection = @import("MemoryProtection.zig");
const Interception = @import("Interception.zig");
const il2cpp = @import("il2cpp.zig");

extern "kernel32" fn AllocConsole() callconv(.winapi) void;

pub export fn DllMain(
    _: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    _: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL {
    if (reason == 1) { // DLL_PROCESS_ATTACH
        init() catch |err|
            fatal("failed to initialize: {t}", .{err});
    }

    return .TRUE;
}

fn init() !void {
    try disableMhyprot();
    const is_wine = try detectWine();
    if (is_wine) try disableSignatureCheck();

    var patcher: Thread = try .spawn(.{}, runPatcherTask, .{});
    patcher.detach();
}

const offsets = .{
    .sec_engine_init = 0xF8F80, // UnityPlayer.dll
    .il2cpp_initialized = 0xB225FC0,
    .il2cpp_string_new = 0xAA8680,
    .il2cpp_array_new_specific = 0xBA99E0,
    .byte_array_type = 0xB227808,
    .sdk_public_key_xml = 0xB3B7A00,
    .@"Foundation.Assets::SetLoginSettingByJson" = 0x4E42220,
    .@"MiHoYo.SDK.ResourceUtil::LoadJsonString" = 0x6F973C0,
    .@"Foundation.RSAKey::get_publicRSAKey" = 0x1A48180,
};

fn disableMhyprot() !void {
    const w = std.os.windows;

    var unity_player_handle: w.PVOID = undefined;
    switch (w.ntdll.LdrLoadDll(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'U', 'n', 'i', 't', 'y', 'P', 'l', 'a', 'y', 'e', 'r', '.', 'd', 'l', 'l' }),
        &unity_player_handle,
    )) {
        .SUCCESS => {},
        else => fatal("failed to load UnityPlayer.dll", .{}),
    }

    try MemoryProtection.removeVmpWatchdog();
    try MemoryProtection.swapAndWrite(
        @intFromPtr(unity_player_handle) + offsets.sec_engine_init,
        &.{0xC3},
    );
}

fn runPatcherTask() void {
    const w = std.os.windows;
    AllocConsole();

    var assembly_handle: w.PVOID = undefined;
    switch (w.ntdll.LdrLoadDll(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'G', 'a', 'm', 'e', 'A', 's', 's', 'e', 'm', 'b', 'l', 'y', '.', 'd', 'l', 'l' }),
        &assembly_handle,
    )) {
        .SUCCESS => {},
        else => fatal("failed to load GameAssembly.dll", .{}),
    }

    base = @intFromPtr(assembly_handle);
    const il2cpp_initialized: *const u8 = @ptrFromInt(base + offsets.il2cpp_initialized);
    while (il2cpp_initialized.* != 1) delayExecution(100);

    il2cpp_allocator = .{
        .byte_array_type = @as(**anyopaque, @ptrFromInt(base + offsets.byte_array_type)).*,
        .newArray = @ptrFromInt(base + offsets.il2cpp_array_new_specific),
        .newString = @ptrFromInt(base + offsets.il2cpp_string_new),
    };

    patchGameAssembly() catch |err|
        fatal("failed to patch GameAssembly: {t}", .{err});
}

/// Populated by `runPatcherTask`
var base: usize = undefined;
var il2cpp_allocator: il2cpp.Allocator = undefined;

var set_login_setting_by_json: Interception = undefined;

const sdk_public_key = @embedFile("config/sdk_public_key.xml");

fn patchGameAssembly() !void {
    try MemoryProtection.removeVmpWatchdog();

    set_login_setting_by_json = try .replace(
        base + offsets.@"Foundation.Assets::SetLoginSettingByJson",
        setLoginSettingToEmbeddedJson,
    );

    _ = try Interception.replace(
        base + offsets.@"MiHoYo.SDK.ResourceUtil::LoadJsonString",
        loadCustomServerPcJson,
    );

    _ = try Interception.replace(
        base + offsets.@"Foundation.RSAKey::get_publicRSAKey",
        getCustomServerPublicKey,
    );

    const sdk_public_key_ptr: **const il2cpp.String =
        @ptrFromInt(base + offsets.sdk_public_key_xml);
    sdk_public_key_ptr.* = .initZ(&il2cpp_allocator, sdk_public_key);
}

const login_setting_json = @embedFile("config/login_setting.json");

fn setLoginSettingToEmbeddedJson(_: *anyopaque) callconv(.c) void {
    set_login_setting_by_json.revert() catch |err|
        fatal("failed to revert SetLoginSettingByJson: {t}", .{err});

    const setLoginSettingByJson: *const fn (*const il2cpp.String) callconv(.c) void =
        @ptrFromInt(set_login_setting_by_json.address);

    setLoginSettingByJson(.initZ(&il2cpp_allocator, login_setting_json));

    MemoryProtection.swapAndWrite(set_login_setting_by_json.address, &.{0xC3}) catch |err|
        fatal("failed to disable SetLoginSettingByJson: {t}", .{err});
}

const server_pc_path = std.unicode.utf8ToUtf16LeStringLiteral("Config/server_pc.json");
const server_pc_json = @embedFile("config/server_pc.json");

fn loadCustomServerPcJson(path: *il2cpp.String) callconv(.c) *const il2cpp.String {
    return if (mem.eql(u16, path.chars(), server_pc_path))
        .initZ(&il2cpp_allocator, server_pc_json)
    else
        .initZ(&il2cpp_allocator, "");
}

const server_public_key = @embedFile("config/server_public_key.xml");

fn getCustomServerPublicKey() callconv(.c) *il2cpp.ByteArray {
    return .dupe(&il2cpp_allocator, server_public_key);
}

const windows_intervals_per_ms = @divExact(std.time.ns_per_ms, 100);

fn delayExecution(delay_ms: u63) void {
    const w = std.os.windows;

    var delay_interval: w.LARGE_INTEGER = -@as(i64, delay_ms) * windows_intervals_per_ms;
    _ = w.ntdll.NtDelayExecution(
        .FALSE, // Alertable
        &delay_interval,
    );
}

fn detectWine() !bool {
    const w = std.os.windows;

    var ntdll_dll: w.PVOID = undefined;
    switch (w.ntdll.LdrLoadDll(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' }),
        &ntdll_dll,
    )) {
        .SUCCESS => {},
        else => return error.NtdllLoadFailed,
    }

    var proc_address: w.PVOID = undefined;
    return switch (w.ntdll.LdrGetProcedureAddress(
        ntdll_dll,
        &.initZ("wine_get_version"),
        0,
        &proc_address,
    )) {
        .SUCCESS => true,
        else => false,
    };
}

fn disableSignatureCheck() !void {
    const w = std.os.windows;

    var winthrust: w.PVOID = undefined;
    switch (w.ntdll.LdrLoadDll(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'w', 'i', 'n', 't', 'r', 'u', 's', 't', '.', 'd', 'l', 'l' }),
        &winthrust,
    )) {
        .SUCCESS => {},
        else => return,
    }

    var proc_address: w.PVOID = undefined;
    for (@as([]const [:0]const u8, &.{
        "CryptCATAdminEnumCatalogFromHash",
        "CryptCATCatalogInfoFromContext",
        "CryptCATAdminReleaseCatalogContext",
    })) |proc_name| switch (w.ntdll.LdrGetProcedureAddress(
        winthrust,
        &.initZ(proc_name),
        0,
        &proc_address,
    )) {
        .SUCCESS => try MemoryProtection.swapAndWrite(
            @intFromPtr(proc_address),
            &.{ 0xB8, 0x01, 0x00, 0x00, 0x00, 0xC3 },
        ),
        else => continue,
    };
}
