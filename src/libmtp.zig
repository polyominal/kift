const std = @import("std");
const c = std.c;

// mapped from LIBMTP_file_struct in libmtp.h.in
pub const LIBMTP_file_t = extern struct {
    item_id: u32,
    parent_id: u32,
    storage_id: u32,
    filename: [*c]u8,
    filesize: u64,
    modificationdate: c.time_t,
    filetype: c_int,
    next: [*c]LIBMTP_file_t,
};

// mapped from LIBMTP_folder_struct in libmtp.h.in
pub const LIBMTP_folder_t = extern struct {
    folder_id: u32,
    parent_id: u32,
    storage_id: u32,
    name: [*c]u8,
    sibling: [*c]LIBMTP_folder_t,
    child: [*c]LIBMTP_folder_t,
};

comptime {
    std.debug.assert(@sizeOf(LIBMTP_file_t) == 56);
    std.debug.assert(@offsetOf(LIBMTP_file_t, "next") == 48);
    std.debug.assert(@sizeOf(LIBMTP_folder_t) == 40);
}

pub const LIBMTP_mtpdevice_t = opaque {};

// libmtp.h.in:532 and :544: raw devices are a complete struct array
// (Detect_Raw_Devices fills an array base, examples index rawdevices[i]).
pub const LIBMTP_device_entry_t = extern struct {
    vendor: [*c]u8,
    vendor_id: u16,
    product: [*c]u8,
    product_id: u16,
    device_flags: u32,
};

pub const LIBMTP_raw_device_t = extern struct {
    device_entry: LIBMTP_device_entry_t,
    bus_location: u32,
    devnum: u8,
};

pub extern var LIBMTP_debug: c_int;

pub extern fn LIBMTP_Init() void;
pub extern fn LIBMTP_Detect_Raw_Devices(devices: [*c][*c]LIBMTP_raw_device_t, numdevs: [*c]c_int) c_int;
pub extern fn LIBMTP_Open_Raw_Device_Uncached(raw_device: [*c]LIBMTP_raw_device_t) ?*LIBMTP_mtpdevice_t;
pub extern fn LIBMTP_Release_Device(device: ?*LIBMTP_mtpdevice_t) void;
pub extern fn LIBMTP_FreeMemory(ptr: ?*anyopaque) void;
pub extern fn LIBMTP_Dump_Device_Info(device: ?*LIBMTP_mtpdevice_t) void;
pub extern fn LIBMTP_Get_Manufacturername(device: ?*LIBMTP_mtpdevice_t) [*c]u8;
pub extern fn LIBMTP_Get_Modelname(device: ?*LIBMTP_mtpdevice_t) [*c]u8;
pub extern fn LIBMTP_Get_Serialnumber(device: ?*LIBMTP_mtpdevice_t) [*c]u8;
pub extern fn LIBMTP_Get_Friendlyname(device: ?*LIBMTP_mtpdevice_t) [*c]u8;
pub extern fn LIBMTP_Get_Batterylevel(device: ?*LIBMTP_mtpdevice_t, max: [*c]u8, current: [*c]u8) c_int;
pub extern fn LIBMTP_Get_Files_And_Folders(
    device: *LIBMTP_mtpdevice_t,
    storage_id: u32,
    leaf: u32,
    files: [*c][*c]LIBMTP_file_t,
    folders: [*c][*c]LIBMTP_folder_t,
) [*c]LIBMTP_file_t;
pub extern fn LIBMTP_Dump_Errorstack(device: ?*LIBMTP_mtpdevice_t) void;

test "libmtp links and inits" {
    LIBMTP_Init();
    LIBMTP_debug = 1;
}
