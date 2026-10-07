# Banana Pi BPI-R4 Pro 8X — Build- und Bring-up-Checkliste

Diese Checkliste gilt für den Entwicklungsbranch `bpi-r4pro-8x`. Ziel des ersten
Bring-ups ist **nicht** sofort vollständige Hardware-Unterstützung, sondern eine
klar gestufte Bootkette:

`BootROM -> BL2/ATF -> U-Boot -> SD -> extlinux -> Linux 6.18 -> Trixie rootfs`

Erst wenn diese Kette stabil ist, werden Netzwerk, PCIe/NVMe und Wi-Fi 7 einzeln
freigeschaltet und getestet.

## 1. Voraussetzungen

Empfohlen ist ein aktueller Debian-/Armbian-Trixie-Buildhost mit mindestens
8 GiB RAM und ausreichend freiem Speicher für Kernel-, U-Boot- und Rootfs-Caches.

Repository und Branch:

```bash
git clone https://github.com/GermanatorLM/build.git
cd build
git switch bpi-r4pro-8x
```

Vor jedem Build zuerst den statischen Port-Check ausführen:

```bash
bash tools/bpi-r4pro8x-check.sh
```

Erwartung: alle Prüfungen enden mit `PASS`. Die leere
`BOARD_MAINTAINER`-Angabe kann vom generischen Armbian-Validator als Warnung
gemeldet werden; sie ist für den Bring-up kein Buildfehler.

## 2. Erster reproduzierbarer Minimal-Build

```bash
./compile.sh build \
  BOARD=bananapir4pro8x \
  BRANCH=current \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

Wichtige erwartete Build-Schritte im Log:

- Board: `bananapir4pro8x`
- Family: `filogic-r4pro`
- Kernelquelle: Frank Wunderlich `BPI-Router-Linux`, Branch `6.18-main`
- ATF: Frank/MediaTek, Branch `mtk-atf-2026`
- ATF mit `DDR4_4BG_MODE=1`
- U-Boot-Target: `mt7988a_bpir4pro_sd_defconfig`
- Linux-DTB: `mt7988a-bananapi-bpi-r4-pro-8x.dtb`
- SD-Overlay: `mt7988a-bananapi-bpi-r4-pro-sd.dtbo`
- Firmware-Installer meldet 9 installierte R4-Pro-Payloads
- Image wird unter `output/images/` erzeugt

Bei einem Fehler zuerst das aktuelle Log unter `output/logs/` sichern. Nicht
gleich mehrere Komponenten gleichzeitig ändern.

### 2.1 Firmware-Auswahl per Build-Flag

Ohne zusätzliche Flags wird weiterhin der fest gepinnte und vollständig
verifizierte Firmwarestand verwendet:

```text
BPI_R4PRO8X_FIRMWARE_MODE=pinned
```

Das ist der Standard und die empfohlene Einstellung für reproduzierbare Builds.

Für den **aktuellsten Stand des kanonischen linux-firmware-Repositories**:

```bash
./compile.sh build \
  BOARD=bananapir4pro8x \
  BRANCH=current \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no \
  BPI_R4PRO8X_FIRMWARE_MODE=latest
```

`latest` löst `HEAD` des kanonischen
`git.kernel.org/.../linux-firmware.git` beim Build auf einen konkreten Commit
auf. Der Build ist damit als Eingabe bewusst nicht vollständig reproduzierbar;
der tatsächlich verwendete Commit wird aber im Image dokumentiert.

Für einen **bestimmten Firmwarestand** kann ein Commit, Tag oder Branch
vorgegeben werden:

```bash
./compile.sh build \
  BOARD=bananapir4pro8x \
  BRANCH=current \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no \
  BPI_R4PRO8X_FIRMWARE_MODE=ref \
  BPI_R4PRO8X_FIRMWARE_REF=<commit-tag-oder-branch>
