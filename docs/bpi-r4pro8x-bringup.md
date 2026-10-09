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

## 49. DT-Kompilierung: port6 vor seiner Definition

CI-Run `37972714444` besteht den Preflight und scheitert bei der Kernel-DT-Kompilierung.
Der ursprüngliche Fehler lautet `Label or path port6 not found` in der 8X-DTS.
`compile-wrapper.sh:28` meldet danach lediglich den Make-Abbruch mit Status 2.
Die frühere Patch-Anwendungsprüfung erkennt diesen semantischen Fehler nicht.
Der Patch setzt `lan6` jetzt direkt im später definierten `port6`-Knoten.
Die gemeinsamen R4-Pro- und Filogic-Dateien bleiben unverändert.
Die SD-Karte bleibt unverändert; dieser Run erzeugt kein Image.

Die lokale DT-Prüfung baut DTC aus vorhandenen Kernelquellen in einem temporären Verzeichnis.
Der erste Aufruf verwendet das falsche Arbeitsverzeichnis; danach fehlt zunächst `NO_YAML` beim Linken.
Der erste DTS-Aufruf scheitert an einem als Text heruntergeladenen Header-Symlink.
Das geladene Symlink-Ziel ermöglicht anschließend die erfolgreiche DT-Kompilierung.
Der erzeugte DTB enthält `lan1` bis `lan6` und `fpc`.
Vier PHY-Warnungen treten unverändert auch ohne den Patch auf.
Der vollständige lokale Preflight besteht erneut.
`git diff --check` beanstandet neue Patch-Kontextzeilen mit Leerzeichen vor Tabs.
Die Prüfung ohne `space-before-tab` besteht; das Leerzeichen gehört zum Unified-Diff-Format.

Status dieses Grobschritts: **STATIC AND DT COMPILE PASS / BUILD PENDING**.

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

## 26. Buildnachweis des MT7996-Kalibrationsfixes

Branch-Commit `c77e5da205cedbf4362e4b4db70043f4b3ababec` wurde im
GitHub-Actions-Run `37898648988` erfolgreich gebaut. Der PR-Merge-Ref und die
im Image vermerkte Revision lauten
`349ecd60185a1478a4977a463615a284c65540dc` beziehungsweise `349ecd6`.
Der Image-Job lief 24 Minuten und 7 Sekunden.

Das Buildprotokoll bestätigt den R4-Pro-lokalen Kernel-Patch
`001-mt76-optional-eeprom-no-sysfs-fallback`. Kernel 6.18.53 wurde damit
gebaut. Das Firmwarepaket installierte alle 15 Payloads vom unveränderten Pin
`17c8530777b28c3b909dc505b95cf895159bd8b9`.

Heruntergeladen und geprüft wurde:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
Größe: 1476395008 Bytes
SHA256: 0075bc65bc9a2548594c0618434a10464c437ff49e4d92213533c53eac06a216
```

Das GitHub-Artefakt ist 1476415745 Bytes groß. Sein SHA256 ist
`80d8bac24bd68e0575b14942506eb36fabee27e8a5384f241bed3f6215568724`.
Der vollständige ZIP-CRC-Test und die mitgelieferte `.img.sha` waren
erfolgreich.

Das Rootfs wurde ausschließlich read-only geprüft. Der Image-Checker
bestätigt extlinux mit 8X-DTB und SD-Overlay. Er bestätigt auch den
Aeonsemi-Initramfs-Hook und das gepinnte Firmware-Audit. Beide neuen Pfade
`mt7996_eeprom_2i5i6i.bin` und `mt7996_eeprom_233_2i5i6i.bin` sind vorhanden.
Der Image-Hash blieb nach dem Aushängen unverändert.

Der separate fehlende Website-Asset
`board-images/bananapir4pro8x.png` bleibt offen. Er beeinflusst den
erfolgreichen Port-Build nicht.

Status dieses Grobschritts: **BUILD PASS / HW TEST PENDING**.

## 27. SD-Vorbereitung für den MT7996-Kalibrationstest

Das in Abschnitt 26 verifizierte Image wurde auf die eindeutig identifizierte
64-GB-SD-Karte geschrieben. Das Ziel war `/dev/sdb` mit exakt 63864569856
Bytes, `RM=1`, `HOTPLUG=1`, Transport `usb`, Modell `STORAGE DEVICE` und
Serienkennung `Generic_STORAGE_DEVICE-0:0`. Die internen SATA- und
NVMe-Laufwerke waren davon klar getrennt.

Desktop-Automount wurde vor dem Aushängen deaktiviert. Unmittelbar vor dem
Schreiben war keine Partition von `/dev/sdb` eingehängt. Geschrieben wurde:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
Größe: 1476395008 Bytes (352 Blöcke zu 4 MiB)
SHA256: 0075bc65bc9a2548594c0618434a10464c437ff49e4d92213533c53eac06a216
```

`dd` schrieb 352 vollständige 4-MiB-Blöcke und schloss mit `fsync`
fehlerfrei ab. Alle Partitionen blieben vor der Rücklese ausgehängt. Genau
1476395008 Bytes wurden anschließend roh von `/dev/sdb` gelesen. Ihr SHA256
war erneut `0075bc65bc9a2548594c0618434a10464c437ff49e4d92213533c53eac06a216`.

Die SD-Karte wurde danach logisch abgeschaltet. Die ursprünglichen
Automount-Einstellungen wurden wiederhergestellt. eMMC, NAND und NOR wurden
nicht beschrieben.

Status dieses Grobschritts: **SD WRITE/READBACK PASS / HW TEST READY**.

## 28. Hardwaretest des MT7996-Kalibrationsfixes

Der UART-Logger lief vor dem Einschalten des physischen BPI-R4 Pro 8X. Der
vollständige Cold Boot ist erhalten als:

```text
UART-Log: uart-2026-10-09-c77e5da20-hw6.log
Größe: 94765 Bytes, 1228 Zeilen
SHA256: bd1b8ced5b059919ab5fba6738704194fbc226d96aca88dcd54bc27d6f81be39
```

Bestätigt wurden `WDT: Cold boot`, BL2, 8192 MiB DRAM, BL31,
U-Boot 2025.04, SD/extlinux und Linux 6.18.53. Das Rootfs wurde von
`mmcblk0p5` read/write gemountet. Beide Aeonsemi-PHYs melden Firmware 1.9.1.
Login erscheint bei 35,68 s; `multi-user.target` wird bei 37,98 s erreicht.

Der Kalibrationsfix arbeitet wie vorgesehen. `mt7996e_rf.bin` wird bei
24,86 s angefordert und endet bei 24,87 s sofort mit `-2`. Es gibt keinen
Sysfs-Fallback und keine 60-Sekunden-Pause. Bei 25,04 s nutzt der Treiber die
EEPROM-Defaults. Bei 25,04 s registriert er erfolgreich `mt76-phy0`.

Damit sind Firmwarestart und MT7996-Probe als **MT7996 PROBE HW PASS**
bestätigt. Das Log nennt den internen Default-Dateipfad beim erfolgreichen
Laden nicht erneut. Der read-only geprüfte Image-Inhalt enthält beide
gepinnten internen-FEM-Defaults.

Der Gesamtstatus bleibt unter `HW PASS`. Der früheste verbleibende explizite
Kernel-Fehler ist `mtk-xsphy` mit fehlendem `ref_clk(id-1)` bei 0,38 s.
Danach folgen der PCIe-Port `11280000` mit `-110` bei 2,87 s und xHCI
`11190000` mit `-110` bei 15,38 s. `sys-led-red` bleibt bei 35,68 s im
deferred probe. eMMC, NAND und NOR wurden nicht beschrieben.

Status dieses Grobschritts:
**MT7996 PROBE HW PASS / OTHER HW BLOCKERS REMAIN**.

## 29. PCA9555-Treiber und korrigierte Fehlerzuordnung

Die weitere Logprüfung korrigiert die erste Einordnung aus Abschnitt 28.
XS-PHY registriert bei 2,61 s den PHY mit `type_sw - reg 0x194`.
Die Clock-Meldung bei 0,38 s beschreibt einen vorübergehenden Probe-Aufschub.
Sie belegt keinen dauerhaften XS-PHY-Ausfall. Die vorherige Einordnung bleibt
zur Nachvollziehbarkeit erhalten.

