# PCIe investigation

The tested image uses source `410693bef6c76c0a74e874fab3995bda3fac64f0`.
The current boot registers both BE14 endpoints. It does not register an NVMe controller.
Both additional M.2 PCIe hosts report link training timeout `-110`.
The user confirms that only the NVMe uses PCIe among the additional modules.
The unused M.2 host can report link down without indicating a second missing device.

## Current changes

Frank's board port is present. The dedicated PEXTP clock patch is absent.
All four `pextp_p*_sel` clocks report zero enable counts in the captured runtime status.
This observation alone does not prove when link training loses its clock.
The active overlays are `sd` and `8x-lan-phy`.
No `cn13` or `cn14` slot overlay is active.
The mt7996 timeout guard prevents early recovery crashes. It does not fix PCIe training.
The MDIO delay from PR25841 affects Ethernet PHY scanning, not PCIe.

## Candidate tests

| Candidate | Method | Interpretation |
| --- | --- | --- |
| Slot selection | Add the existing `cn13` or `cn14` DT overlay to extlinux and reboot. Preserve current overlays. | Tests GPIO mux selection before enumeration. No kernel rebuild is required if the DTBO exists. |
| PEXTP clocks | Port PR25751 to Linux 7.3. Mark only the four PEXTP selectors `CLK_IS_CRITICAL`. Rebuild the kernel. | Tests the reported clock-disable race. Check clock counts and repeat cold/warm starts. |
| Clock diagnosis | Add `clk_ignore_unused` for one comparison boot, then remove it. | Broad diagnostic only. A successful comparison supports clock investigation but does not identify one specific clock. |
| Signal/link speed | Temporarily limit the affected host to PCIe Gen1 through its Device Tree. Reboot. | Tests training margin if slot and clock fixes fail. Restore normal speed after the comparison. |
| Reset/power sequencing | Measure slot power and PERST timing. Compare the schematic and Frank's omitted reset sequence. | Requires evidence before adding GPIO/reset changes. A delayed rescan alone is not a permanent fix. |

CN13 uses PCIe host `11280000`, GPIO79 high, and the `cn13` overlay.
CN14 uses PCIe host `11290000`, GPIO63 high, and the `cn14` overlay.
Keep the chosen slot identical when comparing clock changes.
Do not switch GPIOs while the controller operates.
ASPM tuning targets power management after enumeration. It is not the first test for an absent endpoint.

Confirm the physical NVMe socket before the first slot test.
Record the image hash, overlays, command line, clocks, PCI devices, and NVMe identity after each boot.
Do not write to the NVMe during enumeration tests.
A successful link does not establish storage integrity or complete board acceptance.

Sources:

- [Frank's slot explanation](https://forum.banana-pi.org/t/m-2-m-key-connector-cn-14-does-not-work-on-bpi-r4-pro/26379)
- [OpenWrt PR25751](https://github.com/openwrt/openwrt/pull/25751)
