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
- Firmware-Installer meldet 13 installierte R4-Pro-Payloads
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

Das Bundle enthält den auf dem R4 Pro 8X ausgewählten `444`-Satz und behält
den zuvor verwendeten `233`-Satz für die andere vom Treiber unterstützte
Variante bei:

```text
mediatek/mt7996/mt7996_dsp.bin
mediatek/mt7996/mt7996_eeprom.bin
mediatek/mt7996/mt7996_rom_patch.bin
mediatek/mt7996/mt7996_wa.bin
mediatek/mt7996/mt7996_wm.bin
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

## 13. Board-lokaler SRAM-Fix für den MT7988-Ethernet-Treiber

Die Analyse erfolgte gegen den im erfolgreichen Image gebauten Frank-Kernel-
Commit `e69eb61a1523c5e993803c05a42c55c7576b07d3`. Dessen MT7988-DTS enthält
bereits sowohl den SRAM-Provider `eth_sram: sram@15400000` als auch die
korrekte Referenz `sram = <&eth_sram>` im Ethernet-Knoten. Ein DT-Fix ist daher
nicht erforderlich.

Der Treiber ruft für MT7988 `of_gen_pool_get(..., "sram", 0)` auf und beendet
den Probe bei fehlendem Pool mit genau der auf der Hardware beobachteten
Meldung und `-EINVAL`. Die verwendete `linux-filogic-current.config` enthielt
im Gegensatz zur Edge-Konfiguration jedoch kein `CONFIG_SRAM=y`; damit wurde
der `mmio-sram`-Provider nicht registriert.

Der isolierte Fix ergänzt deshalb `SRAM` im bereits vorhandenen
`custom_kernel_config__bpi_r4pro_8x_network`-Hook. Die gemeinsame
`linux-filogic-current.config` und die normale Filogic-Family bleiben
unverändert. Der Hook-Hash wurde auf `bpi-r4pro-8x-network-v2` erhöht, damit
der Kernel-Artefakt-Cache die Konfigurationsänderung berücksichtigt.

Aktueller Nachweis:

```text
Ursachenanalyse: PASS
Board-lokale Konfiguration: STATIC PASS
Kernel-/Image-Build: PENDING
Hardwaretest Ethernet-Probe: PENDING
```

Der nächste Test muss im erzeugten Image zuerst `CONFIG_SRAM=y` bestätigen.
Danach muss ein Cold Boot zeigen, dass `15100000.ethernet` ohne den bisherigen
SRAM-Pool-Fehler probed. Erst dann werden Management-Ethernet und die weiteren
PHY-/Switch-Stufen einzeln geprüft.

## 14. Build und SD-Vorbereitung nach dem SRAM-Fix

Der board-lokale Fix aus Branch-Commit `3d97a2121` wurde am 7. Oktober 2026
im GitHub-Actions-Run `37632230455` vollständig gebaut. Der Pull-Request-
Merge-Ref des Builds war `e6312be88f7ef91504f2b12918426c7cfeeadd85`.
Preflight und der vollständige gepinnte Trixie-Minimal-Build waren
erfolgreich; der Image-Job lief 37 Minuten und 30 Sekunden.

Das erzeugte Image ist:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
SHA256: 35800842b48b33da343a1f457d9fb629f4b436d866901c45874b9a6feffcc047
Größe: 1472200704 Bytes
```

Das GitHub-Artefakt bestand die ZIP-Integritätsprüfung und das extrahierte
Image die mitgelieferte SHA256-Prüfung. Als Negativvergleich enthielt das
vorherige Image auf der SD-Karte `# CONFIG_SRAM is not set`; im neuen
Raw-Image ist `CONFIG_SRAM=y` direkt enthalten. Damit ist die board-lokale
Kernel-Konfigurationsänderung im finalen Image wirksam.

Die 64-GB-SD-Karte wurde erneut eindeutig als `/dev/sdb`, USB/removable und
mit 63864569856 Bytes identifiziert. Nach dem Aushängen wurden exakt 351
Blöcke zu je 4 MiB geschrieben. Die anschließende vollständige Roh-
Rückleseprüfung derselben 1472200704 Bytes ergab erneut exakt den obigen
SHA256-Hash. Der Kartenleser wurde danach logisch abgeschaltet. Es wurden
keine Schreibvorgänge auf eMMC, NAND oder NOR ausgeführt.

Aktueller Nachweis:

