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

## 3. Firmware-Prüfung im erzeugten Rootfs

Das Firmware-Bundle ist auf den in
`packages/bpi-r4pro8x-firmware/manifest.tsv` eingetragenen Git-Snapshot
gepinnt. Während des Image-Builds werden Größe und Git-Blob-ID jedes Payloads
verifiziert. Das fertige Image enthält zusätzlich eine SHA256-Auditliste unter:

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
