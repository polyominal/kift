const std = @import("std");
const libmtp = @import("libmtp.zig");

fn cstr(ptr: [*c]u8) []const u8 {
    return if (ptr) |p| std.mem.span(p) else "(null)";
}

pub fn main() !void {
    libmtp.LIBMTP_Init();
    libmtp.LIBMTP_debug = 1;

    var rawdevices: [*c]libmtp.LIBMTP_raw_device_t = null;
    var numrawdevices: c_int = 0;
    const err = libmtp.LIBMTP_Detect_Raw_Devices(&rawdevices, &numrawdevices);
    if (err != 0 or numrawdevices == 0) {
        std.debug.print("no devices found (err={d})\n", .{err});
        libmtp.LIBMTP_Dump_Errorstack(null);
        return;
    }

    std.debug.print("found {d} raw device(s)\n", .{numrawdevices});
    for (0..@intCast(numrawdevices)) |i| {
        const raw = &rawdevices[i];
        std.debug.print(
            "  raw[{d}]: bus={d} devnum={d} vendor={s} product={s}\n",
            .{ i, raw.bus_location, raw.devnum, cstr(raw.device_entry.vendor), cstr(raw.device_entry.product) },
        );

        const device = libmtp.LIBMTP_Open_Raw_Device_Uncached(raw) orelse {
            std.debug.print("  failed to open\n", .{});
            continue;
        };
        defer libmtp.LIBMTP_Release_Device(device);

        std.debug.print("  manufacturer: {s}\n", .{cstr(libmtp.LIBMTP_Get_Manufacturername(device))});
        std.debug.print("  model:        {s}\n", .{cstr(libmtp.LIBMTP_Get_Modelname(device))});
        std.debug.print("  serial:       {s}\n", .{cstr(libmtp.LIBMTP_Get_Serialnumber(device))});
        std.debug.print("  friendlyname: {s}\n", .{cstr(libmtp.LIBMTP_Get_Friendlyname(device))});

        var max_batt: u8 = 0;
        var cur_batt: u8 = 0;
        if (libmtp.LIBMTP_Get_Batterylevel(device, &max_batt, &cur_batt) == 0) {
            std.debug.print("  battery:      {d}/{d}\n", .{ cur_batt, max_batt });
        }

        std.debug.print("--- full device info ---\n", .{});
        libmtp.LIBMTP_Dump_Device_Info(device);
    }

    libmtp.LIBMTP_FreeMemory(rawdevices);
}