```text
STATIC PASS
BUILD PASS
SD WRITE/READBACK PASS
ETHERNET HW TEST PENDING
```

Der nächste Schritt ist ein vollständig aufgezeichneter Cold Boot. Der Test
muss zuerst bestätigen, dass die bisherige Meldung `Could not get SRAM pool`
verschwunden ist und der Treiber `15100000.ethernet` erfolgreich probed.

## 15. Hardwaretest des Ethernet-SRAM-Fixes

Der physische Banana Pi BPI-R4 Pro 8X / 8 GiB wurde mit dem Image aus
GitHub-Actions-Run `37632230455` von der zuvor bitgenau geprüften 64-GB-SD-
Karte kalt gestartet. Die vollständige saubere UART-Aufzeichnung ist:

```text
UART-Log: uart-2026-10-07-3d97a2121-hw3.log
Größe: 96983 Bytes, 1253 Zeilen
SHA256: fb78902eda76c3a8ea924a0f81db54a3b84d684be573f334a5970d792ea06f47
```

Ein vorausgegangener Aufnahmeversuch mit einer unbeabsichtigt auf 9600 Baud
zurückgefallenen Host-Schnittstelle bleibt als
`uart-2026-10-07-3d97a2121-hw3-garbled.log` erhalten und wird nicht als
Testnachweis gewertet. Nach expliziter Einstellung von `/dev/ttyACM0` auf
115200 Baud wurde ein vollständiger neuer Cold Boot aufgezeichnet.

Bestätigt wurden:

- BL2, 8192 MiB DRAM, BL31 und U-Boot 2025.04
- Laden des 8X-Basis-DTB und des R4-Pro-SD-Overlays
- Linux 6.18.53, Erkennung der SD-Karte und read/write-Mount von `mmcblk0p5`
- erneutes Erreichen von `multi-user.target` und seriellem Login-Prompt
- keine Meldung `Could not get SRAM pool`
- erfolgreicher Probe von `15100000.ethernet` mit `eth0`, `eth1` und `eth2`
- Initialisierung beider DSA-Bäume und des MaxLinear-Switches
- PCIe-Erkennung der beiden MediaTek-Wi-Fi-Funktionen und des NVMe-Laufwerks

Damit ist der board-lokale `CONFIG_SRAM=y`-Fix als **ETHERNET CORE HW PASS**
bestätigt. Ein vollständiger Netzwerk-HW-Pass ist damit noch nicht erreicht.

Der neue früheste Netzwerkblocker sind die beiden Aeonsemi-AS21xxx-10G-PHYs.
Der Built-in-Treiber fordert `aeonsemi/as21x1x_fw.bin` bereits vor dem Mounten
des Root-Dateisystems an. Beide Versuche enden nach dem Firmware-Loader-
Fallback mit `-110`. Das Image enthält die korrekte 290272 Byte große Datei
unter `/lib/firmware/aeonsemi/as21x1x_fw.bin`, das erzeugte `uInitrd` enthält
sie jedoch nicht.

Die Analyse des exakten Kernel-Commits zeigt: `CONFIG_AS21XXX_PHY` ist ein
Tristate, wird für dieses Board aber absichtlich Built-in gebaut. Der Treiber
liest den Dateinamen aus der DT-Eigenschaft `firmware-name` und ruft
`request_firmware()` auf, deklariert die Datei jedoch nicht mit
`MODULE_FIRMWARE()`. Deshalb kann `initramfs-tools` sie nicht automatisch aus
`modules.builtin.modinfo` ermitteln. Eine Umstellung des Treibers auf Modul
wäre riskant, weil sich vor dem Userspace-Coldplug bereits der generische
Clause-45-PHY-Treiber binden kann.

Der nächste isolierte Fix soll daher die bereits gepinnte und verifizierte
Aeonsemi-Datei über einen R4-Pro-8X-spezifischen `initramfs-tools`-Hook in das
finale Initramfs aufnehmen. Die gemeinsame Filogic-Family bleibt unverändert.
eMMC, NAND und NOR wurden weiterhin nicht beschrieben.

## 16. Board-lokaler Initramfs-Hook für die Aeonsemi-PHY-Firmware

