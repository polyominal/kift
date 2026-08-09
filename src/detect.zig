const std = @import("std");
const log = std.log.scoped(.detect);
const libmtp = @import("libmtp.zig");

fn cstr(ptr: [*c]u8) []const u8 {
    return if (ptr) |p| std.mem.span(p) else "(null)";
}

fn dump_and_clear(device: ?*libmtp.LIBMTP_mtpdevice_t) void {
    libmtp.LIBMTP_Dump_Errorstack(device);
    libmtp.LIBMTP_Clear_Errorstack(device);
}

pub fn main() !void {
    libmtp.LIBMTP_Init();
    libmtp.LIBMTP_debug = 1;

    var rawdevices: [*c]libmtp.LIBMTP_raw_device_t = null;
    var numrawdevices: c_int = 0;
    const err = libmtp.LIBMTP_Detect_Raw_Devices(&rawdevices, &numrawdevices);
    if (err != 0 or numrawdevices == 0) {
        log.err("no MTP devices found (err={d})", .{err});
        dump_and_clear(null);
        return;
    }

    log.info("found {d} raw device(s)", .{numrawdevices});
    for (0..@intCast(numrawdevices)) |i| {
        const raw = &rawdevices[i];
        log.info("raw[{d}]: bus={d} devnum={d} vendor={s} product={s}", .{
            i,
            raw.bus_location,
            raw.devnum,
            cstr(raw.device_entry.vendor),
            cstr(raw.device_entry.product),
        });

        const device = libmtp.LIBMTP_Open_Raw_Device_Uncached(raw) orelse {
            log.err("failed to open device", .{});
            continue;
        };
        defer libmtp.LIBMTP_Release_Device(device);

        log.info("device: {s} / {s}", .{
            cstr(libmtp.LIBMTP_Get_Manufacturername(device)),
            cstr(libmtp.LIBMTP_Get_Modelname(device)),
        });
        log.info("serial: {s}  friendlyname: {s}", .{
            cstr(libmtp.LIBMTP_Get_Serialnumber(device)),
            cstr(libmtp.LIBMTP_Get_Friendlyname(device)),
        });

        var max_batt: u8 = 0;
        var cur_batt: u8 = 0;
        if (libmtp.LIBMTP_Get_Batterylevel(device, &max_batt, &cur_batt) != 0) {
            log.warn("battery level unsupported", .{});
            dump_and_clear(device);
        } else {
            log.info("battery: {d}/{d}", .{ cur_batt, max_batt });
        }

        if (libmtp.LIBMTP_Get_Storage(device, libmtp.LIBMTP_STORAGE_SORTBY_NOTSORTED) == -1) {
            log.err("failed to enumerate storage", .{});
            dump_and_clear(device);
            return;
        }
        var storage = device.storage;
        while (storage) |s| {
            log.info("storage id={d}: {s}  capacity={d} free={d}", .{
                s.id,
                cstr(s.StorageDescription),
                s.MaxCapacity,
                s.FreeSpaceInBytes,
            });
            storage = s.next;
        }

        log.info("--- full device info ---", .{});
        libmtp.LIBMTP_Dump_Device_Info(device);
    }

    libmtp.LIBMTP_FreeMemory(rawdevices);
}