PCIe `11280000` meldet `detect.quiet` und einen fehlenden Link.
Die Bestückung dieses M.2-Ports muss vor einer Fehlerbewertung geprüft werden.
Der xHCI-Timeout bei `11190000` bleibt separat offen.

Der Device Tree verbindet beide System-LEDs mit dem PCA9555 an I2C `3-0020`.
Die gebaute Konfiguration enthält `# CONFIG_GPIO_PCA953X is not set`.
Damit fehlt der Treiber für diesen GPIO-Expander.

Der Board-Hook aktiviert jetzt `GPIO_PCA953X=y`.
Der Konfigurationshash steigt auf `bpi-r4pro-8x-network-v3`.
Der Preflight prüft die neue Option. Die gemeinsame Filogic-Konfiguration bleibt unverändert.

Status dieses Grobschritts: **STATIC PASS / BUILD PENDING**.

## 30. Speicherinventar und eMMC-Testgrenze

Der SD-Boot zeigt einen Winbond SPI-NAND mit 256 MiB.
Die MTD-Partitionen heißen `bl2` und `ubi`.
UBI enthält `fip`, `ubootenv`, `ubootenv2`, `recovery`, `fit` und `emmc_install`.
Die lesend geprüften Umgebungsvolumes liefern keine passenden MAC-Adressschlüssel.
Die NVMe ist eine Patriot P300 mit 128 GB. Die Prüfung beschreibt keinen dieser Speicher.

