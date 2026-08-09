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
Unpacking MTP OPL, size 69093 (prop_count 2508)
info(detect): snapshot: 140 files, 4 folders
documents
├─ dictionaries
│  ├─ Oxford_Dictionary_of_English.sdr
│  ├─ The_New_Oxford_American_Dictionary.sdr
│  │  ├─ The_New_Oxford_American_Dictionary6db96866ad462db28eca48b8d37f3160.mbs  id=1222, size=335
│  │  ├─ The_New_Oxford_American_Dictionary6db96866ad462db28eca48b8d37f3160.mbp1  id=1223, size=118
│  │  └─ The_New_Oxford_American_Dictionary.phl  id=1224, size=397
│  ├─ Oxford_Dictionary_of_English.azw  id=1220, size=49335612
│  └─ The_New_Oxford_American_Dictionary.azw  id=1225, size=71114360
# full dump omitted...
```