Der R4-Pro-8X-Image-Hook erzeugt nach erfolgreicher Installation der gepinnten
Firmware nun `/etc/initramfs-tools/hooks/bpi-r4pro8x-aeonsemi`. Dieser Hook
ruft `add_firmware "aeonsemi/as21x1x_fw.bin"` auf. Armbians finales
`update_initramfs` läuft erst nach `post_family_tweaks` und damit nachdem
sowohl die Firmwaredatei als auch der Hook in das Image eingefügt wurden.

Die Lösung ist bewusst board-lokal. `CONFIG_AS21XXX_PHY=y`, die gemeinsame
Filogic-Kernelkonfiguration sowie Kernel und Device Tree bleiben unverändert.
Damit kann sich der spezifische Aeonsemi-Treiber weiterhin vor einem
generischen Clause-45-Treiber binden und erhält seine Firmware trotzdem vor
dem Rootfs-Mount.

Der Hook enthält zusätzlich den SHA256-Wert der tatsächlich installierten
Firmware. Das ist nicht nur ein Auditmerkmal: Armbians Initramfs-Cache hasht
die Dateien unter `/etc/initramfs-tools`, aber nicht pauschal alle Dateien
unter `/lib/firmware`. Ein geänderter Firmware-Payload ändert damit auch den
Hookinhalt und erzwingt ein neu erzeugtes Initramfs.

Aktueller Nachweis:

```text
Ursachenanalyse: PASS
Board-lokaler Initramfs-Hook: STATIC PASS
Gemeinsame Filogic-Konfiguration unverändert: PASS
Kernel-/Image-Build: PENDING
Aeonsemi-Hardwaretest: PENDING
```

Nach dem nächsten Build muss zuerst nachgewiesen werden, dass
`aeonsemi/as21x1x_fw.bin` tatsächlich im finalen `uInitrd` liegt. Erst danach
wird ein weiterer aufgezeichneter SD-Cold-Boot durchgeführt.

## 17. Buildnachweis des Aeonsemi-Initramfs-Fixes

Branch-Commit `4ce2a690c` wurde im GitHub-Actions-Run `37664464391`
vollständig gebaut. Der PR-Merge-Ref und die im Image aufgezeichnete
Buildrevision lauten `f968f660444375f7acc00060e86755a639eb5074` beziehungsweise
`f968f66`. Der Image-Job war nach 26 Minuten und 57 Sekunden erfolgreich.
Preflight, Dependency Review, Board-Validierung und Shellcheck waren ebenfalls
erfolgreich.

