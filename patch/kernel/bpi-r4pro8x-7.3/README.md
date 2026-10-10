# R4 Pro 8X Linux 7.3-rc6 patches

Base: Torvalds `a90ee4305c4a5df72c11b31dacfdc76e00fcf78a` (`v7.3-rc6`).
Frank source: `32b3bd5458be1657056f9852b0b309f73b65a4d7` (`7.3-rc`).
Frank base: `cee9395acd8043be0644b25c34bfa86623f2b935` (`v7.3-rc1`).

`000` exports Frank's drivers, headers, network code, arm64 Device Trees and documentation.
It excludes build scripts, firmware copies, arm32 configurations and `.orig`/`.rej` files.
Three-way application resolves conflicts against rc6 before export.
MediaTek Ethernet keeps rc6 EEE limits and allocates NAPI before registering interfaces.
RSS/LRO use Frank's NAPI arrays, including probe cleanup.
MaxLinear teardown keeps rc6 worker shutdown and Frank's tag teardown ordering.
MDIO setup completes before the statistics worker starts.
Inherited whitespace warnings remain visible.

`002` enables FPC and the LAN 10G PHY for the 8X front panel.
Frank's updated switch driver numbers the LAN combo port as 13.
The shared Device Tree already names `lan1` through `lan5`.

`003` logs automatic MT7996 variant selection, reset registers and requested ROM firmware.
It does not force 233 or change reset delays.

The upstream EEPROM path uses OF data or eFuse.
The obsolete 6.18 RF-file patches remain in their original directory.
Do not apply them to this kernel.

Local tests verify clean sequential patch application, DTB compilation and SD overlay application.
Full compilation and physical hardware tests remain separate milestones.
