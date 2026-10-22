# PCIe clock ownership

## Running baseline

The current tested image uses source `7b4eb5d0ca18c3a6f8bb5d36321358337159affc`.
Its SHA256 is `bf83ee67ab5dcdbea04e987b12708962bbffe150621888f822cc1dafbc528ae2`.
Both M-key overlays are active. The Patriot P300 occupies CN14, lane 1L1.
The NVMe registers at PCIe Gen3 x1. Both BE14 endpoints also register.
The empty CN13 host reports link down. This does not identify another missing device.
The baseline lacks explicit PEXTP clock consumers. All four reference clocks report zero enable counts after boot.
That snapshot alone does not establish when link training loses its clock.

The earlier CN14-only image passes three warm enumeration tests after adding its slot overlay.
Do not combine different image candidates into one acceptance count.

## Implemented backport

Patches 0005 and 0006 port PR25841 patches 991 and 992 onto Linux 7.3.
Source revision: `81fcdc849ae8905e1b4ab4f43036de6d5e7576e8`.
The binding permits the MT7988 compatible and its five clocks.
Each host retains its four infracfg clocks and adds its matching PEXTP reference clock.
The driver matches the existing `mediatek,mt8192-pcie` fallback.
The driver already obtains all listed clocks and enables them before link training.
No PCIe driver code change is required.

| Host | PEXTP clock | Slot or endpoint |
| --- | --- | --- |
| 11280000 | pextp_p2_sel | CN13 or CN15 |
| 11290000 | pextp_p3_sel | CN14 or CN18 |
| 11300000 | pextp_p0_sel | BE14 interface |
| 11310000 | pextp_p1_sel | BE14 interface |

The Linux 7.3 binding adds MT7981 and MT8189 context absent from the original 6.18 patch.
The backport preserves those entries and changes only the MT7988 description.
The isolated R4 Pro kernel patch directory contains this change. Other Armbian families remain unaffected.
`kernel.backports` in sources.lock.json records source files and patch hashes.

## Verification

Both backports apply to the 7.3 baseline without fuzz.
The Device Tree binding passes dt-doc-validate.
SD and eMMC trees compile with the LAN PHY overlay and both M-key overlays.
Both trees pass targeted PCIe schema validation.
Each host has five clocks, with the correct PEXTP provider and identifier.
The four previous clock entries remain unchanged.
A negative control without the fifth clock produces a schema error.
Both M-key GPIO hogs remain output-high.

These checks do not prove hardware reliability.
The backport is not loaded on the running router yet.
No complete image build or SD rewrite occurs during this implementation step.
CPUfreq configuration remains unchanged.

## Hardware comparison

Build a separate private candidate from the committed source.
Preserve both M-key overlays and the same NVMe socket.
Do not add PR25751 or clk_ignore_unused during this comparison.

1. Record image hash, extlinux configuration, and command line.
2. Verify CN13 GPIO79 and CN14 GPIO63 remain high.
3. Check PEXTP consumers and enable counts while each successful host operates.
4. Verify NVMe enumeration, link speed, and both BE14 interfaces.
5. Repeat cold and warm boots under documented PD/debug conditions.
6. Record errors and radio initialization independently of PCIe enumeration.

An empty host can release its clock after link training fails.
Do not require that host to retain a nonzero enable count.
The empty CN13 timeout can remain after the fix.
Do not write to NVMe during enumeration tests.

PR25751 remains an alternative experiment that marks PEXTP clocks critical.
Use it separately only if further investigation requires that comparison.
ASPM tuning and a temporary Gen1 limit remain later diagnostics.
Change reset or power sequencing only after measuring the relevant conditions.

Sources:

- [OpenWrt PR25841](https://github.com/openwrt/openwrt/pull/25841)
- [OpenWrt PR25751](https://github.com/openwrt/openwrt/pull/25751)
- [Frank's slot explanation](https://forum.banana-pi.org/t/m-2-m-key-connector-cn-14-does-not-work-on-bpi-r4-pro/26379)