Das erzeugte Image ist:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
Größe: 1472200704 Bytes
SHA256: b7a2af5a8dea2b65ddb60edd34c479313d92ee493613b0b8b02d4c1b1b86a0bc
```

Das GitHub-Artefakt hatte exakt 1472221441 Bytes. Nach dem fortsetzbaren
Bereichsdownload bestand es die vollständige ZIP-Prüfung; das entpackte Image
bestand die mitgelieferte SHA256-Prüfung. Das Image wurde anschließend nur
lesbar eingebunden. Der erweiterte Image-Root-Check bestätigte die neun
gepinnten Payloads, deren Auditmetadaten, den ausführbaren Initramfs-Hook und
die extlinux-Konfiguration.

Das finale `uInitrd` enthält:

```text
usr/lib/firmware/aeonsemi/as21x1x_fw.bin
Größe: 290272 Bytes
SHA256: 9016ee573c380bea4b36b352faaac72cb8d38d87c4675be6f2d1066a343ff8ed
```

Dieser Hash ist identisch mit der Rootfs-Datei und mit dem im erzeugten Hook
eingebetteten `firmware-sha256`. Damit ist der Fix als **BUILD PASS**
bestätigt. Für einen Hardware-Pass muss das Image noch auf die SD-Karte
geschrieben und ein neuer Cold Boot vollständig über UART aufgezeichnet
werden. Dabei müssen beide bisherigen 60-Sekunden-Firmware-Timeouts
verschwinden und beide Aeonsemi-PHYs den spezifischen Treiber erfolgreich
binden. eMMC, NAND und NOR bleiben unberührt.

## 18. SD-Vorbereitung für den Aeonsemi-Hardwaretest

Die Zielkarte wurde erneut eindeutig als `/dev/sdb`, USB/removable, Modell
`STORAGE DEVICE` und mit 63864569856 Bytes identifiziert. Interne SATA- und
NVMe-Datenträger waren anhand Bus, Removable-Flag, Modell und Größe klar
ausgeschlossen.

Beim ersten Schreibdurchlauf wurde die neue Rootpartition anschließend
unerwünscht automatisch read/write eingehängt. Die Roh-Rücklesesumme war
danach `52e781569a45310983f032a6e795522d0351f34e17db58bd1828afc3de13d75b`
und damit nicht mehr bitgleich zum Image. Dieser Fehlversuch wird ausdrücklich
nicht als Medienfehler oder erfolgreicher Verifikationslauf gewertet; ein
Ext4-Mount kann Superblock- und Journalmetadaten verändern.

Nach Deaktivierung des Desktop-Automounts wurde das Image erneut geschrieben.
Vor der anschließenden Prüfung war keine SD-Partition eingehängt. Die
vollständige Roh-Rückleseprüfung über exakt 351 Blöcke zu je 4 MiB, insgesamt
1472200704 Bytes, ergab:

```text
b7a2af5a8dea2b65ddb60edd34c479313d92ee493613b0b8b02d4c1b1b86a0bc
```

Dieser Wert ist exakt der SHA256 des heruntergeladenen und zuvor geprüften
Images. Die SD-Karte wurde danach logisch abgeschaltet und Automount wieder
aktiviert. Damit ist **SD WRITE/READBACK PASS** erreicht. Es wurden keine
Schreibvorgänge auf eMMC, NAND oder NOR ausgeführt.

## 19. Hardwaretest des Aeonsemi-Initramfs-Fixes

Der erste Boot mit Branch-Commit `4ce2a690c` wurde ab Kernelzeit 2,45 s
aufgezeichnet und erreichte den Login nach rund 34 Sekunden. Weil BL2 und
U-Boot in dieser Aufnahme fehlen, bleibt sie als ergänzender Nachweis erhalten:

```text
UART-Log: uart-2026-10-08-4ce2a690c-hw4-capture.log
Größe: 78341 Bytes, 950 Zeilen
SHA256: ee255a463121be5b9073b7ccd51fcaa47b6b63d1e01ddc9a84571c5b804ea531
```

Anschließend wurde der Logger vor einem vollständigen zweiten Cold Boot
gestartet. Dieser Wiederholungslauf enthält die gesamte Bootkette:

```text
UART-Log: uart-2026-10-08-4ce2a690c-hw4-repeat.log
Größe: 93188 Bytes, 1208 Zeilen
SHA256: 9c39dc163fc565c57a4a75c8a3cb1feb0b7a68fa515ad3b89e2a27435b9156be
```

Bestätigt wurden BL2, 8192 MiB DRAM, BL31, U-Boot 2025.04, SD/extlinux,
Linux 6.18.53, Rootfs, `multi-user.target` und Login. In beiden Läufen
melden beide Aeonsemi-PHYs `Firmware Version: 1.9.1`. Im vollständigen Lauf
binden `mdio-bus:1c` und `mdio-bus:18` an `Aeonsemi AS21xxx`; die
vorherigen Meldungen `failed to find FW file aeonsemi/as21x1x_fw.bin` und
die beiden 60-Sekunden-Firmware-Timeouts treten nicht mehr auf.

Damit ist der Aeonsemi-Initramfs-Fix als **AEONSEMI 10G PHY HW PASS**
reproduzierbar bestätigt. Externe Link-/Durchsatztests bleiben ein eigener
Netzwerk-Meilenstein.

Der neue früheste blockierende Funktionsfehler betrifft Wi-Fi. Im vollständigen
Cold Boot fordert `mt7996e` bei 26,90 s
`mediatek/mt7996/mt7996_rom_patch.bin` an. Die direkte Suche endet mit
`-ENOENT`, der Sysfs-Fallback wartet bis 90,08 s, und der Treiber-Probe
endet mit `-110`. Das gepinnte R4-Pro-Manifest enthält derzeit nur die
`_233`-Variante des ROM-Patches. Dieser Wi-Fi-Firmwarefehler wird als
nächster isolierter Grobschritt untersucht; er wird nicht mit dem erfolgreichen
Aeonsemi-Fix vermischt.

Weitere weiterhin offene, aber spätere Beobachtungen sind der xHCI-Fehler
bei `11190000.usb`, das fehlende GPIO für `sys-led-red` und mehrere
MaxLinear-Switch-Warnungen während des Setups. eMMC, NAND und NOR wurden
weiterhin nicht beschrieben.

## 20. Gepinnter MT7996-444-Firmwaresatz

Der vollständige Cold Boot aus Abschnitt 19 belegt als frühesten Wi-Fi-Fehler
die Anforderung von `mediatek/mt7996/mt7996_rom_patch.bin`. Der gebaute
Frank-Kernel-Commit `e69eb61a1523c5e993803c05a42c55c7576b07d3` liest in
`mt7996_variant_type_init()` das Register `MT_PAD_GPIO`: Ohne das Bit
`MT_PAD_GPIO_2ADIE_TBTC` wird `MT7996_VAR_TYPE_444` gewählt. Für diese Variante
definiert der Treiber die unsuffigierten ROM-, WM-, DSP- und WA-Namen; DSP ist
für 444 und 233 identisch.

Am bereits gepinnten linux-firmware-Commit
`17c8530777b28c3b909dc505b95cf895159bd8b9` wurden die vier zusätzlichen
444-Payloads per Git-Baum und anschließend gegen Größe und Git-Blob-ID
verifiziert:

```text
6fb81b6ce2d4e576d798f17e7f2ef83e7ec6331e     7680  mediatek/mt7996/mt7996_eeprom.bin
7cc515b21242dbd101c558b048af8782c8ad4883    37216  mediatek/mt7996/mt7996_rom_patch.bin
61dc7a97a013d279e5ffee49a455f1e21df5ba3d   510000  mediatek/mt7996/mt7996_wa.bin
1b8859dd71c2ae092eda5bcf480b3d5d896c83a0  2656440  mediatek/mt7996/mt7996_wm.bin
```

Der bestehende 233-Satz bleibt unverändert; das Manifest umfasst damit 13
R4-Pro-spezifische Payloadpfade. Die gemeinsame Filogic-Family wurde nicht
geändert.

Ein vorausgegangener, nicht vollständig aufgezeichneter Warmstart erreichte
nach dem Laden von WM/DSP/WA zusätzlich die Anforderung
`mediatek/mt7996e_rf.bin`. Franks gemeinsame `mt76_eeprom_init()`-Logik fordert
diese kalibrationsspezifische Datei zuerst an und fällt bei Fehlen auf OF/NVMEM
zurück. Eine solche gerätespezifische Kalibrierdatei wird nicht durch eine
generische linux-firmware-Datei ersetzt. Ob der OF/NVMEM-Fallback auf dem
R4 Pro 8X genügt, wird deshalb erst mit dem neu gebauten Image per Cold Boot
geprüft.

Der lokale Preflight und ein vollständiger Installer-Test in einem leeren
temporären Image-Root waren erfolgreich. Alle 13 Payloads mit zusammen
7188896 Bytes bestanden Git-Blob-, Größen- und SHA256-Auditprüfung.

Status dieses Grobschritts: **STATIC PASS / BUILD PENDING**.

## 21. Buildnachweis des MT7996-444-Firmwarefixes

Branch-Commit `632a0a6e0` wurde im GitHub-Actions-Run `37837041222`
erfolgreich gebaut. Der PR-Merge-Ref und die im Image vermerkte Buildrevision
lauten `7788d34d42fed6a93b34b1c67a9a3e3320ee3516` beziehungsweise `7788d34`.
Der Image-Job lief 34 Minuten und 13 Sekunden; Preflight und vollständiger
Trixie-Minimal-Build waren erfolgreich.

Heruntergeladen und geprüft wurde:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
Größe: 1476395008 Bytes
SHA256: ca35eea557130266d1ef8ad68f5f5f2b83be6e3b9737eec7f17f0a5d17a842f9
```

