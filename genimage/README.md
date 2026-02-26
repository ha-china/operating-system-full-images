# Genimage configs

This directory contains [Genimage][genimage] configuration files for rebuilding
the image from extracted partitions. These config files need to be synced when
HAOS changes the partition layout or adds new board with specific partition
requirements (especially SPL and U-Boot partitions).

The upstream config files are located in the [buildroot-external/genimage][haos-genimage]
folder of the HAOS repository. With slight modifications these can be copied
here when needed.

[genimage]: https://github.com/pengutronix/genimage/
[haos-genimage]: https://github.com/home-assistant/operating-system/tree/dev/buildroot-external/genimage