SD und eMMC nutzen denselben Controller `11230000` mit unterschiedlichen Pins.
Das SD-Overlay setzt `no-mmc`. Das eMMC-Overlay setzt `no-sd` und acht Datenleitungen.
[Frank bestätigt die gegenseitige Auswahl beim R4 Pro](https://forum.banana-pi.org/t/banana-pi-bpi-r4-pro-when-boot-from-emmc-can-i-use-microsd-as-a-storage-device/27367).
Das fehlende eMMC-Gerät im SD-Boot belegt deshalb keinen fehlenden Chip.
Ein Overlaywechsel am laufenden SD-Root-Dateisystem ist kein sicherer Testweg.

SPI zeigt nur `spi0.0` mit `spi-nand`. SPI1 und SPI2 sind im Device Tree deaktiviert.
[Der Hersteller nennt beim Pro 8 GB eMMC und 256 MB SPI-NAND](https://www.banana-pi.com/en/bananapi-router/205.html).
Ein bestückter SPI-NOR beim Pro 8X bleibt unbelegt. Die Linux-Erkennung allein schließt unbeschriebene Hardware nicht aus.
[Der normale R4 V1.3 reserviert einen NOR-Bestückungsplatz](https://forum.banana-pi.org/t/good-news-bpi-is-releasing-bpi-r4-v1-3/27010).
[Der R4 Mini besitzt 32 MB SPI-NOR](https://docs.banana-pi.org/en/BPI-R4_Mini/BananaPi_BPI-R4_Mini).
Diese anderen Boards rechtfertigen keinen NOR-Knoten für den Pro 8X.

Das WLAN-I2C-EEPROM `6-0051` liefert 256 Bytes.
Offset `0x20` enthält `2025-06-07`. Der Rest enthält nur `00` oder `ff`.
SHA256: `cb4794f91bb479938168654598524203ab457fc5115485fb1d255dd20ec0a26c`.
Der lokale Hexdump heißt `eeprom-6-0051-2026-10-09.hex` im UART-Verzeichnis.
Die Zuordnung zur BE14 folgt dem Device-Tree-Label `wifi_eeprom`; eine physische Zuordnung bleibt offen.
Der MT76-Debugfs-Dump liefert 7680 Bytes effektiver Kalibrationsdaten.
Dieser Treiber-Dump ist kein Rohbackup eines physischen Flash-Chips.

Der nächste Test startet den vorhandenen NAND-U-Boot und stoppt dessen Autoboot.
Nur MMC-Informationen und Partitionen dürfen gelesen werden.
Keine Installation, kein `saveenv` und kein Flash-Schreibbefehl gehören zu diesem Test.
Die physische Bootauswahl und der UART-Mitschnitt sind vor dem Neustart erforderlich.

Status dieses Grobschritts: **STORAGE INVENTORY / EMMC TEST PENDING**.

Die Vorbereitung führt `sync; systemctl poweroff` aus.
Linux hängt alle Dateisysteme aus und meldet `reboot: Power down`.
TF-A meldet danach `Power-down unsupported` und einen Panic bei `0x43004898`.
Dieser Fehler betrifft den Ausschaltpfad, nicht den vorherigen SD-Boot.
Die Versorgung muss nach diesem geordneten Shutdown physisch getrennt werden.

## 31. Hersteller-NAND-Boot mit unerwarteten Schreibvorgängen

Der Nutzer startet das Board mit NAND-Bootauswahl.
BL2 meldet `mt7988-spim-nand-ubi-comb`, 8 GiB RAM und 256 MiB SPI-NAND.
Der vorhandene U-Boot ist `2024.10-OpenWrt-unknown` vom 17. Juni 2025.
Er erkennt das Modell `BananaPi BPI-R4 Pro 8X` und einen MMC-Controller.
Ein erkannter Controller belegt noch keinen erkannten eMMC-Chip.

Beide Environment-Leseversuche melden `bad CRC, using default environment`.
Danach meldet U-Boot zweimal `Saving Environment to UBI` und `Writing to UBI... done`.
Diese automatischen Schreibvorgänge erfolgen vor dem Bootmenü.
Der Bediener führt keinen Flash-Schreibbefehl und kein `saveenv` aus.
Die Aussage „kein Flash beschrieben“ gilt ausdrücklich nicht für diesen NAND-Versuch.
Der nächste Versuch muss dieses automatische Herstellerverhalten berücksichtigen.

U-Boot erzeugt außerdem eine zufällige Ethernet-MAC-Adresse.
Der Autoboot läuft vor dem Eingriff ab und startet OpenWrt Linux 6.6.93.
Die letzte erfasste Kernel-Ausgabe endet bei `0.043661` mit `work`.
Ein Linux-Prompt und eine eMMC-Identifikation fehlen.
Ein Kernelstillstand ist wegen des UART-Verbindungsfehlers noch nicht bewiesen.
Die UART-Verbindung wird mit 115200 Baud erneut geöffnet.

Die lokalen Beobachtungen stehen in `bpi-r4pro8x-uart/nand-2026-10-09-observations.md`.
Dieses Dokument enthält Tool-Auszüge, keinen vollständigen Rohmitschnitt.
Die späteren Rohmitschnitte heißen `uart-2026-10-09-nand-storage.log` und `uart-2026-10-09-nand-storage-reconnect.log`.

Status dieses Grobschritts: **NAND TEST INCOMPLETE / AUTOMATIC UBI WRITES**.

## 32. eMMC-Nachweis im Hersteller-Linux

Nach erneuter Debug-USB-Verbindung antwortet `root@OpenWrt` bei bestätigten 115200 Baud.
Der frühere UART-Abbruch belegt deshalb keinen Kernelstillstand.
Das Hersteller-System läuft mit Linux 6.6.93.
Der MMC-Treiber erkennt `8GTF4R` mit HS400 bei 3,38 Sekunden.
Der Nutzbereich enthält 15269888 Sektoren zu 512 Bytes, also 7818182656 Bytes.
`mmcblk0boot0` und `mmcblk0boot1` enthalten jeweils 4 MiB.
`mmcblk0rpmb` enthält 512 KiB.
Die CID lautet `1501003847544634520673adbce13cd1`; das Herstellungsdatum ist März 2025.

`mmc extcsd read /dev/mmcblk0` bestätigt eMMC 5.1.
Die Lebensdauerfelder A und B sowie Pre-EOL melden jeweils `0x01`.
Der Test liest nur Informationen. Er verändert keine eMMC-Partitionen oder Einstellungen.
Dieser Nachweis gilt für den Hersteller-Kernel, nicht für unseren Armbian-Kernel.

Das Hersteller-System mountet `/dev/ubi0_6` auf `/overlay` schreibbar.
Es mountet außerdem `/dev/nvme0n1p1` auf `/mnt/nvme0n1p1` schreibbar.
Nur die Prüfkommandos sind lesend. Der Hersteller-Boot ist insgesamt nicht schreibgeschützt.

Der Hersteller-Device-Tree nennt den NAND-Bereich von 2 bis 6 MiB `Factory`.
Der lesend geprüfte Header bei 2 MiB beginnt allerdings mit `UBI#`.
Der Name allein belegt daher keine MAC- oder Kalibrationsdaten.
Hersteller-Linux hängt UBI an `mtd2` ab 6 MiB ein.
Unser SD-System beschreibt UBI dagegen ab 2 MiB. Diese Layoutabweichung bleibt separat zu prüfen.
Es gibt weiterhin nur `spi0.0` mit `spi-nand`, keinen erkannten SPI-NOR.

Der Mitschnitt heißt `bpi-r4pro8x-uart/uart-2026-10-09-nand-debug-replug.log`.
Der nächste Armbian-eMMC-Test benötigt einen Root-Datenträger außerhalb des gemeinsamen SD/eMMC-Controllers.

Status dieses Grobschritts: **EMMC DETECTION PASS ON VENDOR KERNEL**.

## 33. Persistierte Zufallsadresse statt bestätigter Werks-MAC

Das Hersteller-System verwendet `92:cb:91:79:fc:94` für `eth0` und dessen LAN-Ports.
Der vorherige U-Boot-Mitschnitt bezeichnet genau diese Adresse ausdrücklich als zufällig erzeugt.
Ein lesender Zugriff auf `ubi0_1` findet jetzt `ethaddr=92:cb:91:79:fc:94`.
Die frühere SD-Prüfung fand dort keinen passenden MAC-Schlüssel.
U-Boot hat seine Zufallsadresse offenbar beim automatischen Environment-Schreiben persistiert.
Ein weiterer Boot muss deren Wiederverwendung noch bestätigen.

Der aktive Device Tree enthält diese Adresse in beiden MAC-Eigenschaften von `mac@0`.
`ethtool -P eth0` meldet dieselbe Adresse. Das beweist keine werkseitig programmierte Adresse.
`eth1` verwendet `ea:2a:2d:7b:f5:53`, `eth2` verwendet `b2:f4:99:cc:37:31`.
Beide Geräte melden `addr_assign_type=1`; `ethtool -P` meldet jeweils `not set`.
Die UCI-Netzwerkkonfiguration enthält keinen gefundenen MAC-Override.
`fw_printenv` scheitert am fehlenden `/etc/fw_env.config`; die Prüfung verändert diese Konfiguration nicht.

Status dieses Grobschritts: **PERSISTED RANDOM MAC / FACTORY MAC UNCONFIRMED**.

## 34. Boot des vorhandenen Hersteller-eMMC-Systems

Der Nutzer startet das Board mit eMMC-Bootauswahl.
BL2 und BL31 melden `mt7988-emmc-comb` und erkennen 8 GiB RAM.
U-Boot 2024.10 liest sein MMC-Environment ohne CRC-Warnung.
Der Mitschnitt zeigt hierbei keinen automatischen Environment-Schreibvorgang.
U-Boot liest das vorhandene FIT von eMMC und startet OpenWrt Linux 6.6.93.
Die Root-Konsole meldet `root@(none)`.

Linux bildet `mmcblk0p5` auf `/dev/fit0` und `/dev/fitrw` ab.
Das Root-FIT liefert SquashFS; `/dev/fitrw` liefert das schreibbare F2FS-Overlay.
Die Prüfkommandos lesen nur. Es wird kein neues Image installiert.
Der Hersteller-Boot verwendet schreibbare Dateisysteme und ist kein Schreibschutztest.
Das System meldet außerdem ein fehlendes Root-Passwort.

`eth0` verwendet `da:68:a5:94:9a:ee` mit `addr_assign_type=0`.
Diese Adresse unterscheidet sich vom NAND-Environment. Eine werkseitige Herkunft bleibt unbestätigt.
`eth1` verwendet `a6:b0:8a:c0:4d:df`, `eth2` verwendet `32:45:8d:c7:62:ec`.
Beide Geräte melden `addr_assign_type=1`.
Der eMMC-Boot prüft nicht die Wiederverwendung des separaten NAND-Environments.

U-Boot meldet beim zusätzlichen FIT-Konfigurationsversuch `Could not find configuration node` und `load of <NULL> failed`.
Der Boot setzt danach erfolgreich fort.
Linux meldet PCIe-Timeouts für `11280000` und `11290000`.
DSA meldet MTU-Fehler; INA2xx meldet einen Konfigurationsfehler mit `-6`.
MT7996 meldet wiederholte MCU-Timeouts für Nachricht `00000007`.
Diese Meldungen betreffen das vorhandene Hersteller-System, nicht den Armbian-Kernel.

Der vollständige empfangene Mitschnitt heißt `bpi-r4pro8x-uart/uart-2026-10-09-emmc-boot-01.log`.
Er enthält auch den vorherigen Hersteller-Shutdown mit TF-A-Panic bei `0x430047ec`.
Die UART-Aufzeichnung bleibt geöffnet.

Status dieses Grobschritts: **VENDOR EMMC BOOT PASS / ARMBIAN EMMC UNTESTED**.

## 35. Herkunft der eMMC-Boot-MAC-Adressen

Ein lesender Zugriff auf `mmcblk0p1` findet `ethaddr=da:68:a5:94:9a:ee`.
Diese Partition beginnt bei Sektor 8192, also 4 MiB.
U-Boot liest sein MMC-Environment erfolgreich und übergibt diese Adresse in beiden MAC-Eigenschaften von `mac@0`.
Linux und `ethtool -P eth0` melden dieselbe Adresse.
Damit ist die aktuelle Quelle das eMMC-Environment, nicht ein nachgewiesenes Werks-EEPROM.
Die Adresse ist lokal administriert. Ihre ursprüngliche Erzeugung bleibt ohne älteren Mitschnitt offen.

Die drei Ethernet-NVMEM-Verweise zeigen auf den NAND-Bereich `Factory` bei 2 MiB.
Der Knotenname `partition@180000` stimmt nicht mit dessen tatsächlichem `reg`-Offset überein.
`mac@0` verweist auf sechs Bytes bei Factory-Offset `0xffff4`.
`mac@1` verweist auf sechs Bytes bei Factory-Offset `0xfffee`.
`mac@2` verweist auf sechs Bytes bei Factory-Offset `0xffffa`.
Alle drei lesend geprüften Felder enthalten ausschließlich `ff`.
Sie enthalten keine gültigen MAC-Adressen.

`eth1` und `eth2` melden weiterhin `addr_assign_type=1` und keine permanente Adresse.
Linux nutzt dort den Zufallsfallback statt dieser ungültigen NAND-Felder.
Die auffällige Kernel-Ausgabe `65:74:68:25:64:00` entspricht nicht den tatsächlichen Interface-Adressen.
Der Hersteller-Treiber liefert hier keine verlässliche Darstellung der erzeugten Adresse.

Im weiteren Boot meldet MT7996 nach seinen Timeouts außerdem Warnungen beim Freigeben von IRQ 104.
Der vollständige Mitschnitt erhält diese Hersteller-Warnungen.
Die MAC-Prüfung verändert weder Environment noch Factory-Daten.

Status dieses Grobschritts: **MAC SOURCE TRACE PASS / FACTORY MAC UNCONFIRMED**.

## 36. Referenz-MAC und Vergleich der Hersteller-Images

Der Nutzer bestimmt `da:68:a5:94:9a:ee` als Referenz-MAC.
Diese Entscheidung ändert noch keine Netzwerkkonfiguration und behauptet keine werkseitige Herkunft.

Beide Bootlogs zeigen Linux 6.6.93 vom 17. Juni 2025.
Beide Systeme melden OpenWrt 24.10-SNAPSHOT mit unbekannter Revision.
Ihre FIT-Kernel-Payloads sind jedoch nicht identisch.
Der NAND-Kernel enthält 6744914 Bytes; der eMMC-Kernel enthält 6744266 Bytes.
Die Prüfung liest die Payloads ab FIT-Offset `0x1000` mit den zuvor erfassten FIT-Längen.
NAND-Quelle: `/dev/ubi0_4`. eMMC-Quelle: `/dev/mmcblk0p5`.
NAND-Kernel-SHA256: `3fbbe4531dc22e2458de3b7506776021e5a5e73ef9702fdc7192d99699aa2452`.
eMMC-Kernel-SHA256: `b132d610f18781ab9aeb180790e49416fec27a3e63b49c33dc975eb7834bf0e8`.

NAND verwendet ein UBIFS-Overlay; eMMC verwendet ein F2FS-Overlay.
Die beiden Bootwege laden getrennte Environments mit unterschiedlichen `ethaddr`-Werten.
Ein vollständiger Paket- oder Konfigurationsvergleich wurde nicht durchgeführt.
Der zuerst versuchte SHA1-Vergleich scheitert am fehlenden `sha1sum` im Hersteller-System.
Der anschließende SHA256-Vergleich gelingt. Alle Prüfkommandos bleiben lesend.

Status dieses Grobschritts: **VENDOR IMAGES NOT IDENTICAL**.

## 37. OpenWrt-Importer für die eMMC-MAC

Der neue Importer liest ausschließlich das eMMC-Environment des geprüften Herstellerlayouts.
Er erkennt eMMC anhand von `type=MMC` und prüft die Environment-Partition.
`fw_printenv` prüft CRC und Redundanz an einem Dateisnapshot, nicht an einer schreibbaren Environment-Konfiguration.
Environment-Warnungen und ungültige MACs führen zum Abbruch.

Der Puya P24C02A besitzt laut Hersteller 256 Bytes und acht Bytes pro Seite.
Der Device Tree beschreibt den Board-EEPROM an `0x57` mit passenden Parametern.
Der Treiber identifiziert den physischen Hersteller nicht eindeutig.
Der Importer verlangt deshalb vor dem Schreiben eine bestätigte Chipbezeichnung.
Das WLAN-EEPROM an `0x51` bleibt ausgeschlossen.

Ein port-spezifischer Datensatz belegt `0x40` bis `0x4f`.
Er enthält die binäre Basis-MAC, `R4M1` und eine POSIX-Checksumme.
Die vorhandene Board-Kennung und alle übrigen EEPROM-Bytes bleiben erhalten.
Der Standardaufruf liest nur. Schreiben verlangt `--write`, MAC-Bestätigung und ein neues persistentes Backup-Verzeichnis.
Der Importer verweigert unbekannte Header und belegte Zielbereiche.
Ein vollständiger Rücklesevergleich erkennt Änderungen außerhalb des Zielbereichs.
Er verändert keine Write-Protect-GPIOs und schreibt weder eMMC noch NAND.

Die Paketdokumentation enthält Aufruf, Datensatzformat und Sicherheitsgrenzen.
Lokale Tests prüfen gültige und ungültige MACs, Prüfsummen, kurze Daten und die EEPROM-Auswahl.
Shell-Syntax und ShellCheck bestehen. OpenWrt-Ausführung und EEPROM-Schreiben sind noch nicht hardwaregeprüft.
Das ausgeschaltete Board bleibt unverändert. Es wurde kein EEPROM-Schreibversuch ausgeführt.

Status dieses Grobschritts: **STATIC PASS / EEPROM WRITE UNTESTED**.

## 38. Board-lokaler EEPROM-Boot-Leser

Der Board-Hook installiert den MAC-Leser und aktiviert eine eigene systemd-Unit.
Die Unit lädt at24 und läuft vor `network-pre.target` sowie den unterstützten Netzwerkdiensten.
Der Leser prüft Kennung, MAC und Checksumme des Datensatzes vollständig.
Er schreibt nie EEPROM und verweigert Änderungen an bereits aktiven Interfaces.
Ein leerer Datensatz erhält das bisherige Bootverhalten.
Ein beschädigter Datensatz führt zu einem protokollierten Fehler ohne Übernahme.

`eth0` erhält die gespeicherte Basis-MAC.
Für zufällige `eth1`- und `eth2`-Adressen erzeugt SHA256 stabile, getrennte lokale Adressen.
Diese Ableitung vermeidet die Überlappung benachbarter Basis-MACs durch einfache Addition.
Vorhandene nicht-zufällige Sekundäradressen bleiben erhalten; Kollisionen führen zum Abbruch.
Eine spätere Netzwerkkonfiguration kann die Adressen weiterhin überschreiben.
Die gemeinsame Filogic-Family und der Kernel bleiben unverändert.

Der Preflight prüft die Skripte und führt isolierte Boot-Leser-Tests aus.
Die Tests ersetzen `ip` und sämtliche Sysfs-Pfade durch temporäre Fixtures.
Sie prüfen Vorschau, Übernahme, Prüfsummenfehler, aktive Interfaces und vorhandene Sekundäradressen.
Die Image-Prüfung verlangt identische installierte Skripte und eine aktivierte Unit.
Der Workflow berücksichtigt Änderungen am MAC-Paket und dessen Tests.

Der erste erweiterte Korruptionstest scheitert wegen eines unveränderten Prüfbytes bei Index 14.
Das Prüfbyte enthält bereits `ff`; derselbe Schreibwert verändert nichts.
Der korrigierte Test kippt jetzt bei jedem Byte ein Bit und besteht.
ShellCheck meldet außerdem zunächst `SC2015`; explizite Bedingungen beseitigen diese neue Meldung.
Die Board-Konfiguration benötigt beim isolierten ShellCheck weiterhin die übliche Ausnahme für externe Variablen, `SC2034`.
Die Unit-Prüfung meldet zunächst Sandbox-Einschränkungen. Die anschließende rein statische Prüfung außerhalb der Sandbox besteht.

Der vollständige lokale Preflight, ShellCheck und `systemd-analyze verify` bestehen.
Die bekannte Warnung zum leeren `BOARD_MAINTAINER` bleibt erhalten.
OpenWrt-Importer, physischer EEPROM-Schreibschutz, Programmierung und echter Armbian-Boot stehen noch aus.
Der Port enthält keine feste individuelle MAC-Adresse.

Status dieses Grobschritts: **STATIC PASS / BUILD AND HW PENDING**.

## 39. Herstellerbestätigung des EEPROM-Typs

Der Nutzer nennt den EEPROM-Abschnitt der offiziellen R4-Pro-Einstiegsanleitung.
[Die Herstellerseite benennt ausdrücklich den P24C02A](https://docs.banana-pi.org/en/BPI-R4_Pro/GettingStarted_BPI-R4_Pro#_eeprom).
Ein direkter HTML-Abruf bestätigt diese Angabe.
Damit ist der vorgesehene Chiptyp dokumentiert, ohne allein aus dem generischen at24-Treiber darauf zu schließen.
Die bisherige technische Unsicherheit über die Softwareidentifikation bleibt in der Chronik erhalten.
Die konkrete Write-Protect-Verschaltung und ein erfolgreicher Schreibversuch sind damit noch nicht bewiesen.
Der Importer behält Vorschau, ausdrückliche Bestätigung, Backup und vollständige Rückleseprüfung bei.
Das Board bleibt ausgeschaltet. Es wurde noch kein EEPROM beschrieben.

Status dieses Grobschritts: **EEPROM TYPE DOCUMENTED / WRITE UNTESTED**.

## 40. Fehlende Werkzeuge im Hersteller-OpenWrt

Der Nutzer startet erneut das vorhandene eMMC-OpenWrt.
Der Vorabcheck findet weder `od` noch `cksum` im Hersteller-Image.
Die bisherige Aussage über verfügbare Standardwerkzeuge reicht daher für dieses Image nicht aus.
Die Helfer verwenden jetzt das vorhandene `hexdump`.
Eine portable AWK-Funktion berechnet dieselbe POSIX-Checksumme wie `cksum`.
Der Datensatz bleibt binär kompatibel; vorhandene Formattests bestehen weiterhin.

Zusätzliche Tests vergleichen leere, kurze und längere Daten mit dem lokalen Referenzwerkzeug `cksum`.
Sie prüfen außerdem gemischte Binärbytes.
Der erste lokale Versuch verwendet den Funktionsnamen `xor`, den GNU AWK bereits reserviert.
Die Umbenennung in `crc_xor` beseitigt diesen Kompatibilitätsfehler.
Der vollständige lokale Preflight und ShellCheck bestehen danach.

Status dieses Grobschritts: **STATIC PASS / OPENWRT COMPATIBILITY FIX**.

## 41. Hersteller-DT und erfolgreiche Import-Vorschau

Die Skripte werden ausschließlich in das Board-Tmpfs unter `/tmp/bpi-r4pro8x-mac-preview.CoEaek` übertragen.
Ihre SHA256-Werte stimmen mit den lokalen Dateien überein.
Der erste Importversuch endet mit Exit 1 und `pagesize: No such file or directory`.
Der Hersteller-DT enthält stattdessen `page-size` mit dem Wert acht.
Frank verwendet die Standard-Eigenschaft `pagesize` mit demselben Wert.
Die EEPROM-Auswahl akzeptiert jetzt beide Schreibweisen und prüft weiterhin sämtliche Identitätsmerkmale.
Die Einbyte-Schreiboperationen bleiben unverändert.

Die erneute Vorschau endet erfolgreich mit Exit 0 und `DRY RUN: no EEPROM write`.
Sie liest `da:68:a5:94:9a:ee` aus dem CRC-geprüften redundanten eMMC-Environment.
Sie identifiziert das Board-EEPROM `3-0057` und den freien Datensatzbereich `0x40` bis `0x4f`.
Der Boot-Leser meldet in der Vorschau korrekt einen noch nicht provisionierten Datensatz.
Der vollständige EEPROM-SHA256 bleibt `3f81898302818fb2677ef35028512c44c436c3823c51480454608e1c2d095ae0`.
Es wurde keine MAC gesetzt und kein EEPROM beschrieben.

Der zweite eMMC-Boot und die Vorschau stehen im fortlaufenden `uart-2026-10-09-emmc-boot-01.log`.
Das Hersteller-OpenWrt mountet inzwischen außerdem sein NAND-Overlay unter `/mnt/ubi0_6` schreibbar.
Dieser Mount ist kein externer Backup-Datenträger.
Ein USB-Backup-Datenträger ist vor dem vorgesehenen Schreibtest noch bereitzustellen.
Die lokalen Tests unterstützen beide DT-Schreibweisen und bestehen weiterhin.

Status dieses Grobschritts: **OPENWRT IMPORT DRY-RUN PASS / WRITE PENDING**.

## 42. Externer USB-Backup-Datenträger

Der Nutzer beauftragt das Leeren des neu angeschlossenen USB-Sticks.
Das Board erkennt einen V7 Data Drive 3.0 als `/dev/sda` mit 31.457.280.512 Bytes.
Die USB-Gerätezuordnung, Herstellerkennung und Sektorzahl bestätigen das Ziel vor der Änderung.
Der Stick enthält drei alte Partitionen und eine GPT mit falscher Endposition.
OpenWrt mountet zunächst die zweite Partition unter `/mnt/sda2`.
Der Automounter wird vorübergehend gestoppt und diese Partition ausgehängt.

Eine neue GPT ersetzt die alten Partitionen durch eine Linux-Partition ab Sektor 2048.
Diese Partition erhält ext4 und das Label `EEPROM_BACKUP`.
Das Dateisystem ist unter `/mnt/usb-backup` mit Zugriffsrechten `0700` eingebunden.
Ein Schreib-/Lesetest besteht; die Testdatei wird anschließend entfernt.
Die GPT-Prüfung meldet keine Fehler.
Das leere Dateisystem enthält nur `lost+found` und bietet ungefähr 28,6 GiB freien Speicher.

Die Formatierung ist keine sichere Überschreibung aller alten Daten.
Die alten Partitionen sind nicht mehr regulär nutzbar; eine einfache Rücknahme ist nicht vorgesehen.
EEPROM, eMMC und NAND werden durch diese Vorbereitung nicht beschrieben.
Die EEPROM-Programmierung bleibt ausstehend.
Der UART-Mitschnitt enthält Identifikation, Formatierung und Prüfungen.

Status dieses Grobschritts: **USB BACKUP STORAGE PASS / EEPROM WRITE PENDING**.

## 43. Erfolgreiche EEPROM-Programmierung unter OpenWrt

Der Nutzer beauftragt den Skripttest auf dem laufenden eMMC-OpenWrt.
Die erneute Vorschau besteht und bestätigt die unveränderte EEPROM-Ausgangsdatei.
Der USB-Backup-Mount ist vorhanden; die übertragenen Skripthashes stimmen weiterhin überein.
Der Importer erhält die bestätigte Referenz-MAC `da:68:a5:94:9a:ee` und den dokumentierten Chiptyp P24C02A.

Das Backup liegt unter `/mnt/usb-backup/r4pro8x-mac-2026-10-09-test01`.
Es enthält EEPROM vor und nach dem Schreiben, eMMC-Environment, Datensatz, Herkunft und SHA256-Prüfsummen.
Der Importer programmiert ausschließlich den EEPROM-Bereich `0x40` bis `0x4f` über at24.
Die vollständige Rückleseprüfung besteht mit Exit 0.
Alle Bytes außerhalb des Datensatzes bleiben unverändert; die Herstellerkennung `R4PRO8X-BAL79687` bleibt erhalten.
Der neue EEPROM-SHA256 ist `dd0f1d1c0661af162def96bbab7ec2174564faa13245eb866cf26f9c9d1bff01`.

Die Wiederholung meldet `Already provisioned; no EEPROM write needed` und endet ebenfalls mit Exit 0.
Alle vier binären Backup-Dateien bestehen die SHA256-Prüfung.
Der Leser läuft mit `--show` erfolgreich und verändert keine Netzwerkinterfaces.
Er zeigt `eth0=da:68:a5:94:9a:ee`, `eth1=ce:4a:ab:01:4d:59` und `eth2=22:68:65:93:6d:c9`.
Die lokalen Datensatz-, Geräteauswahl- und Leser-Tests bestehen erneut.

Der UART-Mitschnitt enthält Vorschau, Programmierung, Wiederholung und Lesergebnis.
Ein wirksamer Schreibschutz verhindert diesen Versuch nicht; die konkrete Verschaltung bleibt ungeprüft.
Der Test beschreibt weder das eMMC-Environment noch NAND oder Wi-Fi-EEPROM.
Die Backup-Dateien können vertrauliche Environment-Daten enthalten und müssen privat bleiben.
Die Persistenz nach einem Cold Boot und die automatische Übernahme beim Armbian-Boot bleiben ausstehend.

Status dieses Grobschritts: **EEPROM PROVISIONING HW PASS / ARMBIAN BOOT PENDING**.

## 44. EEPROM-Persistenz und Importer unter SPI-NAND

Vor dem Bootwechsel wird der USB-Stick ausgehängt und Linux heruntergefahren.
TF-A meldet anschließend den bekannten Power-down-Panic bei `0x430047ec`.
Der Nutzer startet danach im SPI-NAND-Modus.
BL2 meldet `Cold boot` und `mt7988-spim-nand-ubi-comb`.
U-Boot lädt sein Environment erfolgreich aus UBI; Linux verwendet das UBIFS-Overlay `/dev/ubi0_6`.
Der eMMC-Controller bleibt verfügbar und meldet Gerätetyp `MMC`.

Der vollständige EEPROM-SHA256 bleibt `dd0f1d1c0661af162def96bbab7ec2174564faa13245eb866cf26f9c9d1bff01`.
Damit übersteht der programmierte Datensatz den Cold Boot unverändert.
OpenWrt mountet den USB-Stick unter `/mnt/sda1` statt `/mnt/usb-backup`.
Die vier binären Backup-Dateien bestehen weiterhin ihre SHA256-Prüfung.
OpenWrt mountet außerdem die NVMe automatisch schreibbar; die Testskripte greifen darauf nicht zu.

Die Skripte werden erneut ausschließlich ins RAM übertragen.
Der erste Transfer wird durch die UART-Zeilenbegrenzung abgeschnitten; zusätzlich fehlt `stty` im Hersteller-Image.
Kürzere Übertragungszeilen beheben den Transferfehler; alle drei Skripthashes stimmen danach mit dem Repository überein.
Erst nach dieser Prüfung werden die Skripte ausgeführt.

Die Import-Vorschau liest `da:68:a5:94:9a:ee` aus dem CRC-geprüften redundanten eMMC-Environment.
Sie meldet `Already provisioned; no EEPROM write needed` und Exit 0.
Der Aufruf mit `--write` erkennt denselben Datensatz und endet ebenfalls ohne Schreiboperation mit Exit 0.
Er erzeugt kein neues Backup-Verzeichnis; der vollständige EEPROM-Hash bleibt unverändert.
Der Leser mit `--show` besteht und zeigt dieselben drei geplanten MAC-Adressen wie unter eMMC-OpenWrt.

Das laufende OpenWrt verwendet weiterhin `eth0=92:cb:91:79:fc:94` aus seinem NAND-Bootpfad.
Der Vorschautest verändert keine aktiven Netzwerkinterfaces.
Die erste EEPROM-Programmierung aus einem NAND-Boot bleibt ungetestet; der Test löscht dafür keinen gültigen Datensatz.
Die automatische Übernahme im Armbian-Boot bleibt ebenfalls ausstehend.
Die bekannten Hersteller-MT7996-Timeouts und Probe-Warnungen erscheinen erneut im UART-Mitschnitt.

Status dieses Grobschritts: **NAND IMPORT REPEAT PASS / EEPROM PERSISTENCE PASS / ARMBIAN BOOT PENDING**.

## 45. Fortlaufende Port-MACs und fester Armbian-Fallback

Der Nutzer verlangt fortlaufende RJ45-MACs und einen festen Fallback auf Basis von `da:68:a5:94:9a:ee`.
Diese Anforderung ersetzt ausdrücklich die vorherige SHA256-Ableitung und das Überspringen leerer EEPROM-Datensätze.
Die frühere Implementierung und ihre Hardwaretests bleiben in der Chronik erhalten.

Der Bootleser übernimmt weiterhin nur einen vollständig validierten EEPROM-Datensatz.
Fehlt ein gültiger Datensatz, nutzt er die gewünschte Referenz-MAC als festen Fallback.
Das gilt auch bei nicht verfügbarem EEPROM, Lesefehlern oder ungültiger Checksumme.
Der Leser protokolliert die Quelle und warnt bei Fallback vor identischen Adressen auf mehreren Boards.
Er beschreibt niemals das EEPROM.

Die Zuordnung verwendet die Armbian-Portnamen aus Franks R4-Pro-Device-Tree.
[Der gemeinsame DT definiert Management und vier LAN-Ports](https://github.com/frank-w/BPI-Router-Linux/blob/6.18-main/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4-pro.dtsi).
[Der 8X-DT ergänzt den fünften LAN-Port und den WAN-Mux](https://github.com/frank-w/BPI-Router-Linux/blob/6.18-main/arch/arm64/boot/dts/mediatek/mt7988a-bananapi-bpi-r4-pro-8x.dts).
`eth0`, `eth1` und `eth2` erhalten Basis, Basis+1 und Basis+2.
`mgmt` erhält Basis+3; `lan0` bis `lan4` erhalten Basis+4 bis Basis+8.
Damit erhalten alle sieben RJ45-Interfaces und beide internen Switch-Controller getrennte Adressen.
Die beiden 10G-Mux-Interfaces teilen ihre Identität jeweils zwischen RJ45 und SFP.

Die Addition berücksichtigt Byteüberträge; Überlauf und Multicast-Grenzen führen vor jeder Zuweisung zum Abbruch.
Der Dienst wartet höchstens 20 Sekunden auf alle neun Interfaces.
Er prüft anschließend sämtliche Interfaces auf DOWN und verändert keine bereits aktiven Links.
Er ersetzt jetzt auch vorhandene nicht-zufällige Adressen, damit die komplette Sequenz konsistent bleibt.
Die vorhandene Board-Installation und Dienstreihenfolge bleiben bestehen; die normale Filogic-Family bleibt unverändert.

Der feste Fallback ist nicht boardspezifisch und erzeugt auf mehreren Boards identische MAC-Adressen.
Auch fortlaufende EEPROM-Basisadressen können überlappende Neunerblöcke erzeugen.
Mehrere Boards benötigen deshalb getrennte Neunerblöcke oder getrennte Layer-2-Netze.
Diese Einschränkung gilt ausdrücklich für den angeforderten Fallback, nicht nur für fehlgeschlagene Provisionierungen.

Fixture-Tests prüfen neun eindeutige Adressen, Byteüberträge, EEPROM-Vorrang und leere, beschädigte sowie fehlende Datensätze.
Sie prüfen außerdem fehlende Ports, aktive DSA-Ports, bestehende Adressen und die Unveränderlichkeit des EEPROMs.
Der vollständige lokale Preflight und ShellCheck bestehen.
Die bekannte Warnung zum leeren `BOARD_MAINTAINER` bleibt erhalten.
Das neue Image und die tatsächliche Zuweisung beim Armbian-SD-Boot sind noch nicht getestet.

Status dieses Grobschritts: **STATIC PASS / NEW IMAGE AND HW PENDING**.

## 46. Frontplattennamen und aktivierter FPC-Port

Der Nutzer legt die Frontplattennamen fest und vertauscht ausdrücklich die bisherigen internen Linux-Namen.
`eth0` bezeichnet jetzt GMAC2 zum MxL86252C; `eth1` bezeichnet GMAC0 zum internen MT7988-Switch.
GMAC1 erhält `wan`; seine Hardwarekennung bleibt unverändert.
Die vier MaxLinear-2,5G-Ports erhalten `lan1` bis `lan4`.
Der externe MT7988-1G-Port erhält `lan5`; der MaxLinear-10G-Combo erhält `lan6`.

Die Suche nach einem Frank-FPC-Overlay endet zunächst mit HTTP 404.
[Die Herstelleranleitung bestätigt anschließend FPC an Port 3 des internen MT7988-Switches](https://docs.banana-pi.org/en/BPI-R4_Pro/GettingStarted_BPI-R4_Pro#_1g_eth_fpc_connector).
Der bestehende SoC-DT enthält dafür bereits PHY, Kalibrierungszellen und Port-Anbindung.
Ein ausschließlich auf die 8X-DTS beschränkter Patch aktiviert PHY und Port und benennt ihn `fpc`.
Die gemeinsame R4-Pro-DTSI und die normale Filogic-Family bleiben unverändert.

Der Naming-Dienst liest GMAC-Hardwarekennungen aus den Sysfs-Device-Tree-Knoten.
Temporäre Namen verhindern Kollisionen beim Tausch von `eth0` und `eth1`.
Belegte Zielnamen, aktive Links, falsche Portlabels und uneindeutige GMACs führen zum Abbruch.
Der MAC-Dienst benötigt einen erfolgreichen Naming-Dienst und läuft danach vor den Netzwerkdiensten.
Die statische Unit-Prüfung scheitert zunächst an Sandbox-Socketrechten und besteht anschließend außerhalb der Sandbox.
Die neue MAC-Sequenz lautet `eth0`, `eth1`, `wan`, `lan1` bis `lan6`, `fpc`, jeweils Basis+0 bis Basis+9.
Die Frontplattenumstellung ändert damit auch bisher abgeleitete Portadressen; die EEPROM-Basis bleibt erhalten.
Combo-RJ45 und SFP teilen weiterhin ihre jeweilige Interface-Identität.

Armbians vorhandene Netplan-Muster decken `eth*`, `lan*` und `wan*` ab.
`fpc` benötigt bei Verwendung eine explizite Netzwerkkonfiguration.
Die Änderung erstellt keine Bridges, Firewallregeln oder Routerkonfiguration.
Der Nutzer belässt WLAN ausdrücklich beim Treiber; WLAN-Adressen und Kalibrierungsdaten bleiben unverändert.

Fixture-Tests prüfen den Hardwaretausch, kollisionsfreie Zwischen­namen, Wiederholung und belegte Namen sowie aktive Links.
ShellCheck meldet zunächst `SC2094` für eine zusätzliche Leseoperation innerhalb der Mapping-Schleife.
Eine vorher ermittelte Namensliste beseitigt diese neue Meldung.
Der DT-Patch besteht `git apply --check` gegen Franks unveränderte 6.18-main-Quelle.
Eine vollständige DT-Kompilierung und ein neuer Imagebuild stehen noch aus; lokal fehlt `dtc`.
CI-Run `37928486295` bestätigt nur den vorherigen, gepushten Stand als erfolgreichen Imagebuild.
Die separate PR-Asset-Prüfung schlägt weiterhin fehl; sie wird nicht durch diese Portänderung korrigiert.

Status dieses Grobschritts: **STATIC PASS / BUILD AND HW PENDING**.

## 47. Einmalige zufällige EEPROM-Erstbelegung

Der Nutzer ersetzt den gemeinsamen festen MAC-Fallback durch eine zufällige, dauerhaft gespeicherte Basis.
Der Bootleser verwendet vorhandene gültige EEPROM-Datensätze unverändert.
Bei einem leeren Datensatz erzeugt `--apply` einmalig einen zufälligen lokalen Unicast-Block.
`--show` erzeugt keine Adresse und schreibt nichts.
Die Zufallsquelle `/dev/random` wartet auf initialisierte Kernel-Entropie.
Die letzten vier Basisbits werden gelöscht; zehn Portadressen passen damit in einen getrennten 16er-Block.
Diese Zufallsvergabe reduziert Kollisionen, garantiert aber keine weltweite Eindeutigkeit.

Die Erstbelegung akzeptiert nur den bekannten Herstellerheader oder einen vollständig gelöschten 256-Byte-Chip.
Der Zielbereich `0x40` bis `0x4f` muss vollständig `ff` enthalten.
Unbekannte belegte Layouts, beschädigte Datensätze und nicht verfügbare EEPROMs führen zum Abbruch statt Überschreiben.
Die vorhandene Herstellerkennung wird nicht verändert.
Alle zehn Interfaces müssen vor der Erstbelegung vorhanden und DOWN sein.

Der Dienst sichert Daten privat unter `/var/lib/bpi-r4pro8x-mac/provision.*` und synchronisiert das Backup vor dem Schreiben.
Ein Lock verhindert gleichzeitig laufende Erstbelegungen; der separate OpenWrt-Importer darf nicht parallel laufen.
Die erneute EEPROM-Prüfung verhindert Schreiben nach zwischenzeitlichen Änderungen.
Die vollständige Rückleseprüfung verlangt unveränderte Bytes außerhalb des Datensatzes.
Ein Fehler verhindert die MAC-Zuweisung; beschädigte Teil-Schreibvorgänge werden nicht automatisch wiederholt oder zurückgesetzt.
eMMC-Environment, NAND und Wi-Fi-EEPROM bleiben außerhalb der Schreibziele.

Fixture-Tests prüfen Erstbelegung, Wiederverwendung ohne weitere EEPROM-Schreiboperation und private Backup-Prüfsummen.
Sie prüfen auch unbekannte Header, beschädigte Datensätze, fehlende EEPROMs, aktive Ports und emulierten Schreibschutz.
Ein vollständig leerer Chip wird ohne erfundene Herstellerdaten unterstützt.
Der neue Schreibschutz-Test erzeugt zunächst ShellCheck-Meldung `SC2155`; getrennte Zuweisung und Export beseitigen sie.
Der vollständige Preflight und ShellCheck bestehen danach; die bekannte Maintainer-Warnung bleibt bestehen.
Diese Tests schreiben ausschließlich temporäre Fixtures; das angeschlossene Board wird nicht verändert.
Die bereits provisionierte Hardware-MAC bleibt gültig; die neue automatische Zufalls-Erstbelegung ist noch nicht hardwaregetestet.

Status dieses Grobschritts: **STATIC PASS / RANDOM PROVISIONING HW PENDING**.

## 48. CI-Preflight: ShellCheck SC2015

CI-Run `37972445834` scheitert im Preflight; der Imagebuild startet nicht.
Der Runner meldet `SC2015` im OpenWrt-Importer und Naming-Script.
Lokales ShellCheck 0.11.0 meldet diese Hinweise zuvor nicht.
Explizite Bedingungen ersetzen beide UND/ODER-Ketten ohne Verhaltensänderung.
Der vollständige lokale Preflight besteht erneut.
Die SD-Karte ist als 63.864.569.856-Byte-USB-Gerät sichtbar und bleibt bis zum erfolgreichen Imagebuild unverändert.

Status dieses Grobschritts: **STATIC PASS / BUILD PENDING**.

## 50. Neues Image und Frontplattenidentitäten auf Hardware

CI-Run `37975601363` besteht mit Branch-Commit `5bca9ec846034c8564c0ed7d675935be4363a950`.
Der PR-Merge-Commit des Images lautet `b94e6d9ab56da1be9fdd736609bbe6c76b24f2d1`.
Das Image enthält Linux `6.18.53-current-filogic` und 15 gepinnte Firmware-Payloads.
Imagegröße: `1476395008` Bytes.
Image-SHA256: `14bb7d95874d1133945f95b3cecde55306813604a948a0f23987a63fc3301768`.
Der langsame Einzel-Download wird durch parallele Teil-Downloads ersetzt.
Einzelne Verbindungen erreichen Zeitüberschreitungen; die signierte Download-URL läuft anschließend ab.
Eine erneuerte URL ermöglicht den vollständigen Download ohne Verlust fertiger Blöcke.
ZIP-Prüfung, Image-Prüfsumme und vollständige SD-Rückleseprüfung bestehen.
Das Schreiben betrifft ausschließlich die identifizierte 64-GB-SD-Karte.

Bootlog: `uart-run-37975601363-sd-boot-01.log`.
TF-A, U-Boot, SD/extlinux, Kernel und Erstanmeldung starten erfolgreich.
Naming- und MAC-Dienst laufen erfolgreich vor den Netzwerkdiensten.
`eth0` bindet den MxL-Switch; `eth1` bindet den internen Switch.
`wan`, `lan1` bis `lan6` und `fpc` besitzen die geplanten Namen.
Alle zehn MACs entsprechen der EEPROM-Basis `da:68:a5:94:9a:ee` plus Offset 0 bis 9.
Der vorhandene EEPROM-Datensatz benötigt keine zufällige Erstbelegung.
Die Testkonten `root` und `admin` werden mit den ausdrücklich bestätigten Testpasswörtern eingerichtet.
Diese schwachen Passwörter eignen sich nicht für einen produktiven oder exponierten Betrieb.

Status: **BUILD / SD / BOOT / PORT IDENTITY PASS / WIFI FAIL**.

## 51. Wi-Fi: erneuter Probe und PCIe-Funktionsreset

Diagnoselog: `uart-run-37975601363-wifi-investigation-01.log`.
Alle 15 Firmwaredateien bestehen erneut die im Image gespeicherte SHA256-Prüfung.
Der aktuelle ROM-Patch meldet Build-Time `20260311120419a`; dies entspricht dem unsuffigierten 444-Payload.
Der frühere erfolgreiche HW6-Boot meldet `20260311120705a`; dies entspricht dem 233-Payload.
Die Dateien fehlen nicht; die unterschiedliche Variantenauswahl bleibt erklärungsbedürftig.
Der Zusammenhang zwischen Variantenauswahl und Timeout ist noch keine bestätigte Ursache.

Ein erneuter Bind-Versuch für `0000:01:00.0` scheitert mit demselben Patch-Start-Timeout.
Danach wird ausschließlich `mt7996e` entladen.
Die Wi-Fi-Funktionen `0000:01:00.0` und `0001:01:00.0` unterstützen FLR.
Beide Funktionsresets bestehen; der anschließende Treiberstart scheitert erneut mit `-11`.
Die ursprüngliche Resetmethodenliste `flr bus` wird wiederhergestellt.
WED ist deaktiviert; ein WED-Abschaltversuch erklärt deshalb diesen Fehler nicht.
`iw phy` liefert keine registrierten Radios.
Firmware, EEPROM, eMMC, NAND, NVMe und Ethernet-Konfiguration werden durch diese Tests nicht beschrieben.

Ein vollständiger Versorgungsausfall ist der nächste isolierte Test.
Ein PCIe-Funktionsreset beweist keinen vollständigen Reset der Wi-Fi-MCU.
Eine pauschale 233-Erzwingung für jedes 8X-Board bleibt ausgeschlossen.
Die Wi-Fi-Modulbestückung und automatische Erkennung müssen zusammenpassen.

Status: **WIFI FAIL / FULL POWER CYCLE PENDING**.

## 52. Board-lokale Wi-Fi-Variantendiagnose

Der zusätzliche Kernelpatch protokolliert `MT_PAD_GPIO`, die erkannte MT7996-Variante und den angeforderten ROM-Patch-Pfad.
Der Patch liegt ausschließlich im R4-Pro-8X-Patchverzeichnis.
Automatische Variantenauswahl, Firmwareinhalte und Kalibrationsdaten bleiben unverändert.
Der Preflight verlangt beide Diagnosemeldungen.
Die Patch-Anwendungsprüfung gegen Franks 6.18-main-Quelle und der lokale Preflight bestehen.
Ein neuer Kernelbuild und der Hardwaretest der Diagnosemeldungen stehen noch aus.

Status: **STATIC PASS / BUILD AND HW PENDING**.

## 53. Wi-Fi-Probe nach vollständiger Stromtrennung

Der Nutzer bestätigt die vollständige Stromtrennung und startet anschließend dasselbe SD-Image erneut.
Der Diagnosepatch aus Abschnitt 52 ist noch nicht gebaut oder auf dem Board installiert.
Der UART-Adapter wird während der Stromtrennung neu eingesteckt; die ursprüngliche Aufzeichnung endet deshalb mit einem I/O-Fehler.
`uart-run-37975601363-wifi-coldboot-02.log` enthält keinen vollständigen Bootmitschnitt.
Die neu geöffnete UART-Verbindung zeichnet ab etwa Kernelzeit 9 Sekunden auf.
Das neue Log heißt `uart-run-37975601363-wifi-coldboot-02-reconnected.log`.
BootROM, TF-A und U-Boot sind für diesen Versuch nicht aufgezeichnet.
Das SD-Rootfilesystem behält UUID `cd06581f-85c5-45fc-83a9-99b65dc6d27f`.

Bei 25,52 Sekunden meldet der ROM-Patch Build-Time `20260311120705a`; dies entspricht dem 233-Payload.
WM-, DSP- und WA-Firmware starten anschließend erfolgreich.
Der Patch-Start-Timeout tritt in diesem Versuch nicht auf.
Die optionale Kalibrationsdatei `mediatek/mt7996e_rf.bin` fehlt weiterhin.
Der Treiber verwendet anschließend die vorhandenen EEPROM-Defaults und registriert bei 26,37 Sekunden `mt76-phy0`.
`iw dev` bestätigt `phy0` und `wlan0` im Managed-Modus.
Die Treiber-MAC lautet `00:0c:43:26:60:10`; die Ethernet-MAC-Mechanik verändert diese Adresse nicht.
`iw phy` listet 2,4 GHz, 5 GHz und 6 GHz als Band 1, 2 und 4.
Mit der aktuellen globalen Länderkennung `00` sind die geprüften 6-GHz-Kanäle deaktiviert.
Länderkennung, Funkverkehr, AP-Betrieb und modulspezifische Kalibration sind noch nicht hardwarevalidiert.

Der erste Loginversuch scheitert; die Wiederholung mit denselben bestätigten Testdaten gelingt.
Naming- und EEPROM-MAC-Dienst bleiben aktiv; alle zehn Ethernet-Identitäten bleiben korrekt.
Die Stromtrennung stellt die Wi-Fi-Probe wieder her, beweist aber nicht die genaue Ursache des vorherigen Zustands.
Ein PCIe-Funktionsreset reicht im vorherigen Versuch nicht aus.
Es werden keine Firmwaredateien ersetzt und keine Varianten dauerhaft erzwungen.

Status: **WIFI PROBE HW PASS / RF TEST PENDING / WARM-BOOT RELIABILITY OPEN**.

## 54. Wi-Fi-I2C-EEPROM und Deutschland als Laufzeitregion

Der erneute vollständige EEPROM-Dump bestätigt I2C `6-0051`, Treiber `at24` und Compatible `atmel,24c02`.
Der Chip liefert 256 Bytes.
Offsets `0x00..0x1f` enthalten `ff`.
Offsets `0x20..0x29` enthalten ASCII `2025-06-07`; die Bedeutung des Datums ist nicht belegt.
Offsets `0x2a..0x3f` enthalten `00`.
Offsets `0x40..0xff` enthalten `ff`.
SHA256 bleibt `cb4794f91bb479938168654598524203ab457fc5115485fb1d255dd20ec0a26c`.
Es gibt keinen erkennbaren Länder- oder Variantendatensatz.
Franks Device Tree bindet diesen Chip als eigenständiges I2C-EEPROM ohne Wi-Fi-NVMEM-Zuordnung ein.
Das effektive MT76-EEPROM im Debugfs umfasst dagegen 7680 Bytes.
Dieses Treiberabbild ist kein Rohdump des 256-Byte-I2C-Chips.
Eigene Kennungen im I2C-Chip würden einen zusätzlichen, ausdrücklich definierten Leser benötigen.
Ein solcher Datensatz würde den bestätigten Resetfehler nicht automatisch beheben.
Der Test beschreibt weder das I2C-EEPROM noch Kalibrationsdaten.

Auf ausdrücklichen Nutzerwunsch setzt `iw reg set DE` die laufende Regulatory-Domain.
`iw reg get` bestätigt `country DE: DFS-ETSI`.
`iw phy` bestätigt Kanal 1 bei 5955 MHz und Kanal 93 bei 6415 MHz mit maximal 23 dBm.
Kanäle bei 6435 MHz und 7115 MHz bleiben deaktiviert.
Die angezeigte 6-GHz-Regel enthält `NO-OUTDOOR`.
Diese Freigabe bestätigt keinen Funkverkehr und keine korrekte modulspezifische Kalibration.
Die Änderung ist eine Laufzeiteinstellung; nach einem Neustart muss die Länderkennung erneut gesetzt werden.
Das allgemeine Image erhält keine fest eingebaute deutsche Länderkennung.

Status: **EEPROM READ-ONLY PASS / DE RUNTIME PASS / RF TEST PENDING**.

## 55. RF-Datei als externe EEPROM-Quelle erhalten

Franks `mt76_eeprom_init()` liefert nach erfolgreichem RF-Dateiladen bisher null.
MT7996 behandelt nur positive Werte als externe EEPROM-Daten.
Der Treiber löscht deshalb die geladene Datei und liest erneut eFuse.
Der neue R4-Pro-Patch liefert bei erfolgreichem Dateiladen eins.
MT7996 prüft anschließend die Chipkennung und verwendet den bestehenden externen Ladepfad.
Die vorhandene Variantenprüfung und die Ergänzung fehlender Sendeleistungswerte bleiben bestehen.
Fehlende Dateien behalten den direkten Abruf ohne Sysfs-Fallback.
OF-, eFuse- und Default-Fallback bleiben unverändert.

Der Test extrahiert beide Ladefunktionen aus gepatchten Kernelquellen.
C-Stubs simulieren Firmware-, OF- und eFuse-Zugriffe.
Der Test prüft Dateierhalt, ungültige Chipkennung, Dateifehler, OF-Daten, leere eFuse und Speicherfehler.
Der Test ersetzt keine vollständige Kernelkompilierung oder Hardwareprüfung.

```bash
bash tools/bpi-r4pro8x-rf-test.sh /pfad/zu/gepatchten/kernelquellen
```

Es wird keine generische Default-Datei als `mediatek/mt7996e_rf.bin` installiert.
Eine echte RF-Datei benötigt eine belegte Quelle und Eignung für das verbaute Modul.
Die Änderung verändert weder das laufende Board noch EEPROM, eFuse oder Flash.
Deutschland bleibt eine private Laufzeitkonfiguration und keine allgemeine Image-Vorgabe.
Die bisherige Chronik bleibt vollständig erhalten.

Die Patch-Anwendungsprüfung besteht gegen Kernel-Commit `e69eb61a1523c5e993803c05a42c55c7576b07d3` nach Patch 001.
Der erste Testaufbau scheitert an einer doppelten Typdeklaration und vorhandenen Vorzeichenwarnungen im extrahierten Kernelcode.
Die korrigierte Extraktion kompiliert; der Test deaktiviert nur diese Vorzeichenwarnungen.
Ohne Patch 004 scheitert der Dateierhalt-Test am unerwarteten eFuse-Zugriff.
Mit Patch 004 bestehen alle sieben Fälle.
Der vollständige Preflight und ShellCheck bestehen; die bekannte Maintainer-Warnung bleibt bestehen.
Ein vollständiger Kernelbuild und die Nutzung einer echten RF-Datei bleiben offen.

Die lesende Laufzeitprüfung präzisiert die frühere Aussage über EEPROM-Defaults aus Abschnitt 53.
Das aktive PCI-Gerät besitzt keinen OF-Knoten; die RF-Datei fehlt.
Der geprüfte Ladepfad liest daher eFuse und ergänzt fehlende Sendeleistungswerte aus dem passenden Default.
Der aktive Datensatz unterscheidet sich von allen vier installierten Default-Dateien.
Aktiver SHA256: `7753b19c90948c284387a83aade8278dafd40915e71f172dcbff6c6223a2d033`.
Offset `0x04` enthält `00:0c:43:26:60:10`; `wlan0` verwendet dieselbe MAC.
Die physische Herkunft und individuelle RF-Güte aller Felder bleiben ungeprüft.

Status: **STATIC / C-STUB PASS / BUILD AND HW PENDING**.