Das GitHub-Artefakt ist 1476415745 Bytes groß, hat den SHA256
`4906d900b11398a5dc02f83ee11c80b675ae57818ed1fd4fdb1efb956750f330`
und bestand den vollständigen ZIP-CRC-Test. Die mitgelieferte `.img.sha`
bestätigt den Image-Hash.

Das Image wurde ausschließlich read-only geprüft. Der Image-Checker bestätigt
extlinux mit 8X-DTB und SD-Overlay, den Aeonsemi-Initramfs-Hook sowie Quelle und
Audit des Firmwarebundles. `SOURCE` weist weiterhin den Modus `pinned` und den
Commit `17c8530777b28c3b909dc505b95cf895159bd8b9` aus. Alle 13 Dateien der
`SHA256SUMS` bestanden die Prüfung; darunter sind die fünf für MT7996-444
relevanten Pfade DSP, EEPROM, ROM-Patch, WA und WM.

Status dieses Grobschritts: **BUILD PASS / HW TEST PENDING**.

Der separate Upstream-Wartungscheck `Verify assets for newly added boards`
schlug im Run `37837035403` fehl, weil im Website-Repository
`armbian/armbian.github.io` noch
`board-images/bananapir4pro8x.png` (1920x1080, transparent) fehlt. Der
Vendor-Eintrag wurde erkannt; gemeldet wurde nur das Boardbild. Dieser externe
Armbian-Imager-Assetpunkt beeinflusst weder Preflight noch Shellcheck,
Board-Validierung, Dependency Review oder den erfolgreichen Image-Build und
bleibt als separater Integrationsschritt offen.