```

Für reproduzierbare Vergleichstests sollte bei `ref` möglichst ein vollständiger
40-stelliger Commit verwendet werden. Tags und Branches werden vor dem Download
auf einen konkreten Commit aufgelöst.

Die drei Modi sind damit:

| Modus | Quelle | Verifikation | Einsatzzweck |
|---|---|---|---|
| `pinned` | festes HHD/linux-firmware Snapshot | Manifest-Größe + Git-Blob-ID | Standard, reproduzierbar |
| `latest` | kanonisches linux-firmware `HEAD` | auf Commit aufgelöst + SHA256-Audit | neue Firmware testen |
| `ref` | kanonisches linux-firmware, frei gewählter Ref | auf Commit aufgelöst + SHA256-Audit | Regression/Bisect/Vergleich |

Nicht kombinieren:

```text
BPI_R4PRO8X_FIRMWARE_MODE=latest
BPI_R4PRO8X_FIRMWARE_REF=...
```

Für einen gesetzten `BPI_R4PRO8X_FIRMWARE_REF` muss der Modus `ref` verwendet
werden.

## 3. Firmware-Prüfung im erzeugten Rootfs

Im Standardmodus `pinned` ist das Firmware-Bundle auf den in
`packages/bpi-r4pro8x-firmware/manifest.tsv` eingetragenen Git-Snapshot
gepinnt. Größe und Git-Blob-ID jedes Payloads werden verifiziert.

In `latest` und `ref` wird der angeforderte Ref zuerst auf einen konkreten
Commit des kanonischen linux-firmware-Repositories aufgelöst. Das fertige Image
dokumentiert in allen Modi den tatsächlich verwendeten Commit und die finalen
Dateihashes unter:

```text
/usr/share/doc/bpi-r4pro8x-firmware/SOURCE
/usr/share/doc/bpi-r4pro8x-firmware/RESOLVED_MANIFEST.tsv
/usr/share/doc/bpi-r4pro8x-firmware/SHA256SUMS
```

Die SHA256-Auditliste liegt unter:

```text
/usr/share/doc/bpi-r4pro8x-firmware/SHA256SUMS
```

Wenn ein entpacktes oder gemountetes Rootfs vorliegt:

```bash
bash tools/bpi-r4pro8x-check.sh --image-root /pfad/zum/rootfs
```

Damit werden Firmware-Dateien, DTB/DTBO-Auswahl und extlinux-Einträge geprüft.

## 4. SD-Karte vorbereiten

Für den ersten Bring-up ausschließlich SD verwenden. eMMC/NAND/NOR-Flashing
ist noch kein Bestandteil dieses Meilensteins.

Vor dem Schreiben das Zielgerät mehrfach prüfen:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS
```

Danach das erzeugte Image mit einem geeigneten Imager oder bewusst mit
`dd` auf die **richtige** SD-Karte schreiben. Ein falsches Zielgerät zerstört
Daten auf dem Host.

## 5. UART-Setup

UART-Konsole:

- 115200 Baud
- 8N1
- keine Hardware-Flusskontrolle

Den kompletten Bootlog ab Power-On mitschneiden. Für jeden Testlauf sollten
mindestens Datum, Commit, Image-Dateiname und UART-Log zusammen archiviert werden.

## 6. Boot-Gates

### Gate A — BL2 / DRAM

Bestanden wenn:

- BL2 startet reproduzierbar.
- keine frühe DRAM-Initialisierungs-Panik erscheint.
- U-Boot erreicht wird.

Später unter Linux prüfen, ob tatsächlich ungefähr 8 GiB RAM verfügbar sind.

### Gate B — U-Boot / SD

Bestanden wenn:

- Prompt `BPI-R4P>` sichtbar ist oder der Autoboot sauber weiterläuft.
- SD/MMC erkannt wird.
- die GPT-Partitionen des Armbian-Images gelesen werden können.
- `/boot/extlinux/extlinux.conf` gefunden wird.

Bei Problemen im U-Boot-Prompt sichern:

```text
mmc list
mmc info
part list mmc 0
ls mmc 0:5 /boot/extlinux
printenv
```

Die Partitionsnummer kann sich bei späteren Layoutänderungen ändern; deshalb
immer zuerst `part list` ansehen.

### Gate C — Linux-Kernel

Bestanden wenn:

- `Starting kernel ...` erreicht wird.
- Linux 6.18 bootet.
- der 8X-Basis-DTB akzeptiert wird.
- der SD-Overlay aktiv ist.
- kein Rootfs-Panic entsteht.

Nach Login:

```bash
uname -a
cat /proc/device-tree/model; echo
free -h
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
cat /proc/cmdline
```

### Gate D — Rootfs / Armbian

Bestanden wenn:

- Trixie bis Login bootet.
- Rootfs schreibbar ist.
- Netzwerkprobleme den Boot nicht blockieren.
- ein Reboot erneut erfolgreich ist.

## 7. Hardware-Bring-up in fester Reihenfolge

Nicht mehrere Punkte gleichzeitig debuggen. Nach jeder bestandenen Stufe Commit
und README-Chronik aktualisieren.

### 7.1 Management-/SoC-Ethernet

```bash
ip -br link
dmesg | grep -Ei 'mediatek|mtk|ethernet|phy|firmware'
```

Ziel: mindestens ein stabiler Managementpfad für SSH/Logs.

### 7.2 Interne 2.5G-PHYs

Firmware muss vorhanden sein:

```text
/lib/firmware/mediatek/mt7988/i2p5ge-phy-pmb.bin
/lib/firmware/mediatek/mt7987/i2p5ge-phy-DSPBitTb.bin
/lib/firmware/mediatek/mt7987/i2p5ge-phy-pmb.bin
```

