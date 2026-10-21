# Hardware acceptance

Keep reports and raw logs private until release approval.
Record tester, date, board revision, BE14 revision, image SHA256, and package hashes.
Record PSU model, PD negotiation, debug cable state, antennas, and ambient temperature.
Use the same image for each comparison series. Change one variable at a time.

## SD first

1. Identify SD by model, capacity, serial, and device path.
2. Unmount SD partitions. Write only the identified device.
3. Read back the full written image range. Compare SHA256 with the decompressed image.
4. Capture UART at 115200 8N1 from BL2 through first login.
5. Verify 8 GiB DDR4, root filesystem mounting, and Armbian first-login setup.
6. Confirm DHCP clients. Confirm no router or Wi-Fi profile exists.
7. Preserve `dmesg`, journal, device tree, firmware hashes, and package versions.

Record boot firmware choice, PAD_GPIO observations, PHY registrations, and all warnings.
Do not repeat uncontrolled `/dev/mem`, PCIe reset, or link retraining experiments.
GPIO54 controls the LAN combo mux. It is not a confirmed BE14 power reset.

## Startup series, each boot medium

Run at least ten cold starts and ten warm starts per medium.
Record every attempt, including failures, power intervals, debug state, and WLAN probe result.
Any WLAN initialization failure blocks acceptance.

Initial comparison condition: disconnect PD and debug for five minutes.
Reconnect debug and start UART capture before reconnecting PD.
This condition is an investigation baseline, not a proven cure or minimum interval.
Compare other conditions only in separate, documented series.
Report a required workaround explicitly.
Measure supply and reset behavior before claiming an electrical cause.
Linux shutdown does not prove physical power removal.

## Ethernet and other devices

| Front label | Expected connection | Test evidence |
| --- | --- | --- |
| lan1–lan4 | MaxLinear 2.5G PHYs | Pending |
| lan5 | Internal 1G switch | Pending |
| lan6 | MaxLinear 10G combo | Pending |
| wan | MT7988 10G combo | Pending |

Verify actual port mapping, negotiated speed, bidirectional traffic, and packet errors.
Test RJ45/SFP combo selection and link recovery. Record each tested speed.
Test USB devices, populated storage, temperature sensors, and repeated restart behavior.
Do not claim PTP hardware timestamps from `linuxptp` availability alone.

## Radio, with antennas

| Band | Client, at least one hour | AP, at least one hour |
| --- | --- | --- |
| 2.4 GHz | Pending | Pending |
| 5 GHz | Pending | Pending |
| 6 GHz | Pending | Pending |

Use the correct regulatory country and permitted channels.
Record peer, frequency, bandwidth, encryption, PMF, DHCP, traffic rate, duration, and errors.
Use suitable WPA3/PMF settings for 6 GHz.
Run bidirectional traffic for at least 3600 seconds for every cell.
Preserve association logs and kernel logs before and after traffic.
Timeout guards do not count as successful WLAN initialization.

## eMMC, after SD acceptance

Develop the installer using the documented controller and boot-partition layout.
Identify the eMMC by CID, model, capacity, and path. Reject ambiguous or mounted targets.
Back up user data, partition tables, boot partitions, and boot configuration.
Hash backups. Verify that recovery media can read the backups.
Document hardware switches and the SD recovery procedure before writing.
Write only the approved eMMC BL2, FIP, and image layout.
Read back every written range. Compare hashes before changing boot selection.
Boot through UART. Repeat all required startup and device tests.
Demonstrate SD recovery without relying on a working eMMC bootloader.

No generic `dd` recipe constitutes an accepted eMMC installer.
Leave EEPROM, SPI-NAND, and switch firmware unchanged during these tests.

## Final release candidate

Record the exact image SHA256 and every release asset SHA256.
Confirm complete corresponding sources and firmware redistribution permissions.
Confirm no credentials, host keys, Wi-Fi profiles, or personal identities remain.
Confirm every required test passes. Keep failures visible in the report.
Publish the tested bytes only. Include installation and SD recovery instructions.
The public promotion step must not invoke `compile.sh`.