## 22. SD-Vorbereitung für den MT7996-444-Hardwaretest

Das in Abschnitt 21 verifizierte Image wurde auf die erneut eindeutig
identifizierte 64-GB-SD-Karte geschrieben. Das Ziel war `/dev/sdb` mit exakt
63864569856 Bytes, `RM=1`, `HOTPLUG=1`, Transport `usb`, Modell
`STORAGE DEVICE` und Serienkennung `Generic_STORAGE_DEVICE-0:0`. Die internen
SATA- und NVMe-Laufwerke wurden vor dem Schreiben getrennt davon geprüft.

Da der Desktop-Automounter beim vorausgegangenen SD-Test eine frisch
geschriebene Rootpartition verändert hatte, wurden `udiskie` und der
GVFS-UDisks-Monitor diesmal vor dem Aushängen pausiert. Unmittelbar vor dem
Schreiben war keine Partition von `/dev/sdb` eingehängt. Geschrieben wurde:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
Größe: 1476395008 Bytes (352 Blöcke zu 4 MiB)
SHA256: ca35eea557130266d1ef8ad68f5f5f2b83be6e3b9737eec7f17f0a5d17a842f9
```

`dd` schrieb genau 352 vollständige 4-MiB-Blöcke und schloss mit `fsync`
fehlerfrei ab. Vor der Rückleseprüfung blieb die neu erkannte Partitionstabelle
vollständig ausgehängt. Genau dieselben 1476395008 Bytes wurden anschließend
roh von `/dev/sdb` zurückgelesen; ihr SHA256 war erneut
`ca35eea557130266d1ef8ad68f5f5f2b83be6e3b9737eec7f17f0a5d17a842f9` und
damit bitgleich zum Build-Image.

Die SD-Karte wurde danach logisch abgeschaltet. `udiskie`, der
GVFS-UDisks-Monitor und die ursprünglichen Automount-Einstellungen wurden
wiederhergestellt. Damit ist **SD WRITE/READBACK PASS / HW TEST READY**
erreicht. eMMC, NAND und NOR wurden nicht beschrieben. Der nächste Schritt ist
ein vollständig aufgezeichneter Cold Boot des physischen BPI-R4 Pro 8X, bei dem
zuerst das Laden des unsuffigierten MT7996-ROM-Patches und anschließend der
OF/NVMEM-Fallback für eine möglicherweise angeforderte
`mediatek/mt7996e_rf.bin` bewertet werden.

## 23. Hardwaretest des MT7996-444-Firmwaresatzes

Der UART-Logger wurde vor dem Einschalten des physischen BPI-R4 Pro 8X
gestartet. Der vollständige Cold Boot ist erhalten als:

```text
UART-Log: uart-2026-10-09-632a0a6e0-hw5.log
Größe: 95727 Bytes, 1238 Zeilen
SHA256: d23749a76e51bf006feb01ba21fe51e5cb37518706f58abb7c99e026ef5097fa
```

Bestätigt wurden `WDT: Cold boot`, BL2, 8192 MiB DRAM, BL31,
U-Boot 2025.04, SD/extlinux, Linux 6.18.53, der read/write-Mount von
`mmcblk0p5`, Login und `multi-user.target`. Beide Aeonsemi-PHYs melden erneut
Firmware 1.9.1.

Der vorausgegangene MT7996-Blocker ist behoben: Die Anforderung des
unsuffigierten `mediatek/mt7996/mt7996_rom_patch.bin` endet nicht mehr mit
`-ENOENT`. Der Treiber erreicht anschließend die laufende MCU und meldet bei
25,76 s, 25,82 s und 25,88 s erfolgreich WM-, DSP- und WA-Firmware aus dem
444-Satz. Damit ist dieser isolierte Grobschritt als
**MT7996 444 FW HW PASS** bestätigt.

Der neue früheste Wi-Fi-Blocker betrifft die Kalibration. Bei 26,21 s fordert
der Treiber `mediatek/mt7996e_rf.bin` an. Die Datei fehlt, der Sysfs-Fallback
endet bei 90,08 s mit `-110`, und danach wird
`mediatek/mt7996/mt7996_eeprom_233_2i5i6i.bin` angefordert. Auch diese Datei
fehlt; nach einem zweiten Fallback-Fenster endet der `mt7996e`-Probe bei
151,52 s mit `-110`. Das restliche System erreicht bei 152,43 s dennoch
`multi-user.target`.

Die beiden beobachteten Kalibrationsdateien werden nicht ungeprüft durch eine
generische Payload ersetzt. Als nächster Grobschritt werden die Auswahl im
gebauten Frank-Kernel, die R4-Pro-8X-Gerätetopologie und eine autoritative
Quelle für die zu dieser Hardware passende EEPROM-Kalibration abgeglichen.
eMMC, NAND und NOR wurden weiterhin nicht beschrieben. Die bereits bekannten
separaten Beobachtungen am PCIe-Port `11280000`, xHCI `11190000` und
`sys-led-red` bleiben unverändert offen.

## 24. Gepinnte MT7996-Defaults für interne FEMs

Der gebaute Kernelstand `e69eb61a1523c5e993803c05a42c55c7576b07d3`
definiert zwei zusätzliche MT7996-EEPROM-Defaults. Beide gelten für interne
Front-End-Module:

```text
5ad238a5ae704873933b6df1c9af42ee206a686b  7680  mediatek/mt7996/mt7996_eeprom_2i5i6i.bin
11eaa85f4682f751da129a86dca7e842a78b6948  7680  mediatek/mt7996/mt7996_eeprom_233_2i5i6i.bin
```

Beide Dateien liegen bereits im gepinnten Firmware-Commit
`17c8530777b28c3b909dc505b95cf895159bd8b9`. Der zweite Pfad ist bytegleich
mit `mt7996_eeprom_233.bin`. Beide Pfade haben denselben Git-Blob
`11eaa85f4682f751da129a86dca7e842a78b6948`.

Der HW-#5-Cold-Boot fordert den internen 233-Pfad an. Der interne 444-Pfad
deckt die zweite vom gleichen Treiber unterstützte MT7996-Variante ab. Das
Manifest umfasst nun 15 geprüfte Payloads. Der Firmware-Pin bleibt unverändert.

Der optionale Versuch für `mediatek/mt7996e_rf.bin` bleibt zunächst getrennt.
Diese Datei ist kein generischer linux-firmware-Payload. Der Treiber wartet bei
ihrem Fehlen derzeit unnötig auf den Sysfs-Fallback.

Der vollständige Installer-Test schrieb 15 Dateien in ein leeres Test-Root.
Alle 15 Einträge bestanden die erzeugte SHA256-Auditprüfung.

Status dieses Grobschritts: **STATIC PASS / BUILD PENDING**.

## 25. Direkter Abruf der optionalen MT7996-Kalibrationsdatei

Franks `mt76_get_eeprom_file()` fordert zuerst `mediatek/mt7996e_rf.bin` an.
Die Datei ist optional und board-spezifisch. Das normale `request_firmware()`
startet bei Fehlen trotzdem den Sysfs-Fallback. HW #5 wartet deshalb rund
60 Sekunden.

Kernel 6.18 dokumentiert `request_firmware_direct()` für optionale Firmware.
Die Funktion nutzt keinen Sysfs-Fallback. Ein Fehlschlag erreicht sofort die
bestehende OF-, NVMEM-, Efuse- und Default-Logik.

Der neue Patchsatz `bpi-r4pro8x-6.18` ändert nur diesen Aufruf. Die normale
Filogic-Family bleibt unverändert. Der Workflow überwacht den neuen Patchpfad.

Der Patch passt auf den exakten Kernel-Commit `e69eb61a1523`. Projekt-Preflight,
CI-kompatibler Shellcheck, Workflow-YAML-Prüfung und Diff-Prüfung waren
erfolgreich.

Status dieses Grobschritts: **STATIC PASS / BUILD PENDING**.
