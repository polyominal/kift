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