Kernel-Log auf Firmware-/PHY-Fehler prüfen.

### 7.3 Aeonsemi AS21xxx / 10G

Firmware:

```text
/lib/firmware/aeonsemi/as21x1x_fw.bin
```

Prüfen:

```bash
dmesg | grep -Ei 'as21|aeon|10g|firmware'
ip -br link
```

### 7.4 MaxLinear MxL862xx DSA-Switch

```bash
dmesg | grep -Ei 'mxl|dsa|switch'
ip -br link
bridge link
```

Ziel ist zunächst nur saubere Probe/Enumeration. VLAN-/Bridge-Konfiguration
kommt erst danach.

### 7.5 PCIe / NVMe

```bash
lspci -nn
dmesg | grep -Ei 'pcie|pci|nvme'
lsblk
```

Erst wenn PCIe stabil enumeriert, NVMe-Rootfs oder weitere Bootpfade testen.

### 7.6 MT7996 Wi-Fi 7

Das Bundle enthält den von Franks BPI-R4-Images verwendeten `233`-Satz:

```text
mediatek/mt7996/mt7996_dsp.bin
mediatek/mt7996/mt7996_eeprom_233.bin
mediatek/mt7996/mt7996_rom_patch_233.bin
mediatek/mt7996/mt7996_wa_233.bin
mediatek/mt7996/mt7996_wm_233.bin
```

Prüfen:

```bash
dmesg | grep -Ei 'mt7996|mt76|firmware'
iw dev
lspci -nn
```

Wi-Fi-Konfiguration und AP-Betrieb erst angehen, wenn der Treiber ohne
Firmwarefehler probed.

## 8. Fehlerklassifikation

Fehler immer der frühesten fehlschlagenden Stufe zuordnen:

1. **kein BL2/U-Boot** -> ATF/DRAM/U-Boot
2. **U-Boot sieht SD nicht** -> U-Boot-DTS/MMC
3. **extlinux fehlt** -> Armbian-Image/Partitionierung
4. **Kernel startet nicht** -> U-Boot/extlinux/DTB
5. **Kernel startet, Rootfs fehlt** -> SD-Overlay/cmdline/initramfs
6. **Login funktioniert, Hardware fehlt** -> Linux-DT/Kconfig/Firmware/Treiber

Dadurch bleiben Änderungen klein und bis zum verursachenden Commit
zurückverfolgbar.

## 9. Testprotokoll-Vorlage

Für jeden Hardware-Test einen kurzen Block führen:

```text
Datum:
Build-Commit:
Image:
Board/Revision:
Boot-Gate:
Ergebnis: PASS / FAIL
UART-Log:
dmesg-Ausschnitt:
Nächster Schritt:
```

Ein Punkt gilt erst als abgeschlossen, wenn er nach einem Cold Boot erneut
reproduzierbar bestanden wurde.

## 10. Erster physischer SD-Boot vom 7. Oktober 2026

```text
Datum: 2026-10-07
Branch-Commit: 3f3d673da189c1f2dcbbd46731a1285a1d31dfda
Image-Build-Revision: 7f6439f
Image: Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
Board: Banana Pi BPI-R4 Pro 8X / 8 GiB
Boot-Gate: Gate B / Gate C
Ergebnis: BOOT BLOCKED
UART-Log: uart-2026-10-07-07e66bd41.log
```

Erfolgreich erreicht wurden:

- BootROM und BL2
- DDR4-Initialisierung und komplexer Speichertest, `DRAM: 8192MB`
- BL31
- U-Boot 2025.04
- SD-Erkennung und Laden von `/boot/extlinux/extlinux.conf`
- Laden von Kernel, initrd und 8X-Basis-DTB
- Start von Linux 6.18.53 mit vier CPUs und rund 8 GiB RAM

Der früheste relevante Fehler ist in U-Boot:

```text
Invalid fdtoverlay_addr_r for loading overlays
```

Das konfigurierte SD-Overlay wird deshalb nicht geladen. Der Kernel startet
mit dem Basis-DTB, erkennt das SD-Rootfs nicht und endet nach dem initramfs-
Timeout mit:

```text
ALERT! UUID=728e769e-2874-40a1-adde-a86d2a08f253 does not exist.
Dropping to a shell!
```

Der nächste isolierte Fix muss `fdtoverlay_addr_r` im R4-Pro-U-Boot-Target
definieren. Die gemeinsame Filogic-Konfiguration soll dabei unverändert bleiben.

Der daraufhin implementierte, noch auf Hardware zu bestätigende Fix verwendet
ein R4-Pro-lokales U-Boot-Text-Environment:

```text
fdt_addr_r=0x62000000
fdtoverlay_addr_r=0x62080000
ramdisk_addr_r=0x62180000
```

