Work in progress with essentially nothing functioning at the moment.

This supposedly implements a CLI tool that transfers arbitrary files
from my computer to my Kindle over USB via
[MTP](https://en.wikipedia.org/wiki/MTP),
which Amazon isn't willing to support with their own tooling.

```shell
$ ./zig/download.sh
$ ./zig/zig build test
```

```shell
$ ./zig/zig build detect
LIBMTP device_unknown[57]: Device 0 (VID=1949 and PID=9981) is UNKNOWN in libmtp v1.1.23.
LIBMTP device_unknown[59]: Please report this VID/PID and the device model to the libmtp development team
info(detect): found 1 raw device(s)
info(detect): raw[0]: bus=1 devnum=1 vendor=(null) product=(null)
PTP: Opening session
info(detect): device: Amazon / Kindle Colorsoft Signature Edition
info(detect): serial:   friendlyname: Kindle Colorsoft Signature Edition
warning(detect): battery level unsupported
info(detect): storage id=65537: Internal Storage  capacity=27071250432 free=26019823616
info(detect): --- full device info ---
# full dump omitted...
```