Damit liegt der Overlay-Stagingbereich 512 KiB oberhalb des Basis-DTB und
1 MiB unterhalb des initrd-Bereichs. Der normale Filogic-/BPI-R4-Env-Block
bleibt unverändert. Der nächste Hardwaretest muss zuerst bestätigen, dass
U-Boot das SD-Overlay tatsächlich lädt und das Rootfs-Gerät danach erscheint.

## 11. Build und SD-Vorbereitung nach dem Overlay-Adressfix

Der R4-Pro-lokale Fix aus Branch-Commit `a298f8ac3` wurde am 7. Oktober 2026
im GitHub-Actions-Run `37606136761` vollständig gebaut. Der Pull-Request-
Merge-Ref des Builds war `c2e580bb1767fe4b8e47304875e5fc4e1c8ef073`.
Preflight und vollständiger gepinnter Trixie-Minimal-Build waren erfolgreich.

Das erzeugte Image ist:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
SHA256: 1da8417fc4a5032d05b6571c5c52ad73fa2085fdd1febbc5cdf8d42e110cbae5
Größe: 1472200704 Bytes
```

Der Buildlog bestätigt, dass Patch `451-add-bpi-r4pro-8x` mit der neuen Datei
`bpi-r4pro.env` angewendet und U-Boot 2025.04 anschließend erfolgreich gebaut
wurde. Zusätzlich ist `fdtoverlay_addr_r=0x62080000` im finalen Raw-Image
enthalten. Das heruntergeladene Image bestand die mitgelieferte SHA256-Prüfung.
Nach dem Schreiben wurden exakt 351 Blöcke zu je 4 MiB von der 64-GB-SD-Karte
zurückgelesen; der Rücklese-Hash entsprach ebenfalls der obigen SHA256-Summe.

Damit bleibt vor dem nächsten Cold Boot ausschließlich die Hardwarebestätigung
offen: U-Boot muss das SD-Overlay ohne die frühere Fehlermeldung laden und der
Kernel anschließend das SD-Rootfs finden. Das ist noch kein `BOOT PASS`.

## 12. Reproduzierbarer SD-Boot vom 7. Oktober 2026

Der Fix wurde auf dem physischen Banana Pi BPI-R4 Pro 8X / 8 GiB in zwei
aufeinanderfolgenden Cold Boots getestet:

```text
Branch-Commit: a298f8ac3
Image-Build-Revision: c2e580b
Image-SHA256: 1da8417fc4a5032d05b6571c5c52ad73fa2085fdd1febbc5cdf8d42e110cbae5
UART-Log 1: uart-2026-10-07-a298f8ac3-hw2.log
UART-Log 2: uart-2026-10-07-a298f8ac3-hw2-repeat.log
Ergebnis: BOOT PASS / HW BLOCKED
```

Beide Durchläufe erreichten reproduzierbar:

- BL2/DDR4 mit `DRAM: 8192MB`, BL31 und U-Boot 2025.04
- Laden des 8X-Basis-DTB und des R4-Pro-SD-Overlays über extlinux
- keinen erneuten Fehler `Invalid fdtoverlay_addr_r for loading overlays`
- Erkennung der 64-GB-SD-Karte als `mmcblk0` samt Partitionen `p1` bis `p5`
- read/write-Mount der Rootpartition `mmcblk0p5`
- systemd, SSH, seriellen Login-Prompt und `multi-user.target`

Beim ersten Lauf wurde die Rootpartition erfolgreich auf den verfügbaren
SD-Kartenplatz vergrößert. Der zweite Lauf bootete anschließend erneut bis in
den vollständigen Userspace. Damit ist `BOOT PASS` erreicht.

`HW PASS` ist noch nicht erreicht. Der früheste reproduzierbare Linux-
Hardwarefehler nach erfolgreichem SD-Root-Mount ist:

```text
mtk_soc_eth 15100000.ethernet: Could not get SRAM pool
mtk_soc_eth 15100000.ethernet: probe with driver mtk_soc_eth failed with error -22
```

Weitere offene Beobachtungen sind ein nicht startender xHCI-Controller bei
`11190000.usb`, vier PCIe-Links ohne Link sowie das fehlende GPIO für
`sys-led-red`. Die PCIe-Meldungen werden erst als Fehler gewertet, wenn die
Bestückung der betreffenden Slots im Testaufbau feststeht. Die U-Boot-Warnung
über eine ungültige Environment-CRC ist beim noch nicht gespeicherten Default-
Environment nicht bootblockierend. Es wurden keine Installations- oder
Flash-Schreibvorgänge auf eMMC, NAND oder NOR angestoßen.

Der nächste isolierte Hardware-Grobschritt ist die Analyse des fehlenden SRAM-
Pools für `15100000.ethernet`, ohne die gemeinsame Filogic-Family zu ändern,
sofern eine R4-Pro-lokale DT-Lösung möglich ist.
