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

## 56. Erster 6-GHz-Clienttest am Nutzer-Hotspot

Der Nutzer bestätigt angeschlossene Antennen und aktiviert einen privaten 6-GHz-Hotspot.
Die ersten passiven Scans zeigen den Hotspot nicht.
Nach erneuter Aktivierung erscheint der vollständige WLAN-Name auf 5975 MHz mit etwa -54 dBm.
Der Test verwendet weiterhin das Image aus Run `37975601363` mit Linux `6.18.53-current-filogic`.
Die Diagnose- und RF-Ladepatches sind auf dieser Hardware noch nicht installiert.

Ein separater wpa_supplicant verwaltet nur `wlan0`.
Die private Testkonfiguration nutzt WPA3-SAE, `sae_pwe=2` und verpflichtendes PMF.
Die anfängliche automatische Suche findet den Hotspot verzögert.
Der Test begrenzt anschließend Frequenz und BSSID auf den gefundenen Hotspot.
Das zusätzliche `reassociate` unterbricht die bereits begonnene Verbindung.
Der Hotspot lehnt mehrere folgende Association-Versuche mit Status 30 ab.
Ein anschließender Versuch verbindet erfolgreich; die Ablehnungen bleiben im UART-Log erhalten.

wpa_supplicant meldet `COMPLETED`, `key_mgmt=SAE`, `pmf=2` und `wifi_generation=6`.
`iw` bestätigt 5975 MHz, 160 MHz Kanalbreite und zwei räumliche Streams.
Die angezeigte TX-Linkrate beträgt 2401,9 Mbit/s; die RX-Linkrate beträgt später 1729,6 Mbit/s.
Diese Linkraten sind kein gemessener Nutzdatendurchsatz und kein Wi-Fi-7-Verbindungsnachweis.
Der Signalpegel liegt während des Pingtests bei etwa -42 dBm.

Eine temporäre networkd-Datei verwaltet ausschließlich `wlan0` und erhält eine DHCPv4-Adresse.
Die Datei übernimmt weder DHCP-Routen noch DHCP-DNS.
Die vorhandene Ethernet-Konfiguration bleibt unverändert.
Zehn Gateway-Pings bestehen mit null Prozent Verlust und durchschnittlich 6,815 ms Laufzeit.
Die Station meldet keinen Beacon-Verlust, aber sechs TX-Fehler und 1177 `rx drop misc`.
Diese kumulativen Zähler enthalten den Verbindungsaufbau; ihre Ursache ist noch nicht geklärt.
Der Test beweist keine Dauerstabilität oder vollständige RF-Kalibration.

Teststeuerung und Protokoll liegen unter `/run/r4pro-wifi-test`.
Die DHCP-Konfiguration liegt unter `/run/systemd/network/05-r4pro-wifi-test.network`.
Beide Konfigurationen verschwinden beim Neustart; die Verbindung bleibt für weitere Tests aktiv.
WLAN-Name und Passwort werden nicht in Repository oder Image eingetragen.
Deutschland bleibt privat und lokal.
Der UART-Mitschnitt heißt `uart-run-37975601363-wifi-coldboot-02-reconnected.log` und muss privat bleiben.
Der Mitschnitt enthält Testzugangsdaten.
Es werden weder EEPROM noch eFuse oder Flash beschrieben.

Status: **6GHZ CLIENT SMOKE PASS / REPEAT AND THROUGHPUT PENDING / FULL HW PASS OPEN**.

## 57. USB-Unterstützung für LoRa, Mobilfunk und HaLow

Der Nutzer bestätigt RAK5166, Quectel RM520N-GL und ALFA AHM27292U-EU als zusätzliche Bestückung.
USB erkennt Quectel `2c7c:0801` auf `2-1.1` mit 5000 Mbit/s.
Hersteller- und Produktstrings bestätigen RM520N-GL; fünf USB-Interfaces bleiben ungebunden.
Die SIM ist laut Nutzer entsperrt; der Kerneltest bestätigt den SIM-Status noch nicht.
USB erkennt ALFA `1d6b:0104` auf `1-1.2` mit 480 Mbit/s.
Die Produktstrings bestätigen `AHM27292U 802.11ah`.
Die Deskriptoren bieten RNDIS-Ethernet und eine ACM-Konsole; beide bleiben ungebunden.
USB erkennt außerdem STM32 `0483:5740` auf `1-1.4` mit 12 Mbit/s.
Diese Schnittstelle passt zum RAK5166-USB-Konzentrator; der generische Produktstring bestätigt das Modell nicht unabhängig.
[RAK beschreibt USB und SX1303 für dieses Modul](https://docs.rakwireless.com/product-categories/wislink/rak5166/datasheet/).
[Quectel dokumentiert USB-Serial und QMI/MBIM](https://quectel.com/content/uploads/2024/04/Quectel_UMTS_LTE_5G_Linux_USB_Driver_User_Guide_V3.2.pdf).
[ALFA dokumentiert das eigenständige HaLow-Modul](https://docs.alfa.com.tw/Product/AHM27292U/).

Der laufende Kernel deaktiviert `USB_ACM`, `USB_SERIAL`, `USB_USBNET`, `USB_WDM` und `RFKILL`.
`lspci` fehlt im Minimal-Image; die USB-Prüfung benötigt dieses Werkzeug nicht.
Fehlende Treiber erklären die fehlenden seriellen Geräte und USB-Netzwerkinterfaces.
Der R4-Pro-Board-Hook aktiviert folgende Optionen als Module:

```text
USB_ACM USB_SERIAL USB_SERIAL_WWAN USB_SERIAL_OPTION
USB_NET_DRIVERS USB_USBNET USB_WDM USB_NET_CDCETHER USB_NET_CDC_NCM
USB_NET_CDC_MBIM USB_NET_QMI_WWAN USB_NET_RNDIS_HOST RFKILL
```

Der Konfigurationshash steigt auf `bpi-r4pro-8x-network-v4`.
Der Preflight verlangt alle Module und den neuen Hash.
Die normale Filogic-Family und gemeinsame Kernelkonfiguration bleiben unverändert.
Der neue Imagebuild enthält auch die bisherigen Wi-Fi-Diagnose- und RF-Ladepatches.
Er installiert keine ungeprüfte RF-Datei und keine private WLAN-Konfiguration.
Der Build ändert keine Modulfirmware, SIM-Einstellungen oder Mobilfunkprofile.
LoRa-Gateway-Software und HaLow-Funkkonfiguration bleiben getrennte nächste Schritte.
Eine Mobilfunk-Datenverbindung benötigt spätere Zustimmung und einen passenden APN.
Das laufende Board und alle Flash-Speicher bleiben unverändert.

Preflight, ShellCheck und isolierter Board-Hook-Aufruf bestehen.
Ein erster ShellCheck-Aufruf ohne Shellangabe meldet SC2148; der korrekte Bash-Aufruf besteht.
Der Hook enthält alle 13 angeforderten Moduloptionen.
Die gemeinsame Kernelkonfiguration und Filogic-Family bleiben unverändert.

Status: **STATIC PASS / BUILD AND HW PENDING**.

## 58. PTP-Kernelunterstützung und Werkzeuge

Der Nutzer verlangt PTP im selben neuen Imagebuild.
Der Board-Hook aktiviert `PTP_1588_CLOCK=y` und sichert `NETWORK_PHY_TIMESTAMPING=y` ab.
Kconfig aktiviert dabei PPS und die PTP-Paketklassifizierung als Abhängigkeiten.
Die Board-Paketliste ergänzt `linuxptp` mit `ptp4l`, `phc2sys` und weiteren Diagnosewerkzeugen.
Der Konfigurationshash steigt auf `bpi-r4pro-8x-network-v5`.
Der Preflight prüft beide Optionen, das Paket und den neuen Hash.
Die gemeinsame Filogic-Konfiguration bleibt unverändert.

Die lesende Prüfung des laufenden Images meldet bei `wan` ausschließlich Software-RX-Timestamping und die Systemuhr.
`ethtool -T wan` meldet `PTP Hardware Clock: none`.
Die Prüfung für `lan1` endet mit `Operation not supported`.
`/sys/class/ptp` fehlt im aktuellen Image.
Das Aktivieren des Frameworks ergänzt keinen fehlenden Hardware-Timestamping-Treiber.
Ein PTP-Hardware-Pass bleibt ausdrücklich offen.
[linuxptp dokumentiert Software-Timestamping mit `ptp4l -S`](https://www.linuxptp.org/documentation/ptp4l/).
Die tatsächliche Portunterstützung und Synchronisationsgüte benötigen spätere Tests mit einem passenden PTP-Gegenüber.
Der Port startet keinen PTP-Dienst automatisch und verändert jetzt keine Systemuhr.
Die Änderung erfindet keine PHC und aktiviert keine fremden Clock-Treiber.

Während der lesenden Prüfung meldet der UART-Mitschnitt entfernte SFP-Module und einen Ethernet-Muxwechsel.
Aeonsemi meldet dabei IPC-Fehler `-14` und einen Polling-Timeout `-110`.
Danach bindet der WAN-PHY erneut mit Firmware 1.9.1.
Diese Laufzeitfehler treten vor Installation der neuen Konfiguration auf und bleiben separat offen.

Das Trixie-arm64-Paket `linuxptp_4.2-1+b1` wird vor dem Build geprüft.
`dpkg-deb` fehlt auf dem Host; `bsdtar` ermöglicht die anschließende Paketprüfung.
Die PTP-Dienste liegen als Templates vor; die Neuinstallation aktiviert keinen `timemaster`-Dienst.
Preflight, Bash-ShellCheck und isolierter Board-Hook-Aufruf bestehen.

Status: **STATIC PASS / BUILD AND PTP HW PENDING**.

## 59. Imagebuild für USB-Erweiterungen und PTP

GitHub-Actions-Run `37992263277` baut Branch-Commit `d99538fa6a5134777949c5b42278400fa670b7a0` erfolgreich.
Der PR-Merge-Commit lautet `a0ecc19aa90e84e84f99ee49c851bc1a21ddbf3b`.
Der Imagejob läuft 35 Minuten und 35 Sekunden.
Preflight, ShellCheck, Board-Validierung und Dependency Review bestehen.
Die separate Boardbild-Prüfung bleibt weiterhin fehlgeschlagen.

Der Buildlog bestätigt beide Wi-Fi-Patches `003-mt7996-variant-diagnostics` und `004-mt76-preserve-rf-file-eeprom`.
Der Kernel bleibt `6.18.53-current-filogic`.
Der Log bestätigt die Kompilierung und Installation von ACM, Option-Serial, QMI, MBIM, USBNet, RNDIS und rfkill.
Der PTP-Kern wird eingebaut; `linuxptp` Version `4.2-1+b1` wird im Trixie-Rootfs installiert.
Der Firmware-Pin bleibt unverändert; das Bundle enthält weiterhin 15 auditierte Payloads.

Das Image-Artefakt trägt ID `11646808458` und umfasst 1480610049 Bytes.
Der erste Einzel-Download über `gh api` folgt unerwartet dem Redirect und wird zugunsten paralleler Bereichsdownloads beendet.
Einzelne Bereichsdownloads erreichen ihr 150-Sekunden-Zeitlimit kurz vor Blockende.
Ein neuer Downloader erhält vollständige Blöcke und setzt geprüfte Teilblöcke mit längerer Zeitgrenze fort.
Die laufende Übertragung verändert noch keine SD-Daten.

Alle 177 Blöcke werden vollständig geladen.
Ein Syntaxfehler verhindert zunächst das abschließende Zusammenfügen.
Nach Korrektur bestehen ZIP-Prüfung und Image-Prüfsumme.
Das Image umfasst 1480589312 Bytes.
SHA256: `d182abfb9056b82c896e5412b7d6c72fc1ca6af05e6143882f2c2ad5dafa914e`.

Die lesende Rootfs-Prüfung bestätigt alle 13 angeforderten USB- und rfkill-Konfigurationsoptionen.
Die zwölf benötigten Moduldateien liegen komprimiert im Image vor.
PTP, PHY-Timestamping, PPS und PTP-Paketklassifizierung sind eingebaut.
`ptp4l` und `phc2sys` liegen im Image vor.
Extlinux verwendet das 8X-DTB und das SD-Overlay.
Die Firmwarequelle bleibt `pinned` bei Commit `17c8530777b28c3b909dc505b95cf895159bd8b9`.
Alle 15 Firmware-Prüfsummen bestehen.
Debugfs meldet beim unprivilegierten Export Eigentümerfehler; die exportierten Nutzdaten bestehen den vollständigen Hashvergleich.

Status: **BUILD PASS / IMAGE AUDIT PASS / HW TEST PENDING**.

## 60. USB/PTP-Image auf SD geschrieben

Der Nutzer bestätigt die Administratoranfrage für den SD-Schreibvorgang.
Der erste Versuch stoppt vor dem Schreiben durch die UUID-Schutzprüfung.
Der vorherige unprivilegierte Cachewert lautet `9e32e7f4-53cf-448a-876d-d1bd050fa5a9`.
Die tatsächlich eingelegte SD verwendet `cd06581f-85c5-45fc-83a9-99b65dc6d27f`.
Die korrigierte Schutzprüfung liest die UUID direkt mit `blkid -p`.
Größe, USB-Pfad, Modell und Gerätekennung bleiben zusätzliche Schutzprüfungen.

Das Ziel ist `/dev/sdb`, `Generic_STORAGE_DEVICE-0:0`, mit 63864569856 Bytes.
Das Image aus Run `37992263277` überschreibt das bisherige SD-Image.
Der Schreibvorgang umfasst 1480589312 Bytes und dauert rund 49 Sekunden.
Der vollständige Rücklese-Hash stimmt mit der geprüften Image-Prüfsumme überein.
SHA256: `d182abfb9056b82c896e5412b7d6c72fc1ca6af05e6143882f2c2ad5dafa914e`.
`udisksctl power-off` schaltet den Kartenleser sicher ab.
Die abschließende Geräteprüfung zeigt `/dev/sdb` nicht mehr.
Das Schreiblog liegt lokal unter `bpi-r4pro8x-flash-37992263277.log`.
eMMC, SPI-NAND, SPI-NOR und andere Host-Laufwerke bleiben unverändert.
Der nächste Schritt ist ein Cold Boot mit UART-Aufzeichnung und anschließender USB/PTP-Prüfung.

Status: **SD FLASH PASS / HW TEST PENDING**.

## 61. Erstboot des USB/PTP-Images

Am 10. Oktober 2026 startet das Image aus Run `37992263277` auf der physischen 8X-Hardware.
Der bestehende UART-Recorder bleibt aktiv, damit der Bootanfang erhalten bleibt.
Das lokale Log heißt weiterhin `bpi-r4pro8x-uart/uart-run-37975601363-wifi-coldboot-02-reconnected.log`.
Der neue Bootabschnitt beginnt bei Zeile 1700.
Der Dateiname benennt den vorherigen Run, nicht das jetzt gestartete Image.

TF-A meldet Cold Boot und 8192 MB DRAM.
U-Boot 2025.04 lädt Extlinux, das 8X-DTB und das SD-Overlay.
Linux `6.18.53-current-filogic` mountet SD-Rootfs `86d96695-2d54-463e-8ace-d14d22e7226c`.
Systemd erreicht `multi-user.target`; Armbian wartet auf die Erstlogin-Einrichtung.
Die Rootfs-Vergrößerung auf 15429632 Blöcke besteht.
Portnamen- und MAC-Dienste schließen erfolgreich ab.

Quectel bindet mit `qmi_wwan`, `wwan0`, `cdc-wdm0` und `ttyUSB0` bis `ttyUSB3`.
Das STM32-Gerät am bisherigen RAK-USB-Pfad bindet mit ACM als `ttyACM0`.
ALFA bindet mit RNDIS als `eth3` und ACM als `ttyACM1`.
ALFA trennt sich einmal während des Boots und bindet anschließend erneut.
Eine Datenverbindung oder Funkfunktion ist damit noch nicht getestet.
Der Kernel meldet `PTP clock support registered`.
Hardware-Timestamping und PTP-Synchronisation bleiben ungeprüft.

Wi-Fi meldet Variante 444 und `MT_PAD_GPIO=0x00000000`.
Der Treiber fordert `mediatek/mt7996/mt7996_rom_patch.bin` an.
Der Patchstart scheitert mit MCU-Timeout; die Probe endet mit `-11`.
Die fehlschlagende Stufe ist die Linux-Treiberinitialisierung, nicht TF-A oder U-Boot.
TF-A-Cold-Boot bestätigt keinen vollständigen Stromverlust am Wi-Fi-Modul.
Die frühere erfolgreiche 233-Erkennung bleibt als Vergleich erhalten.
Der nächste Wi-Fi-Test benötigt einen bestätigten vollständigen Stromverlust einschließlich möglicher USB-Rückspeisung.

Weitere Bootmeldungen bleiben offen: XS-PHY-Referenztakt, PCIe `11280000` und USB-Controller `11190000` mit Probe-Fehlern.
U-Boot meldet Environment-CRC-Warnungen und verwendet Defaults.
Der Kernel meldet GPT-Abweichungen vor der automatischen Rootfs-Vergrößerung und PHY-LED-Pinctrl-Fehler.
SDIO-Erkennungsbefehle melden Fehler, bevor die SD erfolgreich erkannt und gemountet wird.
Diese Meldungen verhindern den Erstlogin nicht; ihre Ursachen bleiben getrennt zu prüfen.

Status: **BOOT PASS / USB BIND PASS / WIFI FAIL / HW PARTIAL**.

## 62. Wi-Fi-Diagnose und Vorbereitung der Stromtrennung

Die Erstlogin-Einrichtung verwendet erneut die zuvor genehmigten temporären Testkonten.
Der erste Passwortvergleich scheitert; die Wiederholung besteht.
Zusätzliche Locale-Erzeugung wird übersprungen.
Das neue lokale Diagnoselog heißt `bpi-r4pro8x-uart/uart-run-37992263277-wifi-investigation-02.log`.
Das Log enthält private Testdaten und wird nicht eingecheckt.

`iw dev` und `iw phy` zeigen keine Radios.
Alle 15 Firmware-Prüfsummen bestehen auf dem laufenden Board.
Der erste Hashaufruf verwendet das falsche Arbeitsverzeichnis und prüft keine Datei.
Der korrigierte Aufruf läuft unter `/usr/lib/firmware` und bestätigt alle Dateien.
`lspci` fehlt; die anschließende Sysfs-Prüfung bestätigt PCI-Geräte `14c3:7990` und `14c3:7991`.
Die Hauptfunktion besitzt nach der fehlgeschlagenen Probe keinen gebundenen Treiber.
Die zweite Funktion bleibt an `mt7996e_hif` gebunden.
Beide Funktionen bieten weiterhin Resetmethoden `flr bus` an.
Systemd meldet keine fehlgeschlagenen Units; dies bestätigt keine erfolgreiche Wi-Fi-Probe.

Es werden keine Firmwaredateien ersetzt, Varianten erzwungen oder EEPROM-Daten verändert.
Linux synchronisiert und unmountet alle Dateisysteme für die angeforderte Stromtrennung.
Anschließend meldet TF-A `Power-down unsupported` und einen Panic bei `0x43004898`.
Das Board ist deshalb nicht nachweislich elektrisch ausgeschaltet.
Die physische Stromtrennung bleibt erforderlich.
Der nächste Test vergleicht Variantenerkennung und Firmwarestart nach vollständigem Versorgungsausfall.

Status: **WIFI FAIL / FULL POWER CYCLE PENDING**.

## 63. Wi-Fi-Kaltstart mit dem neuen Diagnosepatch

Der Nutzer bestätigt die Stromtrennung und startet das Board erneut.
`bpi-r4pro8x-uart/uart-run-37992263277-wifi-coldboot-01.log` zeichnet BootROM, TF-A, U-Boot und Linux vollständig auf.
Das Board verwendet unverändert das Image aus Run `37992263277`.
TF-A meldet Cold Boot; Linux erreicht den Login auf dem bisherigen SD-Rootfs.

Bei 26,00 Sekunden meldet MT7996 Variante 444 mit `MT_PAD_GPIO=0x00000000`.
Der Treiber fordert den unsuffigierten ROM-Patch an und meldet Build-Time `20260311120419a`.
Bei 31,12 Sekunden scheitert der Patchstart mit MCU-Timeout.
Bei 36,17 Sekunden endet die Probe mit `-11`.
`iw dev` und `iw phy` zeigen erneut keine Radios.
Alle 15 Firmware-Prüfsummen bestehen auf dem Board.
Die Stromtrennung allein reproduziert den früheren erfolgreichen 233-Start diesmal nicht.
Die Ursache ist weiterhin offen; eine fehlende Firmwaredatei erklärt diesen Versuch nicht.

Die Quellprüfung bestätigt die automatische Auswahl über Bit 19 von `MT_PAD_GPIO`.
Auch [OpenWrt mt76](https://github.com/openwrt/mt76/blob/master/mt7996/init.c) verwendet diese Auswahl vor dem MCU-Start.
Die Nullmessung beweist weder eine echte 444-Bestückung noch eine fehlerhafte Registerlesung.
Der nächste isolierte Diagnoseschritt soll Registerzugriff und Resetreihenfolge mit dem erfolgreichen Stand vergleichen.
Es werden keine Varianten erzwungen, Kalibrationsdaten verändert oder Firmwaredateien ersetzt.

Der LED-State-Dienst scheitert separat mit `Invalid state file, syntax error in configuration file`.
Dieser Fehler tritt vor dem Login auf und wird nicht als Wi-Fi-Ursache eingeordnet.
Ein erster Loginversuch enthält Terminalantworten und scheitert; der anschließende Root-Login besteht.
Das Board bleibt eingeschaltet; die UART-Aufzeichnung bleibt aktiv.

Status: **BOOT PASS / WIFI FAIL / POWER CYCLE NOT SUFFICIENT**.

## 64. Wi-Fi-Neustart und Register-Tracing

Der Nutzer beauftragt die isolierten Laufzeittests.
Das Log `bpi-r4pro8x-uart/uart-run-37992263277-wifi-coldboot-01.log` zeichnet die Tests weiter auf.
Beide PCI-Funktionen melden Runtime-Status `active`.
Die Hauptfunktion bleibt ungebunden; die zweite Funktion bindet weiterhin `mt7996e_hif`.
Die Modulparameter bieten keinen Variantenoverride an.

Entladen und erneutes Laden von `mt7996e` reproduzieren Variante 444 und den Firmware-Timeout.
`modprobe` liefert trotzdem Status null; eine erfolgreiche Modulladung bestätigt keine erfolgreiche Geräteprobe.
Der direkte Rebind scheitert ebenfalls und liefert Shellstatus eins.
`iw dev` zeigt weiterhin kein Radio.

Eine eigene Trace-Instanz `r4pro_wifi_test` erfasst ausschließlich drei relevante Registeradressen.
Der Test verändert keine fremde Trace-Instanz und deaktiviert seine Events anschließend wieder.
Der Trace erfasst alle 20 gefilterten Events ohne Pufferverlust.
Das L1-Remap-Register `0x155024` übernimmt `0x70027001` für den Resetbereich.
Der Resetregisterwert bei PCI-Offset `0x138600` wechselt `0x00010340 -> 0x00010341 -> 0x00010340`.
Die anschließende Remap-Rücklesung liefert `0x70007001` für den Variantenbereich.
Der PCI-Offset `0x1356f0` liefert `0x00000000` für `MT_PAD_GPIO` bei Adresse `0x700056f0`.
Dies bestätigt die beobachtete Registertransaktion, nicht die korrekte elektrische Strap-Erkennung.
Die genaue Ursache der abweichenden 233/444-Erkennung bleibt offen.

Status: **REGISTER TRACE PASS / WIFI FAIL**.

## 65. Fehlgeschlagener Wi-Fi-Bus-Reset

Die Geräteprüfung bestätigt ausschließlich Wi-Fi-Endpunkte unter den PCIe-Controllern `11300000` und `11310000`.
Der Test entlädt den Wi-Fi-Treiber und wählt vorübergehend Resetmethode `bus`.
Der erste Reset von `0000:01:00.0` scheitert im Kernel mit `-25`.
Der Root-Port meldet einen fehlenden aktiven Link und anschließend PCIe-AER-Completion-Timeouts.
Die Konfigurationswiederherstellung liest Nullwerte und erreicht keine erfolgreiche Geräte-Recovery.
Der Shellaufruf meldet Status eins.
Die Testsequenz schreibt anschließend die ursprüngliche Resetmethodenliste `flr bus` zurück.
Der Fehler stoppt die Sequenz vor dem zweiten Reset und vor der erneuten Treiberladung.
Weitere Bus-Reset-Versuche werden nicht ausgeführt.

Der Test fährt Linux zur sicheren Beendigung herunter.
Linux synchronisiert alle Speicher und bestätigt das Unmounten aller Dateisysteme.
TF-A meldet erneut `Power-down unsupported` mit Panic bei `0x43004898`.
Ein vollständiger physischer Stromzyklus ist vor weiteren Hardwaretests erforderlich.
Firmware, EEPROM und Bootloader bleiben unverändert.
eMMC, NAND, NOR und NVMe erhalten keine testbedingten Schreibzugriffe.
Dieser fehlgeschlagene Versuch bleibt ausdrücklich Teil der Chronik.

Status: **BUS RESET FAIL / POWER CYCLE REQUIRED**.

## 66. Wiederherstellungsboot nach dem Bus-Reset

Der Nutzer bestätigt erneut die vollständige Stromtrennung und startet das Board.
Das vollständige UART-Log heißt `bpi-r4pro8x-uart/uart-run-37992263277-wifi-recovery-coldboot-02.log`.
TF-A, U-Boot und Linux starten unverändert von SD.
Linux erreicht `multi-user.target` und den Login.
Beide Wi-Fi-PCI-Funktionen werden wieder erkannt.
Der Bootmitschnitt enthält keine erneute AER-Completion-Timeout-Serie des vorherigen Bus-Reset-Tests.
Dies bestätigt die Wiederherstellung der PCIe-Erkennung, nicht eine erfolgreiche Wi-Fi-Probe.

Bei 26,89 Sekunden meldet MT7996 erneut Variante 444 und `MT_PAD_GPIO=0x00000000`.
Der unsuffigierte ROM-Patch meldet wieder Build-Time `20260311120419a`.
Der Patchstart scheitert nach fünf Sekunden; die Probe endet bei 37,05 Sekunden mit `-11`.
Die vorherigen Probe-Fehler für PCIe `11280000` und USB `11190000` treten weiterhin separat auf.
Identische Neustarts und weitere Bus-Resets werden nicht als Lösungsweg wiederholt.
Der nächste gezielte Test benötigt Variantenregisterwerte vor und nach dem internen Wi-Fi-Reset.
Ein Vergleich mit dem früher erfolgreichen Treiberstand bleibt ebenfalls erforderlich.
Firmware und EEPROM bleiben unverändert; das Board bleibt eingeschaltet.

Status: **BOOT PASS / PCIE RECOVERY PASS / WIFI FAIL**.

## 67. Variantenregister vor und nach internem Wi-Fi-Reset

Die vorhandenen Register-Tracepoints erfassen keinen Variantenregisterwert vor dem internen Reset.
Der board-lokale Diagnosepatch `003-mt7996-variant-diagnostics.patch` ergänzt deshalb zwei Registerlesungen in `mt7996_wfsys_reset()`.
Die neue Meldung lautet `Wi-Fi reset MT_PAD_GPIO: before=... after=...`.
Der Patch erhält Resetbit, Resetreihenfolge, beide 20-ms-Wartezeiten und automatische Variantenauswahl.
Zusätzliche Registerzugriffe und die Diagnosemeldung können das zeitliche Verhalten beeinflussen.
Der Patch erzwingt keine Variante und verändert keine Firmware- oder Kalibrationsdateien.
Der Preflight verlangt die neue Diagnosemeldung.
Die gemeinsame Filogic-Family bleibt unverändert.

Ein erster Patchentwurf ist syntaktisch fehlerhaft.
Weitere Kontextprüfungen benötigen zunächst Fuzz; der korrigierte Entwurf besteht anschließend ohne Fuzz.
`git apply --check` und `patch --dry-run --fuzz=0` bestehen gegen die vorhandene Frank-6.18-Quelle.
Die bisherige Variantendiagnose liegt in dieser Quelle vier Zeilen versetzt; der Kontext stimmt vollständig überein.
Ein isolierter C-Test kompiliert die tatsächlich gepatchte Resetfunktion mit `-Wall -Wextra -Werror`.
Vier Fälle prüfen Nullwerte, gesetztes Variantenbit und beide Änderungsrichtungen über den Reset.
Alle Fälle bestätigen die Resetfolge, beide Wartezeiten und unverfälschte protokollierte Werte.
Der lokale Test liegt unter `/tmp/r4pro8x-reset-diagnostics.YHzD1t`.
Preflight, Bash-ShellCheck und Git-Whitespace-Prüfung bestehen.

Das laufende Board verwendet weiterhin das unveränderte Image aus Run `37992263277`.
Die neue Vorher/Nachher-Messung benötigt einen neuen Kernelbuild und anschließend einen Hardwaretest.
Ein Wi-Fi-Fix oder erfolgreicher Registervergleich ist damit noch nicht bestätigt.

Status: **STATIC PASS / BUILD AND RESET COMPARISON PENDING**.

## 68. Erfolgreicher Reset-Diagnosebuild

[GitHub-Run `38003437809`](https://github.com/GermanatorLM/build/actions/runs/38003437809) besteht Preflight und vollständigen Imagebau.
Der Branch-Commit lautet `641274dc35a1646f6ea7fb8f863f25ce2551a787`.
Der gebaute PR-Merge-Commit lautet `95f94932ba4cc83183495cccad880c562b16c0c8`.
Der Imagejob dauert 34 Minuten und 53 Sekunden.
Der Buildlog bestätigt den erweiterten Reset-Diagnosepatch und den bisherigen RF-EEPROM-Fix.
Kernel und Firmware-Pin bleiben unverändert.
Das Image-Artefakt trägt ID `11650893309` und umfasst als ZIP 1480610049 Bytes.
Der Download läuft mit geprüften parallelen Bereichsdownloads.
Die nachfolgende Imageprüfung soll die Vorher/Nachher-Meldung im tatsächlich gebauten Treibermodul bestätigen.
Das neue Image wird bislang auf keine SD geschrieben.

Der Nutzer verlangt während des Downloads das Herunterfahren des Boards.
Linux synchronisiert die Speicher und bestätigt `All filesystems unmounted`.
TF-A meldet anschließend erneut `Power-down unsupported` und Panic bei `0x43004898`.
Das UART-Log `uart-run-37992263277-wifi-recovery-coldboot-02.log` sichert auch diesen Shutdown.
Physische Stromtrennung bleibt erforderlich; das Linux-Dateisystem ist bereits sicher ausgehängt.

Die Übertragung stoppt nach 162 geprüften Blöcken mit HTTP-403-Fehlern und einzelnen Zeitüberschreitungen.
Ein erneuerter Downloadlink ermöglicht die restlichen 15 Blöcke ohne Verlust der geprüften Daten.
Alle 177 Blöcke, ZIP-Prüfung und Image-Prüfsumme bestehen anschließend.
Das Image umfasst 1480589312 Bytes.
SHA256: `88c43d9d1d7a750f76de830f54e36474317f9564df1d79346cf38ca6dbd1b46a`.

Die lesende Imageprüfung bestätigt USB-Module, PTP-Konfiguration, linuxptp und die SD-Extlinux-Konfiguration.
Die Firmwarequelle bleibt gepinnt; alle 15 Firmware-Prüfsummen bestehen.
Das dekomprimierte `mt7996e`-Modul enthält die neue Vorher/Nachher-Resetmeldung und die bisherige Variantendiagnose.
Debugfs meldet erneut Eigentümerfehler beim unprivilegierten Export; die exportierten Nutzdaten bestehen den Hashvergleich.
Das lokale Audit liegt unter `bpi-r4pro8x-images/run-38003437809/audit.SYCQuL`.
Die Hardwaremessung benötigt weiterhin das neue Image auf SD.

Status: **BUILD PASS / IMAGE AUDIT PASS / HW TEST PENDING**.

## 69. Reset-Diagnoseimage auf SD geschrieben

Der Nutzer bestätigt das Überschreiben der eingelegten SD mit dem neuen Diagnoseimage.
Gerätekennung, USB-Pfad, Modell und Größe identifizieren erneut ausschließlich `/dev/sdb`.
Die SD umfasst 63864569856 Bytes und meldet `Generic_STORAGE_DEVICE-0:0`.
Die direkte UUID-Schutzprüfung bestätigt das bisherige Rootfs `86d96695-2d54-463e-8ace-d14d22e7226c`.
Ein unprivilegierter Cachewert zeigt weiterhin die ältere UUID; der Schreibschutz verwendet deshalb `blkid -p`.

Das Image aus Run `38003437809` überschreibt das bisherige SD-Image nach Administratorfreigabe.
Der Schreibvorgang umfasst 1480589312 Bytes und dauert rund 49 Sekunden.
Die vollständige Rückleseprüfung stimmt mit der Image-Prüfsumme überein.
SHA256: `88c43d9d1d7a750f76de830f54e36474317f9564df1d79346cf38ca6dbd1b46a`.
`udisksctl power-off` schaltet den Kartenleser sicher ab; `/dev/sdb` verschwindet anschließend aus der Geräteliste.
Das lokale Schreiblog heißt `bpi-r4pro8x-flash-38003437809.log`.
Andere Host-Laufwerke, eMMC, NAND und NOR bleiben unverändert.
Der nächste Hardwaretest erfasst das Variantenregister vor und nach dem internen Wi-Fi-Reset beim vollständigen Kaltstart.

Status: **SD FLASH PASS / RESET COMPARISON PENDING**.

## 70. Hardwaremessung vor und nach internem Wi-Fi-Reset

Der Nutzer startet das neue Diagnoseimage aus Run `38003437809`.
Das vollständige UART-Log heißt `bpi-r4pro8x-uart/uart-run-38003437809-reset-comparison-coldboot-01.log`.
BootROM, TF-A, U-Boot und Linux starten erfolgreich auf der physischen 8X-Hardware.
Das SD-Rootfs verwendet UUID `51e89eae-8fc3-4bae-8e74-8705c056448b`.
Linux erreicht `multi-user.target`, vergrößert das Rootfs und wartet auf die Erstlogin-Einrichtung.

Bei 27,60 Sekunden meldet der neue Diagnosepatch `before=0x00000000 after=0x00000000` für `MT_PAD_GPIO`.
Die automatische Erkennung wählt anschließend weiterhin Variante 444.
Der unsuffigierte ROM-Patch meldet Build-Time `20260311120419a`.
Bei 32,80 Sekunden scheitert der Patchstart mit MCU-Timeout.
Bei 37,85 Sekunden endet die Probe nach dem Semaphore-Timeout mit `-11`.
Die früheste fehlschlagende Wi-Fi-Stufe bleibt der Linux-Firmwarestart.

Die Nullmessung liegt bereits vor dem internen Wi-Fi-Reset vor.
Dieser Versuch unterstützt daher nicht die Hypothese, dass dieser Reset erst das Variantenbit löscht.
Die Messung beweist weder korrekte Strap-Erkennung noch eine echte 444-Bestückung.
Der Patch liefert die beabsichtigte Hardwarediagnose, aber keinen Wi-Fi-Fix.
Firmwaredateien, EEPROM-Daten und Variantenauswahl bleiben unverändert.
Der nächste Vergleich soll den früher erfolgreichen Treiberstand auf derselben Hardware untersuchen.
Weitere identische Stromzyklen oder Bus-Resets ersetzen diesen Vergleich nicht.
Das Board bleibt eingeschaltet; der UART-Recorder bleibt aktiv.

Status: **BOOT PASS / RESET DIAGNOSTIC HW PASS / WIFI FAIL**.

## 71. Vollständigen Rücktest mit früher erfolgreichem Image vorbereiten

Der Nutzer bestätigt den Vergleich mit dem früher erfolgreichen Treiberstand.
Branch `bpi-r4pro-8x` und sauberer Arbeitsbaum werden vor der Vorbereitung geprüft.
PR `#1` bleibt offen; Diagnosebuild `38003437809` bleibt erfolgreich abgeschlossen.
Das lokale Image aus Run `37975601363` besteht erneut seine vollständige SHA256-Prüfung.
Das Image umfasst 1476395008 Bytes.
SHA256: `14bb7d95874d1133945f95b3cecde55306813604a948a0f23987a63fc3301768`.

Beide Images verwenden Kernelkennung `6.18.53-current-filogic`.
Die Kernelkonfigurationen unterscheiden sich bei RFKILL, USB-Treibern, PPS und PTP.
Das aktuelle Image deaktiviert `CONFIG_MODVERSIONS`.
Die gemeinsame Kernelkennung belegt deshalb keine sichere Kompatibilität einzelner Treibermodule.
Der Rücktest verwendet das vollständige ältere Image statt gemischter Kernelmodule.
Dieser Vergleich isoliert noch keinen einzelnen Patch oder Konfigurationsunterschied.
Die beiden Firmware-Auditlisten stimmen für alle 15 Payloads byteweise überein.
Die aktuellen 15 Firmwaredateien bestehen zusätzlich die Hashprüfung auf dem Board.

Die Erstlogin-Einrichtung verwendet die bereits freigegebenen temporären Testkonten.
`iw dev` zeigt weiterhin kein Radio.
Das Mainboard-EEPROM liefert SHA256 `dd0f1d1c0661af162def96bbab7ec2174564faa13245eb866cf26f9c9d1bff01`.
Das Wi-Fi-I2C-EEPROM liefert weiterhin SHA256 `cb4794f91bb479938168654598524203ab457fc5115485fb1d255dd20ec0a26c`.
Beide EEPROMs werden nur gelesen.
Das bestehende UART-Log aus Abschnitt 70 sichert die Prüfungen und den Shutdown.
Linux bestätigt `All filesystems unmounted`.
TF-A meldet erneut `Power-down unsupported` und Panic bei `0x43004898`.
Der Nutzer muss die Versorgung vollständig trennen, bevor die SD entnommen wird.

Das lokale Script `flash-r4pro8x-37975601363-comparison.sh` bereitet den geschützten SD-Rücktest vor.
Bash-Syntaxprüfung und ShellCheck bestehen.
Das Script verlangt die bekannte 64-GB-SD, Kartenleserkennung, USB-Pfad und aktuelle Rootfs-UUID.
Die erwartete UUID lautet `51e89eae-8fc3-4bae-8e74-8705c056448b`.
Es prüft Imagehash und vollständigen Rücklesehash und schaltet anschließend den Kartenleser ab.
Der Host sieht aktuell keine SD; das Script wird deshalb noch nicht ausgeführt.
Der Rücktest überschreibt später das aktuelle SD-Rootfs einschließlich temporärer Erstlogin-Konten.
Beide Originalimages und bisherigen UART-Logs bleiben lokal erhalten.
eMMC, NAND, NOR und gemeinsame Filogic-Konfiguration bleiben unverändert.
Der nächste Schritt benötigt die SD im Host-Kartenleser.
Danach muss ein vollständiger Kaltstart den ROM-Patch, Firmwarestart und `iw dev` erneut prüfen.

Status: **COMPARISON PREPARATION PASS / SD TRANSFER AND HW COMPARISON PENDING**.

## 72. Vergleichsimage auf SD geschrieben

Der Nutzer bestätigt die eingelegte SD und das stromlose Board.
Branch `bpi-r4pro-8x` und sauberer Arbeitsbaum werden erneut geprüft.
Der Host erkennt die bekannte 64-GB-SD als `/dev/sdb`.
Gerätekennung, USB-Pfad, Größe und direkte Rootfs-UUID bestehen die Schutzprüfung.
Das Vergleichsscript schreibt ausschließlich diese SD nach Administratorfreigabe.
Der Schreibvorgang umfasst 1476395008 Bytes und dauert rund 49 Sekunden.
Die vollständige Rückleseprüfung stimmt mit dem Originalimage überein.
SHA256: `14bb7d95874d1133945f95b3cecde55306813604a948a0f23987a63fc3301768`.
`udisksctl power-off` schaltet den Kartenleser sicher ab.
Das lokale Schreiblog heißt `bpi-r4pro8x-flash-37975601363-comparison.57Vbxz.log`.
Das bisherige SD-Rootfs einschließlich temporärer Erstlogin-Konten wird ersetzt.
Beide Originalimages und bisherigen UART-Logs bleiben erhalten.
eMMC, NAND, NOR und EEPROMs bleiben unverändert.

Der bisherige UART-Recorder wird gezielt beendet.
Der neue Recorder wartet bereits auf den vollständigen Vergleichs-Kaltstart.
Das neue Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-ab-comparison-coldboot-01.log`.
Der Vergleich muss zuerst ROM-Patch-Auswahl, Firmwarestart und Radio-Registrierung prüfen.
Ein Wi-Fi-Erfolg oder eine isolierte Fehlerursache ist noch nicht bestätigt.

Status: **COMPARISON SD FLASH PASS / COLD BOOT AND WIFI COMPARISON PENDING**.

## 73. Früher erfolgreiches Image reproduziert den Wi-Fi-Fehler

Der Nutzer startet das Vergleichsimage nach bestätigter Stromtrennung.
Das vollständige Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-ab-comparison-coldboot-01.log`.
BootROM, TF-A, U-Boot und Linux starten erfolgreich.
TF-A meldet Cold Boot und 8192 MB DRAM.
Extlinux verwendet das 8X-DTB, SD-Overlay und Rootfs-UUID `cd06581f-85c5-45fc-83a9-99b65dc6d27f`.
Linux erreicht `multi-user.target` und vergrößert das SD-Rootfs erfolgreich.
Die Erstlogin-Einrichtung verwendet erneut die freigegebenen temporären Testkonten.
Der ältere Kernel bindet die neu aktivierten USB-Netzwerkmodule nicht; die Erstlogin-Einrichtung meldet einen Netzwerk-Timeout.

Bei 24,26 Sekunden meldet der ROM-Patch Build-Time `20260311120419a`.
Diese Build-Time entspricht dem 444-Payload, nicht dem früher erfolgreich gestarteten 233-Payload.
Der ältere Treiber enthält keine Register- oder Firmwarepfad-Diagnose aus Patch 003.
Dieser Versuch liefert deshalb keinen direkten `MT_PAD_GPIO`-Messwert.
Bei 29,28 Sekunden scheitert der Patchstart nach MCU-Nachricht-7-Timeout.
Bei 34,33 Sekunden endet die Probe nach Semaphore-Timeout mit `-11`.
WM-, DSP- und WA-Start sowie Radio-Registrierung bleiben aus.
`iw dev` zeigt kein Radio; die Hauptfunktion bleibt ohne Treiberbindung.
Die zweite Funktion bindet weiterhin an `mt7996e_hif`.

`lspci` fehlt im Minimalimage; die lesende Sysfs-Prüfung liefert die PCIe-Daten.
Beide Funktionen melden MediaTek-IDs `14c3:7990` und `14c3:7991`, Runtime-Status `active` und PCIe 8,0 GT/s mit zwei Lanes.
Die gefilterte Dmesg-Prüfung zeigt keine PCIe-AER-Fehlerserie.
Alle 15 installierten Firmwaredateien bestehen die SHA256-Prüfung.
Beide EEPROM-Hashes stimmen mit den Messungen aus Abschnitt 71 überein.
Mainboard: `dd0f1d1c0661af162def96bbab7ec2174564faa13245eb866cf26f9c9d1bff01`.
Wi-Fi-I2C: `cb4794f91bb479938168654598524203ab457fc5115485fb1d255dd20ec0a26c`.
Portnamen- und MAC-Dienste bleiben aktiv; `systemctl --failed` listet keine fehlgeschlagenen Dienste.

Der Rücktest reproduziert den Fehler ohne die neuen Diagnosepatches, RF-Datei-Korrektur und USB/PTP-Konfiguration.
Diese Änderungen sind damit keine notwendige Voraussetzung für den beobachteten Fehler.
Der Test beweist weder einen Hardwaredefekt noch eine reine Hardwareursache.
Der frühere erfolgreiche 233-Start und 6-GHz-Test bleiben unverändert Teil der Chronik.
Weitere Bus-Resets, Firmwarewechsel und EEPROM-Schreibzugriffe werden nicht ausgeführt.
Das Board bleibt eingeschaltet; der UART-Recorder bleibt aktiv.
Ein nächster kontrollierter Hardwaretest kann externe USB-Verbindungen als mögliche Versorgungs- oder Startbedingungen ausschließen.
Dieser Test benötigt eine neue Stromtrennung und unveränderte SD sowie BE14-Bestückung.

Status: **BOOT PASS / WIFI COMPARISON FAIL / CAUSE OPEN**.

## 74. Kaltstart ohne externe USB-Geräte

Der Nutzer verlangt den Shutdown vor der Entfernung der USB-Geräte beziehungsweise Module.
Linux bestätigt im Vergleichslog aus Abschnitt 73 `All filesystems unmounted`.
TF-A meldet anschließend erneut `Power-down unsupported` und Panic bei `0x43004898`.
Der Nutzer bestätigt die Trennung und startet danach dasselbe SD-Image.
Ein separater UART-Recorder erfasst BootROM, TF-A, U-Boot und Linux vollständig.
Das Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-without-usb-coldboot-01.log`.
Linux erreicht erneut `multi-user.target` und den Login.
Der erste Login enthält Terminal-Antwortzeichen und scheitert; die Wiederholung gelingt mit denselben Testdaten.

Die USB-Sysfs-Prüfung zeigt nur Root-Hubs und Hubs `2109:2822` sowie `2109:0822`.
Die zuvor erkannten RAK-, Quectel- und ALFA-USB-Geräte fehlen.
Der Test bestätigt ihre fehlende USB-Erkennung, nicht ihren physischen Ausbau.
Beide Wi-Fi-PCIe-Funktionen bleiben mit 8,0 GT/s, zwei Lanes und Runtime-Status `active` sichtbar.
Die gefilterte Dmesg-Prüfung zeigt keine PCIe-AER-Fehlerserie.

Bei 26,68 Sekunden meldet der ROM-Patch weiterhin Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Bei 31,76 Sekunden scheitert der Patchstart nach MCU-Nachricht-7-Timeout.
Bei 36,81 Sekunden endet die Probe nach Semaphore-Timeout mit `-11`.
`iw dev` zeigt weiterhin kein Radio.
Alle 15 Firmware-Prüfsummen bestehen.
Beide EEPROM-Hashes stimmen weiterhin mit Abschnitt 73 überein.
`armbian-led-state.service` scheitert separat mit `Invalid state file, syntax error in configuration file`.
Der früheste Wi-Fi-Fehler bleibt der Linux-Firmware-Patchstart.

Die Entfernung der externen USB-Geräte stellt Wi-Fi in diesem Versuch nicht wieder her.
Ihre Anwesenheit ist damit keine notwendige Voraussetzung für den beobachteten Fehler.
Die elektrische Versorgung des BE14 und seine Strap-Erkennung bleiben ungeprüft.
Ein Hardwaredefekt ist weiterhin nicht bestätigt.
Weitere Resets, Firmwarewechsel und EEPROM-Schreibzugriffe werden nicht ausgeführt.
Das Board bleibt eingeschaltet; der UART-Recorder bleibt aktiv.
Der nächste Hardwarevergleich kann den Sitz und die Anschlüsse des BE14 prüfen.
Solche Arbeiten benötigen zuvor einen sauberen Shutdown und vollständige Stromtrennung.

Status: **BOOT PASS / USB ISOLATION NO RECOVERY / WIFI FAIL / CAUSE OPEN**.

## 75. Erfolgreicher Firmwarestart nach BE14-Neueinsetzen mit angeschlossenen Modulen

Der Nutzer prüft den BE14-Sitz nach sauberem Shutdown und setzt das Modul erneut ein.
Der Nutzer verbindet auch die anderen Module wieder und startet das Board.
Das Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-be14-reseat-coldboot-01.log`.
Die Auswertung erfolgt erst nach dem folgenden isolierten Test aus Abschnitt 76.
Dieser Boot wird nicht als isolierter BE14-Test gewertet.

Das unveränderte Vergleichsimage verwendet Rootfs-UUID `cd06581f-85c5-45fc-83a9-99b65dc6d27f`.
Bei 25,92 Sekunden meldet der ROM-Patch Build-Time `20260311120705a`, entsprechend dem 233-Payload.
WM-, DSP- und WA-Firmware starten anschließend erfolgreich.
Die optionale RF-Datei fehlt weiterhin; der Treiber verwendet EEPROM-Defaults.
Bei 26,80 Sekunden meldet der Treiber `registering led 'mt76-phy0'`.
Der Firmware-Patchstart-Timeout bleibt in diesem Boot aus.
Eine Prüfung mit `iw dev` oder ein Clienttest erfolgt vor dem angeforderten Shutdown nicht.
USB-Endpunkte erscheinen an `2-1.1`, `1-1.4` und `1-1.2`.
Linux erreicht `multi-user.target`.

Der Nutzer verlangt anschließend den Shutdown für den isolierten Test ohne die anderen Module.
Linux bestätigt `All filesystems unmounted`; TF-A meldet weiterhin `Power-down unsupported`.
Dieser Erfolg widerlegt eine durchgehend fehlschlagende Wi-Fi-Firmwareinitialisierung nach dem Neueinsetzen.
Er beweist weder einen Kontaktfehler noch einen erforderlichen Einfluss der anderen Module.
Das unveränderte Image scheitert zuvor auch mit angeschlossenen Modulen.

Status: **BOOT PASS / WIFI FIRMWARE START PASS / CLIENT UNTESTED / CAUSE OPEN**.

## 76. Isolierter Boot nach BE14-Neueinsetzen ohne andere Module

Der Nutzer bestätigt die erneut getrennten Module und startet dasselbe SD-Image.
Das vollständige Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-be14-reseat-without-usb-coldboot-01.log`.
BootROM, TF-A, U-Boot und Linux starten; Linux erreicht `multi-user.target` und Login.
Der erste Login enthält Terminal-Antwortzeichen; die Wiederholung mit denselben Testdaten gelingt.

Bei 24,22 Sekunden meldet der ROM-Patch wieder Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Bei 29,28 Sekunden scheitert der Patchstart nach MCU-Nachricht-7-Timeout.
Bei 34,33 Sekunden endet die Probe nach Semaphore-Timeout mit `-11`.
`iw dev` zeigt kein Radio.
Beide Wi-Fi-PCIe-Funktionen bleiben mit 8,0 GT/s, zwei Lanes und Runtime-Status `active` sichtbar.
USB-Sysfs zeigt nur Root-Hubs und Hubs `2109:2822` sowie `2109:0822`.
Alle 15 Firmware-Prüfsummen bestehen; beide EEPROM-Hashes stimmen weiterhin mit Abschnitt 73 überein.

Der erfolgreiche Boot aus Abschnitt 75 und dieser Fehlerboot verwenden dasselbe Image, aber unterschiedliche ROM-Payloads.
Das erneute Einsetzen allein stellt keinen reproduzierbaren Erfolg her.
Die zwei Versuche belegen noch keinen ursächlichen Einfluss der anderen Module.
Stromversorgung, Timing und automatische Variantenerkennung bleiben mögliche Untersuchungsrichtungen, nicht bestätigte Ursachen.
Ein erzwungener Variantenwechsel erfolgt nicht.
Weitere Resets und EEPROM-Schreibzugriffe erfolgen nicht.
Der nächste kontrollierte Vergleich muss einen erfolgreichen Start reproduzieren und die Variantenerkennung dabei erfassen.
Das Board bleibt eingeschaltet; UART zeichnet weiter auf.

Status: **BOOT PASS / WIFI FAIL / VARIANT CHANGE OBSERVED / CAUSE OPEN**.

## 77. Warmstart und Shutdown vor geplantem Kalt-/Warmvergleich

Der Nutzer verlangt einen Warmstart, danach Shutdown, anschließend Kaltstart und einen weiteren Warmstart.
Der erste Warmstart verwendet unveränderte SD und getrennte Erweiterungsmodule.
Das Log aus Abschnitt 76 erfasst weiterhin die gesamte Sequenz.
Linux meldet bei 223,08 Sekunden `Restarting system`.
TF-A bestätigt `Software reset (reboot)`; dieser Versuch ist kein physischer Kaltstart.
Der Warmboot beginnt im Log bei der TF-A-Meldung in Zeile 1448.

Bei 25,51 Sekunden meldet der ROM-Patch wieder Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Bei 30,56 Sekunden scheitert der Patchstart.
Bei 35,61 Sekunden endet die Probe nach Semaphore-Timeout mit `-11`.
Linux erreicht `multi-user.target`; `iw dev` zeigt kein Radio.
Der erste Login enthält Terminal-Antwortzeichen; die Wiederholung gelingt.

Der anschließend angeforderte Shutdown bestätigt `All filesystems unmounted` bei 91,47 Sekunden.
TF-A meldet erneut `Power-down unsupported` und Panic bei `0x43004898`.
Physische Stromtrennung bleibt erforderlich.
Der neue UART-Recorder wartet auf den geplanten Kaltstart.
Das neue Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-cold-then-warm-01.log`.
Nach dem bestätigten Kaltstart folgt der bereits beauftragte Warmstart mit unveränderter Bestückung.
Dieser zweite Kalt-/Warmvergleich steht noch aus.
Firmware, EEPROMs und Kernelstand bleiben unverändert.

Status: **WARM BOOT PASS / WIFI FAIL / COLD-WARM PAIR PENDING**.

## 78. Angefordertes Kalt-/Warmvergleichspaar abgeschlossen

Der Nutzer startet das Board nach der angeforderten Stromtrennung.
Das durchgehende Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-cold-then-warm-01.log`.
SD-Image, BE14 und getrennte Erweiterungsmodule bleiben während des Vergleichs unverändert.
TF-A meldet zuerst `Cold boot`.
Bei 27,67 Sekunden meldet der ROM-Patch Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Bei 32,72 Sekunden scheitert der Patchstart; bei 37,77 Sekunden endet die Probe mit `-11`.
Linux erreicht `multi-user.target`; `iw dev` zeigt kein Radio.
Die Kaltstart-Boot-ID lautet `65c191d0-b36d-46f0-b4ff-26e7df1b5b6b`.
Beide EEPROM-Hashes stimmen weiterhin mit Abschnitt 73 überein.

Der beauftragte Warmstart beginnt mit Linux-Meldung `Restarting system` bei 89,47 Sekunden.
TF-A bestätigt `Software reset (reboot)` bei Logzeile 1411.
Bei 26,66 Sekunden meldet der ROM-Patch erneut Build-Time `20260311120419a`.
Bei 31,68 Sekunden scheitert der Patchstart; bei 36,73 Sekunden endet die Probe mit `-11`.
Auch der Warmstart erreicht `multi-user.target`; `iw dev` zeigt kein Radio.
Die neue Boot-ID lautet `a2917475-08b2-456c-8d86-1710fdd693d1`.
Alle 15 Firmware-Prüfsummen und beide EEPROM-Hashes bestehen die anschließende Laufzeitprüfung.
USB-Sysfs zeigt weiterhin ausschließlich Root-Hubs und Hubs `2109:2822` sowie `2109:0822`.
Die ersten Loginversuche enthalten Terminal-Antwortzeichen; die Wiederholungen gelingen mit denselben Testdaten.

Dieses Vergleichspaar zeigt keinen Wechsel zu erfolgreicher 233-Firmware zwischen Kalt- und Warmstart.
Es widerlegt keine mögliche Timing- oder Versorgungsabhängigkeit über andere Versuche.
Der erfolgreiche 233-Start aus Abschnitt 75 bleibt als separater Befund erhalten.
Firmware, EEPROMs und Variantenauswahl werden nicht verändert.
Weitere Neustarts erfolgen nicht ohne neuen Testauftrag.
Das Board bleibt nach dem Warmstart eingeschaltet; der UART-Recorder bleibt aktiv.

Status: **COLD AND WARM BOOT PASS / WIFI FAIL / CAUSE OPEN**.

## 79. Erstes Kalt-/Warmvergleichspaar mit eingesetzten Modulen

Der Nutzer setzt die Erweiterungsmodule wieder ein und beauftragt zwei weitere Kalt-/Warmvergleichspaare.
Das erste vollständige Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-modules-cold-warm-pair1.log`.
TF-A bestätigt zuerst `Cold boot`.
USB-Sysfs bestätigt Quectel `2c7c:0801`, ALFA `1d6b:0104` und STM32 `0483:5740`.
Die Kaltstart-Boot-ID lautet `5791fe6c-e9b0-42b2-a0d7-742b2197a797`.
Bei 25,85 Sekunden meldet der ROM-Patch Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Bei 30,88 Sekunden scheitert der Patchstart; bei 35,93 Sekunden endet die Probe mit `-11`.
Linux erreicht `multi-user.target`; `iw dev` zeigt kein Radio.
Beide EEPROM-Hashes stimmen weiterhin mit Abschnitt 73 überein.

Der beauftragte Warmstart beginnt bei 82,39 Sekunden mit `Restarting system`.
TF-A bestätigt `Software reset (reboot)`.
Bei 25,58 Sekunden meldet der ROM-Patch erneut Build-Time `20260311120419a`.
Bei 30,64 Sekunden scheitert der Patchstart; bei 35,69 Sekunden endet die Probe mit `-11`.
Auch der Warmstart erreicht `multi-user.target`; `iw dev` zeigt kein Radio.
Die Warmstart-Boot-ID lautet `9a264e0e-4375-4e0e-bf6d-b3496359d56c`.
Alle 15 Firmware-Prüfsummen und beide EEPROM-Hashes bestehen die Laufzeitprüfung.
Die ersten Loginversuche enthalten Terminal-Antwortzeichen; die Wiederholungen gelingen mit denselben Testdaten.

Dieses Paar reproduziert den früheren erfolgreichen 233-Start mit angeschlossenen Modulen nicht.
Die eingesetzten Module allein garantieren damit keinen erfolgreichen Wi-Fi-Start.
Der anschließende Shutdown bestätigt `All filesystems unmounted` bei 86,71 Sekunden.
TF-A meldet erneut `Power-down unsupported` und Panic bei `0x43004898`.
Das Board benötigt physische Stromtrennung vor dem zweiten Kaltstart.
Der zweite Recorder wartet bereits unter `bpi-r4pro8x-uart/uart-run-37975601363-modules-cold-warm-pair2.log`.
SD, Module, Firmware und EEPROMs bleiben für das zweite Paar unverändert.

Status: **PAIR 1 BOOT PASS / WIFI FAIL / PAIR 2 PENDING**.

## 80. Zweites Vergleichspaar und Auswertung aller vier Starts

Der Nutzer startet das zweite Paar nach dem angeforderten Shutdown und der Aufforderung zur Stromtrennung.
Das vollständige Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-modules-cold-warm-pair2.log`.
TF-A meldet zuerst `Cold boot`; beim beauftragten Warmstart meldet TF-A `Software reset (reboot)`.
Linux startet den Warmboot bei 90,46 Sekunden mit `Restarting system`.
Beide Starts erreichen `multi-user.target`; beide Laufzeitprüfungen mit `iw dev` zeigen kein Radio.
Die Kaltstart-Boot-ID lautet `610be714-57b7-4727-aa74-2f1b0b4e715a`.
Die Warmstart-Boot-ID lautet `68ac8216-61d7-4085-b191-72cde40d87bc`.
Die ersten Loginversuche enthalten Terminal-Antwortzeichen; die Wiederholungen gelingen mit denselben Testdaten.

Alle vier Starts aus beiden Paaren melden ROM-Patch-Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Die Tabelle nennt Kernelzeiten in Sekunden innerhalb des jeweiligen Boots.

| Versuch | ROM-Patch-Meldung | Patchstart scheitert | Probe endet mit `-11` |
| --- | ---: | ---: | ---: |
| Paar 1, kalt | 25,85 | 30,88 | 35,93 |
| Paar 1, warm | 25,58 | 30,64 | 35,69 |
| Paar 2, kalt | 25,64 | 30,72 | 35,77 |
| Paar 2, warm | 25,55 | 30,64 | 35,69 |

Alle Versuche zeigen MCU-Nachricht-7-Timeout und anschließend Nachricht-10-Timeout beim Freigeben des Patch-Semaphores.
Keiner startet WM-, DSP- und WA-Firmware oder registriert ein Radio.
Die abschließende USB-Prüfung bestätigt erneut Quectel, ALFA und STM32 an denselben Pfaden wie Paar 1.
Alle 15 Firmware-Prüfsummen bestehen; beide EEPROM-Hashes stimmen weiterhin mit Abschnitt 73 überein.
Die gefilterte Dmesg-Prüfung zeigt im letzten Warmboot keine PCIe-AER-Fehlerserie.
SD, BE14, Erweiterungsmodule, Firmware und EEPROMs bleiben während des Vergleichs unverändert.

Der Vergleich zeigt keinen Erfolg durch Warmstart oder erneuten Kaltstart mit eingesetzten Modulen.
Die Anwesenheit der Module und die Startart erklären den früheren erfolgreichen 233-Start bisher nicht reproduzierbar.
Vier Versuche beweisen keinen Hardwaredefekt und schließen Timing- oder Versorgungsabhängigkeiten nicht aus.
Der 233/444-Wechsel bleibt der relevante Unterschied zwischen erfolgreichen und fehlgeschlagenen Firmwarestarts.
Eine direkte Strap-Messung fehlt im älteren Vergleichskernel.
Weitere identische Neustarts liefern derzeit keinen neuen isolierten Befund.
Der nächste Diagnoseansatz muss die Variantenerkennung bei einem erfolgreichen Start erfassen.
Das Board bleibt nach dem letzten beauftragten Warmstart eingeschaltet; UART zeichnet weiter auf.

Status: **FOUR BOOTS PASS / FOUR WIFI FAILURES / CAUSE OPEN**.

## 81. Lesende Untersuchung der Variantenauswahl

Der Nutzer beauftragt die Untersuchung nach den vier fehlgeschlagenen Starts.
Branch `bpi-r4pro-8x`, HEAD `5258a125e` und sauberer Arbeitsbaum werden geprüft.
Die lokale Frank-Quelle trägt Commit `e69eb61a1523c5e993803c05a42c55c7576b07d3`.
`mt7996_variant_type_init()` liest einmal `MT_PAD_GPIO` bei Adresse `0x700056f0`.
Bit 19, Maske `0x00080000`, wählt 233; ein nicht gesetztes Bit wählt 444.
Auch ein vollständig nullwertiges Register führt ohne gesonderte Plausibilitätsprüfung zu 444.
Die Funktion läuft vor DMA-/MCU-Initialisierung und vor Wi-Fi-EEPROM-Kalibration.
Das Mainboard-I2C-EEPROM beeinflusst diesen Auswahlpfad nicht.
[Die aktuelle mt76-Quelle](https://github.com/openwrt/mt76/blob/master/mt7996/init.c) verwendet denselben MT7996-Auswahlpfad.
Dies belegt den Auswahlmechanismus, nicht die Ursache der abweichenden Registerwerte.

`mt7996_rr()` schützt Remap-Programmierung und Nutzdatenlesen mit `reg_lock`.
Der L1-Remap führt nach dem Schreibzugriff zusätzlich einen Rücklesezugriff aus.
Eine einfache konkurrierende Remap-Transaktion ist durch die untersuchte Quelle nicht belegt.
Die früheren Tracewerte aus Abschnitt 64 bleiben der direkte Registerbefund im Fehlerzustand.
Im aktuell laufenden älteren Kernel fehlt bisher eine direkte Registermessung.
Die Hauptfunktion bleibt ungebunden und meldet PCI-Enable-Zähler null.
Ein direkter BAR-Zugriff ohne erneute Geräteaktivierung wird deshalb nicht ausgeführt.

Beide Wi-Fi-PCIe-Controller verwenden die SoC-Resetfolge mit einer 100-ms-Wartezeit vor PERST-Freigabe.
Die Board-DTSI aktiviert beide Controller, ohne zusätzliche lokale Resetverzögerung oder Wi-Fi-Versorgungszuordnung.
Regulator-Sysfs beschreibt 3,3 V, misst aber nicht die Spannung am BE14.
Die GPIO-Auswertung liefert keinen eigenen beanspruchten BE14-Power-Schalter.
Im erfolgreichen Boot aus Abschnitt 75 erscheinen die zwei PCIe-Endpunkte bei 2,75 und 3,99 Sekunden.
Im zweiten Vergleichspaar erscheinen sie beim Kaltstart bei 2,76 und 2,99 Sekunden.
Das ist eine Timing-Beobachtung, kein Nachweis einer Resetursache.
Primärfunktion vor Sekundärfunktion tritt sowohl bei Erfolg als auch bei Fehler auf.

Ein lokales Diagnosescript bereitet eine einmalige normale Treiberprobe mit eigener gefilterter Trace-Instanz vor.
Das Script heißt `bpi-r4pro8x-variant-trace-investigation.sh` und liegt außerhalb des Repositorys.
Es prüft Boardkennung, PCI-IDs und fehlende Haupttreiberbindung vor der Probe.
Es erfasst ausschließlich Remap-, Varianten- und interne Resetregistertransaktionen.
Es verändert keine Resetmethode und erzwingt keine Firmwarevariante.
Ein erster lokaler Entwurf enthält einen Syntaxrest; der korrigierte Entwurf löst zunächst ShellCheck-Warnung SC2320 aus.
Die korrigierte Statusauswertung besteht anschließend Bash-Syntaxprüfung und ShellCheck.
Die Sicherheitsprüfung verweigert die Ausführung, weil die erneute Treiberprobe den Gerätezustand verändert.
Das Script wird nicht auf dem Board ausgeführt; keine neue Trace-Instanz oder Geräteprobe entsteht.
Eine erneute Probe benötigt deshalb eine ausdrückliche Nutzerfreigabe.
Firmware, EEPROMs, Treiberbindung und globale Trace-Einstellungen bleiben unverändert.
Das Board bleibt eingeschaltet; UART zeichnet weiter auf.

Status: **SOURCE ANALYSIS PASS / CAUSE OPEN / PROBE AUTHORIZATION PENDING**.

## 82. Freigegebene Registeraufzeichnung im älteren Kernel

Der Nutzer erlaubt die Diagnoseprobe und Schreibzugriffe für das wiederherstellbare Testimage.
Die Probe läuft auf Run `37975601363`, Boot-ID `68ac8216-61d7-4085-b191-72cde40d87bc`.
Das UART-Log aus Abschnitt 80 enthält die Aufzeichnung ab Kernelzeit 607,19 Sekunden.
Die eigene Trace-Instanz heißt `r4pro_variant_investigation`.
Die Probe bindet die bereits ungebundene Hauptfunktion einmal an `mt7996e`.
Die Probe verwendet keinen PCIe-Bus-Reset und verändert keine Firmware oder EEPROMs.

Der interne Reset liest `0x138600=0x00010340`, setzt Bit 0 und löscht Bit 0 anschließend.
Der L1-Remap schreibt vor der Variantenmessung `0x155024=0x70007001`.
Der Rücklesezugriff bestätigt diesen Wert.
Der Variantenzugriff liest bei 607,273624 Sekunden `0x1356f0=0x00000000`.
Diese PCIe-Fensteradresse entspricht `MT_PAD_GPIO` bei `0x700056f0`.
Der Trace enthält alle 20 aufgezeichneten Ereignisse ohne Überlauf oder verlorene Ereignisse.
Eine Variantenmessung vor dem internen Reset fehlt in diesem älteren Kernel.

Der Treiber meldet erneut ROM-Patch-Build-Time `20260311120419a`, entsprechend dem 444-Payload.
Nachricht 7 scheitert bei 612,32 Sekunden; Nachricht 10 scheitert bei 617,36 Sekunden.
Die Probe endet erneut mit `-11`; der Sysfs-Schreibbefehl liefert Status 1.
`iw dev` zeigt weiterhin kein Radio.
Die Null-Lesung tritt damit auch ohne die neuen Diagnosepatches auf.
Der Trace beweist keine gültige 444-Hardwarevariante und erklärt die frühere 233-Auswahl noch nicht.

Die Abschlussprüfung bestätigt deaktivierte Trace-Aufzeichnung und deaktivierte Registerereignisse.
Die eigene Trace-Instanz bleibt für weitere lesende Auswertung erhalten.
Beide Wi-Fi-PCIe-Links melden weiterhin 8,0 GT/s und zwei Lanes.
Die Hauptfunktion bleibt ungebunden; die Sekundärfunktion bleibt an `mt7996e_hif` gebunden.
Die Dmesg-Prüfung zeigt keine neue PCIe-AER-Fehlerserie.
Beide EEPROM-Hashes stimmen weiterhin mit Abschnitt 73 überein.
Das Board bleibt eingeschaltet; UART zeichnet weiter auf.

Der nächste Vergleich benötigt eine direkte Registermessung bei einem erfolgreichen 233-Start.
Ein isolierter Timing-Test muss dieselbe Firmware und dieselbe Hardwarekonfiguration beibehalten.
Eine feste 233-Auswahl wäre ein Experiment, kein bestätigter allgemeiner Fix.

Status: **TRACE PASS / WIFI FAIL / CAUSE OPEN**.

## 83. Frühe Variantenaufzeichnung für den nächsten Kaltstart

Der Nutzer beauftragt die Registermessung für einen erfolgreichen 233-Start.
Ein erfolgreicher Start lässt sich bisher nicht reproduzierbar erzwingen.
Die Vorbereitung erfasst deshalb die erste reguläre Probe unabhängig von deren Ergebnis.
Die Vorbereitung verändert ausschließlich das laufende SD-Testimage aus Run `37975601363`.
Die Repository-Konfiguration und die Wi-Fi-Treiberquelle bleiben unverändert.

Das lokale Script heißt `bpi-r4pro8x-install-early-trace.sh` und liegt außerhalb des Repositorys.
Das Script prüft Boardkennung, Kernelversion und Root-UUID.
Bash-Syntaxprüfung und ShellCheck bestehen.
Das Script sichert Initramfs, U-Boot-Initramfs und extlinux-Konfiguration unter `/root/r4pro-early-trace-backup`.
Die drei Sicherungen bestehen anschließend die SHA256-Prüfung.

Ein lokaler Initramfs-Hook nimmt `mt76` und dessen Abhängigkeiten auf.
Ein lokales init-top-Script erstellt die Trace-Instanz `r4pro_early_variant`.
Der Registerfilter erfasst ausschließlich `0x155024`, `0x1356f0` und `0x138600`.
Der Trace-Puffer umfasst 128 KiB pro CPU.
Das Script meldet `R4PRO_EARLY_TRACE_READY` oder `R4PRO_EARLY_TRACE_FAILED` im Kernel-Log.
Ein Vorbereitungsfehler soll den normalen Boot nicht anhalten.
Die Trace-Vorbereitung verändert keine Resetfolge und erzwingt keine Firmwarevariante.
Das frühere Laden der Trace-Abhängigkeiten kann trotzdem das Boot-Timing beeinflussen.

`update-initramfs` erstellt den neuen Initramfs und dessen U-Boot-Version erfolgreich.
Die Generierung warnt vor fehlender `mt7981_wo.bin` für den eingebauten Ethernet-Treiber.
Diese Warnung verhindert die Generierung nicht; der Hardwaretest bleibt ausstehend.
Die extrahierte ORDER-Datei bestätigt die Trace-Vorbereitung vor udev.
Der extrahierte Initramfs enthält `mt76`, aber keinen `mt7996e`-Treiber.
Damit bleibt die eigentliche Wi-Fi-Probe außerhalb des Initramfs.
Ein zusätzlicher BusyBox-Test findet keinen BusyBox-Binary an den zwei geprüften Pfaden.
Dieser Zusatztest bleibt unbestätigt; die Script-Syntaxprüfung besteht.

Der neue Initramfs trägt SHA256 `9543703f9d50e5243b92bde7ee4e854943c1e68187ea8b6a25879a201ecf796f`.
Die U-Boot-Version trägt SHA256 `5f58624daaba46c2fb0929e24b96cda55aeeead17a9c98e60d6c543a665e829f`.
Linux fährt herunter und bestätigt vollständig ausgehängte Dateisysteme bei 833,93 Sekunden.
TF-A meldet erneut `Power-down unsupported`; die elektrische Stromtrennung bleibt erforderlich.
Das neue UART-Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-early-variant-coldboot-01.log`.
Der Recorder läuft vor dem nächsten Start.
Der Nutzer muss das Board vollständig stromlos machen und anschließend starten.
Nach dem Boot müssen Trace-Bereitschaft, Registerwerte und Firmwareauswahl gemeinsam geprüft werden.

Status: **EARLY TRACE PREPARED / COLD BOOT PENDING**.

## 84. Fehlende Initramfs-Programme und lokaler Diagnosefix

Der Nutzer meldet den Start.
Der UART-Adapter verschwindet während der Stromtrennung; der Recorder endet mit einem Ein-/Ausgabefehler.
Der Adapter erscheint anschließend als `ttyACM1` unter demselben stabilen Gerätepfad.
Die neue Aufzeichnung beginnt erst während des Linux-Starts.
Das Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-early-variant-coldboot-01-reconnected.log`.
Ein vollständiges BootROM-/TF-A-Log fehlt für diesen Versuch.
Die Boot-ID lautet `7640ed9d-33d7-484b-8cb3-9b97c7e04808`.

Das init-top-Script scheitert vor der Trace-Einrichtung an fehlenden Programmen `tr` und `grep`.
Die Boardprüfung verlässt deshalb das Script; die frühe Trace-Instanz entsteht nicht.
Die vorherige Prüfung bestätigt die Scriptreihenfolge, aber nicht alle benötigten Initramfs-Programme.
Der Versuch liefert keine frühe Variantenmessung.
Linux erreicht trotzdem `multi-user.target`.
Wi-Fi meldet wieder 444-Build-Time `20260311120419a` bei 25,97 Sekunden.
Patchstart und Semaphore-Freigabe scheitern; die Probe endet bei 36,09 Sekunden mit `-11`.
`iw dev` zeigt kein Radio.
USB-Controller `11190000.usb` meldet instabile Takte und Probe-Fehler `-110`.
Dieser Zusatzbefund erklärt den Wi-Fi-Fehler bisher nicht.

Das lokale Fixscript heißt `bpi-r4pro8x-fix-early-trace.sh`.
Der Hook nimmt `tr`, `grep`, `mkdir`, `mount` und `modprobe` samt Bibliotheken ausdrücklich auf.
Die ursprüngliche Hook-Version bleibt unter `/root/r4pro-early-trace-backup/trace-hook-before-exec-fix` erhalten.
Der neue Initramfs enthält alle fünf ausführbaren Programme.
Ein chroot-Test im extrahierten Initramfs bestätigt die Boardprüfung mit NUL-getrennter Kennung.
Ein zusätzlicher chroot-Test bestätigt ausführbares `modprobe`, kmod-Version 34.2.
Die ORDER-Datei bestätigt weiterhin die Trace-Vorbereitung vor udev.
Die Script-Ausführung im laufenden Linux meldet `R4PRO_EARLY_TRACE_READY` bei 134,16 Sekunden.
Die Filterprüfung bestätigt die drei gewünschten Registeradressen.
Dieser Laufzeittest ersetzt keine frühe Bootmessung.
Die Testaufzeichnung und beide Ereignisse werden anschließend deaktiviert.
Beide EEPROM-Hashes bleiben unverändert.

Der korrigierte Initramfs trägt SHA256 `1768f8a2c5fbe254b747a25a826daac1a9403c4d4884c1cf48d7e39f8edab141`.
Die U-Boot-Version trägt SHA256 `6d3e2e1dabcdf0d5e3fe625525f4f392150424b06df913260807a1ebd1dc1394`.
Der nächste Kaltstart muss die frühe Bereitschaftsmeldung und den Registertrace bestätigen.
Linux bestätigt vollständig ausgehängte Dateisysteme bei 137,64 Sekunden.
TF-A meldet erneut `Power-down unsupported`; eine elektrische Stromtrennung bleibt erforderlich.
Der neue Recorder verbindet sich nach einem USB-Geräteverlust automatisch erneut.
Jede Verbindung erhält ein eigenes zeitgestempeltes Log mit Präfix `uart-run-37975601363-early-variant-coldboot-02-`.
Bestehende Logs bleiben erhalten.

Status: **BOOT PASS / WIFI FAIL / TRACE FIX PREPARED / COLD BOOT PENDING**.

## 85. Frühe Registermessung beim bestätigten Kaltstart

Der Nutzer startet das Board mit unveränderter Modulkonfiguration.
Der Recorder erfasst BootROM, TF-A, U-Boot und Linux ohne Verbindungsabbruch.
TF-A meldet `Cold boot`; U-Boot bestätigt die Initramfs-Prüfsumme.
Das Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-early-variant-coldboot-02-20261010T013624.log`.
Die Boot-ID lautet `a7b3ee66-fdd4-42a9-a475-f3e5fd1998ce`.
Linux erreicht `multi-user.target`.

Die korrigierte Vorbereitung meldet `R4PRO_EARLY_TRACE_READY` bei 16,307024 Sekunden.
Diese Meldung liegt vor der ersten regulären Wi-Fi-Probe bei 24,75 Sekunden.
Die Trace-Instanz enthält 20 Ereignisse ohne Überlauf oder verlorene Ereignisse.
Der interne Reset setzt und löscht Bit 0 im Register `0x138600`.
Der vorherige Registerwert lautet `0x00010340`.
Der L1-Remap schreibt `0x155024=0x70007001` und bestätigt diesen Wert durch Rücklesen.
Die Variantenmessung liest `0x1356f0=0x00000000` bei 24,843835 Sekunden.
Diese Fensteradresse entspricht `MT_PAD_GPIO` bei `0x700056f0`.
Eine Variantenmessung vor dem internen Reset fehlt weiterhin im älteren Kernel.

Der Treiber meldet den 444-Payload mit Build-Time `20260311120419a` bei 24,919018 Sekunden.
Patchstart scheitert bei 30,002730 Sekunden; die Probe endet bei 35,049301 Sekunden mit `-11`.
`iw dev` zeigt kein Radio.
Die Hauptfunktion bleibt ungebunden; die Sekundärfunktion bleibt an `mt7996e_hif` gebunden.
Beide Wi-Fi-PCIe-Links melden 8,0 GT/s und zwei Lanes.
Die gefilterte Prüfung zeigt keine PCIe-AER-Fehlerserie.
Die EEPROM-Hashes bleiben unverändert.
Quectel, ALFA und STM32 erscheinen erneut an den erwarteten USB-Pfaden.

USB-Controller `11190000.usb` meldet erneut instabile Takte und Probe-Fehler `-110`.
Ein weiterer PCIe-Controller `11280000.pcie` scheitert ebenfalls mit `-110`.
Diese Zusatzbefunde betreffen nicht die zwei erfolgreich enumerierten Wi-Fi-PCIe-Endpunkte.
Eine gemeinsame Takt- oder Versorgungsursache bleibt unbewiesen.

Die Abschlussprüfung bestätigt deaktivierte Trace-Aufzeichnung und deaktivierte Registerereignisse.
Die Trace-Instanz bleibt erhalten; das Board bleibt eingeschaltet.
Der Diagnose-Initramfs aktiviert die frühe Aufzeichnung erneut beim nächsten Boot.
Ein erfolgreicher 233-Start wurde nicht erreicht und nicht direkt gemessen.
Die Vorbereitung funktioniert jetzt; weitere identische Neustarts ersetzen keinen isolierten Vergleich.
Der nächste Diagnoseversuch sollte genau einen Timing- oder Initialisierungsparameter verändern.
Eine feste 233-Auswahl bleibt ein gesondertes Experiment, kein bestätigter allgemeiner Fix.

Status: **BOOT PASS / EARLY TRACE PASS / WIFI FAIL / CAUSE OPEN**.

## 86. Isolierter Timing-Test mit verzögerter erster Probe

Der Nutzer beauftragt den vorgeschlagenen Timing-Test.
Branch `bpi-r4pro-8x` und sauberer Arbeitsbaum werden geprüft.
Der Test verändert nur das laufende SD-Image aus Run `37975601363`.
Firmware, EEPROMs, Kernel, Initramfs und interne Resetfolge bleiben unverändert.
Die Modulkonfiguration enthält bisher keine ausdrückliche `mt7996e`-Ladeanweisung.

Das lokale Installationsscript heißt `bpi-r4pro8x-install-delayed-wifi.sh`.
ShellCheck besteht; bestehende Zieldateien würden die Installation verhindern.
`/etc/modprobe.d/r4pro-delayed-wifi.conf` setzt `blacklist mt7996e` für automatische Alias-Ladevorgänge.
Die explizite Modulanforderung bleibt zulässig.
Ein Timer fordert die erste Probe etwa 90 Sekunden nach dem Boot an.
Die Genauigkeit beträgt eine Sekunde; die tatsächliche Startzeit wird im Kernel-Log erfasst.
Der Timer wird aktiviert, aber im aktuellen Boot nicht gestartet.
`systemctl` bestätigt `enabled` und `inactive` vor dem Shutdown.
Script-Syntaxprüfung und `systemd-analyze verify` bestehen.

Das Probescript prüft die frühe Trace-Instanz und fehlendes Modul `mt7996e`.
Es prüft außerdem fehlende Treiberbindungen beider Wi-Fi-PCIe-Funktionen.
Eine unerwartete frühere Probe führt zum Abbruch statt zu einer weiteren Probe.
Das Script protokolliert `R4PRO_DELAYED_FIRST_PROBE_START` mit tatsächlicher Uptime.
Die explizite Modulanforderung lädt den unveränderten Treiber einmal.
`modprobe`-Erfolg allein beweist keinen erfolgreichen PCIe-Geräteprobevorgang.
Das Script sichert Registertrace, Pufferstatistik, Dmesg und `iw dev` unter `/root/r4pro-delayed-wifi-<Boot-ID>`.
Nach der Probe deaktiviert das Script die eigene Trace-Aufzeichnung und beide Registerereignisse.
Der Dienst verwendet ein Zeitlimit von 45 Sekunden.

Der Test verzögert beide Wi-Fi-Funktionen, da derselbe Modulname deren Treiber bereitstellt.
Er verändert den Zeitpunkt der Treiberinitialisierung, nicht die frühe PCIe-Enumeration.
Der Test beweist bei Erfolg noch keinen allgemeinen Fix.
Bei Abbruch müssen frühe Modulanforderungen untersucht werden.

Linux bestätigt vollständig ausgehängte Dateisysteme bei 228,94 Sekunden.
TF-A meldet erneut `Power-down unsupported`; der Nutzer muss die Versorgung elektrisch trennen.
Der Recorder erhält eigene Logs mit Präfix `uart-run-37975601363-delayed-first-probe-`.
Er verbindet sich nach USB-Geräteverlust automatisch erneut.
Der nächste Versuch benötigt einen vollständigen Kaltstart mit unveränderten Modulen.
Der Nutzer muss nach dem Einschalten mindestens etwa 105 Sekunden für Probe und Ergebnisaufzeichnung einplanen.

Status: **DELAYED FIRST PROBE PREPARED / COLD BOOT PENDING**.

## 87. Ergebnis der verzögerten ersten Wi-Fi-Probe

Der Nutzer startet das Board.
Der Recorder erfasst BootROM, TF-A, U-Boot und Linux; TF-A meldet `Cold boot`.
Das Log heißt `bpi-r4pro8x-uart/uart-run-37975601363-delayed-first-probe-20261010T014146.log`.
Die Boot-ID lautet `1d2844be-e60c-46a3-a0f9-f6c091811307`.
Die frühe Trace-Vorbereitung meldet Bereitschaft bei 16,316930 Sekunden.
Linux erreicht `multi-user.target` vor der Wi-Fi-Probe.
Die Laufzeitprüfung bei 81,28 Sekunden bestätigt fehlendes Modul `mt7996e`.
Damit führt der Timer tatsächlich die erste Wi-Fi-Probe dieses Boots aus.

Die Startmarkierung erscheint bei 90,902198 Sekunden und nennt Uptime 90,89 Sekunden.
Der Trace enthält 20 Ereignisse ohne Überlauf oder verlorene Ereignisse.
Der interne Reset setzt und löscht Bit 0; der Anfangswert lautet wieder `0x00010340`.
Der L1-Remap schreibt `0x70007001` und bestätigt diesen Wert durch Rücklesen.
Der Variantenzugriff liest `0x1356f0=0x00000000` bei 91,053470 Sekunden.
Der Treiber meldet den 444-Payload bei 91,101826 Sekunden.
Patchstart scheitert bei 96,162492 Sekunden.
Die Semaphore-Freigabe scheitert ebenfalls; die Geräteprobe endet bei 101,209038 Sekunden mit `-11`.
Die Abschlussmarkierung erscheint bei 101,284869 Sekunden.

Der Dienst meldet Erfolg, weil Modulanforderung und Ergebnisaufzeichnung gelingen.
Dieser Dienststatus ist kein Wi-Fi-Erfolg; `iw dev` bleibt leer.
Beide Wi-Fi-PCIe-Links melden weiterhin 8,0 GT/s und zwei Lanes.
Beide EEPROM-Hashes bleiben unverändert.
Trace, Pufferstatistik, Dmesg und `iw dev` liegen unter `/root/r4pro-delayed-wifi-1d2844be-e60c-46a3-a0f9-f6c091811307`.
Der Trace trägt SHA256 `d0984cef570f520ee0078dd080ef785d2f45f8f81e5e5f8e42df4f879852068d`.
Die Trace-Aufzeichnung ist nach dem Versuch deaktiviert.

Die zusätzliche Wartezeit bis etwa 90 Sekunden behebt den Fehler in diesem Versuch nicht.
Dieser Einzelversuch schließt nicht alle Timing- oder Versorgungsabhängigkeiten aus.
Ein erfolgreicher 233-Start bleibt ungemessen.
Weitere identische Verzögerungsversuche liefern derzeit keinen neuen isolierten Ansatz.

Der Timer wird deaktiviert und gestoppt; die Prüfung bestätigt `disabled` und `inactive`.
Die lokale Ladesperre wird in das Ergebnisverzeichnis verschoben und bleibt dort erhalten.
Die Modprobe-Konfiguration enthält anschließend keine `mt7996e`-Ladesperre mehr.
Dienstdateien und Script bleiben deaktiviert für die Reproduktion erhalten.
Der nächste Boot verwendet wieder die reguläre automatische Wi-Fi-Probe mit früher Trace-Aufzeichnung.
Das Board bleibt eingeschaltet; UART zeichnet weiter auf.

Status: **BOOT PASS / TIMING TEST PASS / WIFI FAIL / CAUSE OPEN**.

## 88. Vorbereitung des getrennten 233-Diagnosetreibers

Der Nutzer beauftragt den vorgeschlagenen 233-Diagnosetest.
Die Boardprüfung findet weder Compiler noch Kernel-Builddateien unter `/usr/src`.
Das laufende Image stammt weiterhin aus Run `37975601363`.
Das Actions-Log bestätigt Kernelcommit `e69eb61a1523c5e993803c05a42c55c7576b07d3`.
Die archivierte Image-Konfiguration dient als Buildgrundlage.
Module aus neueren Images werden wegen abweichender Konfiguration nicht übernommen.

Das lokale Arbeitsverzeichnis heißt `bpi-r4pro8x-force233.5mRsJV`.
Das unveränderte Originalmodul wird aus dem archivierten Root-Dateisystem extrahiert.
Das komprimierte Originalmodul trägt SHA256 `242b8725e07ca2719f71c37bf40b0659a793db16eb5957cdfb8e011eaf7bff56`.
Sein Vermagic lautet `6.18.53-current-filogic SMP mod_unload aarch64`.
Die ELF-Modulstruktur umfasst `0x4c0` Bytes.
Die Konfiguration deaktiviert Modulversionen und aktiviert Modul-BTF.
Diese Prüfungen ersetzen noch keine ABI-Prüfung eines neu gebauten Moduls.

Ein separater Diagnosepatch erzwingt 233 nur für Boardkennung `bananapi,bpi-r4-pro-8x` und MT7996.
Der Patch erhält den Registerzugriff und protokolliert dessen unveränderten Wert.
Der Patch verändert keine Firmwaredateien und keine EEPROMs.
Der Anwendungstest mit `patch --dry-run` besteht.
Der Patch liegt außerhalb des aktiven Repository-Patchverzeichnisses.
Er wird weder als allgemeiner Fix aktiviert noch auf dem Board installiert.

Der Host besitzt keinen AArch64-GCC und keinen direkten Docker-Zugriff.
Eine `pkexec`-Anfrage zur Prüfung vorhandener Docker-Images wartet auf lokale Authentifizierung.
Ein separater Buildentwurf verwendet Ubuntu-GCC 13 und die Image-Konfiguration.
ShellCheck besteht für den Buildentwurf.
Ein vollständiger Archivdownload wird zugunsten eines selektiven Quellenabrufs gestoppt.
Das unvollständige Downloadartefakt bleibt erhalten.
Der selektive Abruf lädt nur Build-relevante Dateien am bestätigten Commit nach.

Der Modultest wurde noch nicht ausgeführt.
Der getrennte Modulbau und dessen ABI-Prüfungen stehen aus.
Das Board bleibt eingeschaltet; sein Originaltreiber und seine Bootdateien bleiben unverändert.

Status: **DIAGNOSTIC PREPARED / BUILD AUTHENTICATION PENDING / RUNTIME TEST PENDING**.

## 89. Erster lokaler Modulbau und korrigierte Buildvorbereitung

Der Nutzer fordert eine neue Authentifizierungsanfrage und die anschließende Fortsetzung an.
Die Docker-Inventarprüfung und der erste lokale Build erhalten die erforderliche Authentifizierung.
Ein unprivilegierter Ubuntu-24.04-Container erhält ausschließlich das lokale Diagnoseverzeichnis.
Der Container erhält weder Hardwaregeräte noch privilegierte Containerrechte.
Ubuntu-GCC 13.3.0 und die erforderlichen Buildpakete werden installiert.

Der erste Vergleichsbuild übernimmt die Konfiguration des laufenden Images.
`modules_prepare` scheitert an fehlender Generatorquelle `kernel/time/timeconst.bc`.
Die selektive Quellenliste enthält außerdem noch nicht `kernel/bounds.c`.
Beide Dateien werden am bestätigten Kernelcommit nachgeladen.
Ein erster Ergänzungsbefehl verwendet ein nicht unterstütztes Git-Argument; der korrigierte Befehl gelingt.
Git meldet zurückbehaltene Dokumentationsdateien im kopierten Analysebaum.
Diese Dateien bleiben erhalten; das eigentliche Repository bleibt unverändert.

Der Konfigurationsvergleich zeigt außerdem fehlendes `pahole` und dadurch deaktivierte BTF-Optionen.
Ein Modul mit dieser abweichenden Konfiguration wird nicht gebaut oder geladen.
Der korrigierte Buildentwurf ergänzt `dwarves` für die ursprüngliche BTF-Konfiguration.
Er baut zuerst die unveränderte Variante und anschließend die 233-Diagnosevariante.
Beide Varianten verwenden dieselbe Quelle, Konfiguration und Toolchain.
Der Diagnosepatch ergänzt ausschließlich die protokollierte, boardgebundene 233-Auswahl.
Die Kernelquelle exportiert das dafür verwendete Symbol `of_machine_compatible_match`.
Eine Kallsyms-Prüfung findet keinen gleichnamigen Ksymtab-Eintrag; diese Prüfung bestätigt deshalb den Export nicht eigenständig.
Der Quellenexport ist direkt geprüft; die spätere Modul-Ladeprüfung bleibt erforderlich.

Die ursprüngliche Anfrage zur Sicherung des beendeten Containers wird beendet.
Die korrigierte Build-Anfrage wartet auf eine neue lokale `pkexec`-Authentifizierung.
Der zweite Buildcontainer soll nach seinem Ende für Diagnosezwecke erhalten bleiben.
Kein Diagnosetreiber wurde auf das Board übertragen oder geladen.
Die Laufzeitprüfung bestätigt weiterhin das unveränderte Originalmodul mit dem Hash aus Abschnitt 88.
Das Board bleibt eingeschaltet; UART zeichnet weiter auf.

Status: **FIRST MODULE BUILD FAIL / CORRECTED BUILD AUTHENTICATION PENDING / RUNTIME TEST PENDING**.

## 90. Erfolgreicher Vergleichs- und Diagnosemodulbau

Die vorherige Buildanfrage erhält inzwischen ihre Authentifizierung.
Ein erneuter Start scheitert am bereits verwendeten Containernamen; kein zweiter Build läuft parallel.
Der vorhandene Container heißt `r4pro-force233-build-v2` und bleibt nach seinem Ende erhalten.
Weitere Prepare-Versuche scheitern zunächst an fehlenden Quellen für `resolve_btfids`, Scheduler-Offsets und ARM64-vDSO.
Die fehlenden BTF-Werkzeuge, Kernel-Unterbäume, vDSO-Dateien und x86-Syscall-Tabellen werden am selben Commit ergänzt.
Ein erster zusätzlicher Inspektionsbefehl verwendet falsche relative Pfade; die Wiederholung liest die richtigen Dateien.
Der anschließende Prepare-Schritt und beide Modulbauten gelingen.

GCC-Version 13.3.0 und pahole-Version 1.25 entsprechen dem Originalbuild.
Aktivierte Kerneloptionen bleiben unverändert.
Der Konfigurationsvergleich zeigt nur den Compiler-Aufrufnamen und entfernte Kommentare für deaktivierte Realtek-Treiber.
Das fehlende `Module.symvers` erzeugt Warnungen für ungelöste externe Symbole.
Der Build verwendet deshalb ausdrücklich `KBUILD_MODPOST_WARN=1`.
Die konfigurierte Modulversionierung bleibt deaktiviert.
Das fehlende `vmlinux` verhindert die BTF-Metadatengenerierung für beide Module.
Die BTF-Kerneloptionen und damit die Modulstruktur bleiben trotzdem erhalten.
Beide Module besitzen zunächst leere automatisch erzeugte Abhängigkeitslisten.
Der Laufzeittest muss vorhandene Original-Abhängigkeitsmodule verwenden und die tatsächliche Symbolauflösung prüfen.

Original, Vergleich und Diagnose besitzen Vermagic `6.18.53-current-filogic SMP mod_unload aarch64`.
Alle drei ELF-Modulstrukturen umfassen `0x4c0` Bytes.
Die Vergleichsvariante importiert exakt dieselben Symbole wie das Original.
Original und Vergleich besitzen byteidentischen `.text`-Maschinencode.
Dessen SHA256 lautet `9a4d92d921ba7cf6df6f058df0630e82e04134b3f9b607919a20017759b2118a`.
Die Diagnosevariante ergänzt nur das importierte Symbol `of_machine_compatible_match`.
Der zugehörige Kernel-Export wurde bereits direkt in der Quelle geprüft.

Die ungekürzte Vergleichsvariante trägt SHA256 `1f5cd85ee11c2ea3fa55d9f8eea269d9358be28c2e91ee714848c0e5e92d648f`.
Die ungekürzte Diagnosevariante trägt SHA256 `d92d5bd0a3eae29f5befd6f81d7e47f7d4da2a5e6eed2ab365e567827721af92`.
Die Übertragungsvarianten entfernen nur Debug-Metadaten und behalten getrennte Dateien.
Vergleich: `0bc2b609a22db6e1343b38fa3210641dac49a42f3d97b14b7fe78a8b2c47feeb`.
Diagnose: `8639b37740fc099a832809fef59553f45eb9def39b3b25f9b6e2204072a6ebde`.
Große UART-Eingaben werden zweimal wegen ihrer Größe abgewiesen.
Die Übertragung gelingt anschließend in kleinen Blöcken.
Beide vollständigen Board-Hashes und Vermagic-Prüfungen stimmen mit den Hostdateien überein.
Das installierte Originalmodul wird nicht überschrieben.

Status: **DIAGNOSTIC MODULE BUILD PASS / MODULE TRANSFER PASS / RUNTIME TEST PENDING**.

## 91. Laufzeitvergleich mit unverändertem und erzwungenem 233-Treiber

Beide Tests laufen im bisherigen Boot mit ID `1d2844be-e60c-46a3-a0f9-f6c091811307`.
Das UART-Log aus Abschnitt 87 enthält beide Tests und die Übertragung.
Das lokale Probescript heißt `run-module-test.sh`; ShellCheck besteht.
Das Script prüft Boardkennung, Vermagic, Modulhash und fehlendes Radio.
Es sichert das Originalmodul zusätzlich unter `/root/r4pro-force233-diag`.
Es entlädt ausschließlich `mt7996e`; die Original-Abhängigkeitsmodule bleiben geladen.
Es verwendet keinen PCIe-Bus-Reset und keine erzwungene Modulentladung.

Der Vergleichstest startet bei 32034,78 Sekunden.
Das Vergleichsmodul lädt ohne Versions- oder Symbolfehler.
Der Kernel markiert das externe Diagnosemodul mit Out-of-tree-Taint.
Diese Markierung bleibt bis zum Neustart bestehen.
Der Trace liest `MT_PAD_GPIO=0` und erfasst 20 Ereignisse.
Der Treiber wählt 444-Build-Time `20260311120419a` und scheitert erneut mit `-11`.
Die Geräteprobe endet bei 32045,049130 Sekunden.

Der 233-Test startet bei 32069,81 Sekunden nach Entladen des Vergleichsmoduls.
Das Diagnosemodul lädt ebenfalls ohne Versions- oder Symbolfehler.
Die Diagnosemeldung bestätigt `PAD_GPIO=0x00000000; forcing 233`.
Der Treiber meldet 233-Build-Time `20260311120705a`.
Patchstart und Semaphore-Freigabe scheitern trotzdem mit denselben MCU-Timeouts.
Die Geräteprobe endet bei 32080,089289 Sekunden mit `-11`.
WM-, DSP- und WA-Initialisierung werden nicht erreicht; `iw dev` bleibt leer.
Der Diagnose-Trace enthält 20 Ereignisse ohne Überlauf oder verlorene Ereignisse.

Beide `insmod`-Befehle liefern Status null; dieser Status bestätigt nur die Modulinitialisierung.
Die PCIe-Geräteproben scheitern unabhängig davon.
Trace, Statistik, Dmesg und Radiostatus liegen getrennt unter `result-baseline` und `result-forced` im Diagnoseverzeichnis.
Beide PCIe-Links melden weiterhin 8,0 GT/s und zwei Lanes.
Beide EEPROM-Hashes und das installierte Originalmodul bleiben unverändert.
Die eigene Trace-Aufzeichnung wird nach jedem Test deaktiviert.
Das Diagnosemodul wird nach der abschließenden Prüfung wieder entladen.

Die erzwungene Firmwarevariante allein behebt den vorhandenen Fehlerzustand in diesem Laufzeitvergleich nicht.
Dieser Versuch beweist nicht, dass die erste 233-Probe nach einem Kaltstart ebenfalls scheitert.
Vor beiden Tests gab es bereits fehlgeschlagene Geräteproben im selben Boot.
Ein frischer Kaltstart muss diesen möglichen Einfluss gesondert prüfen.

Status: **MODULE LOAD PASS / BOTH WIFI FAIL / COLD FIRST233 TEST REQUIRED**.

## 92. Vorbereitung der ersten 233-Probe nach Kaltstart

Der nächste Vergleich soll 233 ohne vorausgegangenen Firmwarefehlversuch starten.
Das lokale Script heißt `install-first233-test.sh`; ShellCheck besteht.
Eine neue lokale Modprobe-Konfiguration sperrt die automatische Alias-Anforderung von `mt7996e`.
Ein gesonderter Timer fordert die erste Diagnoseprobe nach etwa 90 Sekunden an.
Diese Verzögerung entspricht dem ersten 444-Vergleich aus Abschnitt 87.
Kernel, Initramfs, Firmware, EEPROMs und Originalmoduldatei bleiben unverändert.
Nur Lademethode und Diagnosevariante unterscheiden sich vom vorherigen verzögerten Kaltstart.

Das Testscript prüft Boardkennung, Diagnosehash und fehlendes Modul `mt7996e`.
Es prüft ungebundene Wi-Fi-PCIe-Funktionen und aktive frühe Trace-Aufzeichnung.
Eine unerwartete frühere Probe führt zum Abbruch.
Das Script lädt zunächst die Original-Abhängigkeit `mt76_connac_lib`.
Es lädt anschließend die getrennte Datei `/root/r4pro-force233-diag/forced.ko`.
Es erfasst Start- und Abschlussmarkierungen im Kernel-Log.
Registertrace, Pufferstatistik, Dmesg und `iw dev` werden pro Boot-ID gesichert.
Das Ergebnisverzeichnis heißt `/root/r4pro-force233-diag/first233-<Boot-ID>`.
Die eigene Trace-Aufzeichnung und beide Registerereignisse werden nach der Probe deaktiviert.

Script-Syntaxprüfung und systemd-Unit-Prüfung bestehen.
Der neue Timer meldet vor dem Shutdown `enabled` und `inactive`.
Das experimentelle Modul ist zuvor erfolgreich entladen.
Linux bestätigt vollständig ausgehängte Dateisysteme bei 32193,224069 Sekunden.
TF-A meldet erneut `Power-down unsupported`; die elektrische Stromtrennung bleibt erforderlich.
Der Recorder erhält eigene Logs mit Präfix `uart-run-37975601363-first233-coldboot-`.
Der Recorder verbindet sich nach USB-Geräteverlust automatisch erneut.

Der Nutzer muss das Board vollständig stromlos machen und mit unveränderten Modulen starten.
Die Auswertung muss vorangegangene Originalproben ausschließen und die Diagnosemarkierung bestätigen.
Der erste 233-Kaltstart ist noch nicht ausgeführt.
Der lokale Diagnosemodus bleibt bis zur Testauswertung und anschließenden Bereinigung für weitere Boots aktiv.

Status: **FIRST233 COLD BOOT PREPARED / HARDWARE START PENDING**.

## 93. Erste 233-Probe nach Kaltstart scheitert

TF-A bestätigt `Cold boot`; die Boot-ID lautet `77c761d8-9351-4286-bc7b-daabd6d54d0f`.
Die frühe Trace-Aufzeichnung startet bei 16,727003 Sekunden.
Das UART-Log enthält keine frühere `mt7996e`-Probe.
Der Timer startet die erste Probe bei 90,168974 Sekunden.
Die Diagnose bestätigt `PAD_GPIO=0x00000000; forcing 233` bei 90,303544 Sekunden.
Der Treiber meldet 233-Build-Time `20260311120705a` bei 90,371176 Sekunden.
Der Patchstart scheitert bei 95,442679 Sekunden nach MCU-Timeout für Nachricht 7.
Die Semaphore-Freigabe scheitert nach MCU-Timeout für Nachricht 10.
Die Geräteprobe endet bei 100,489281 Sekunden mit `-11`.
WM-, DSP- und WA-Initialisierung fehlen; `iw dev` bleibt leer.

Der Trace enthält 20 Ereignisse ohne Überlauf oder Verluste.
Der Trace bestätigt Resetfolge `0x10340 -> 0x10341 -> 0x10340` und PAD-Lesewert null.
Beide Wi-Fi-PCIe-Links melden 8,0 GT/s und zwei Lanes.
Die primäre Funktion bleibt ungebunden; die sekundäre Funktion bindet `mt7996e_hif`.
Der Dienst meldet Erfolg, weil `insmod` Status null liefert.
Dieser Status bestätigt keine erfolgreiche Geräteprobe.
Beide EEPROM-Hashes und der Hash des installierten Originalmoduls bleiben unverändert.

Die Ergebnisse liegen unter `/root/r4pro-force233-diag/first233-77c761d8-9351-4286-bc7b-daabd6d54d0f`.
Das lokale UART-Log heißt `uart-run-37975601363-first233-coldboot-20261010T104027.log`.
Der Test deaktiviert anschließend Timer, Trace und Registerereignisse.
Die Autoload-Sperre liegt wiederherstellbar im Ergebnisverzeichnis; das Diagnosemodul ist entladen.
Der nächste Boot lädt wieder das unveränderte Originalmodul.
Die frühe Initramfs-Trace-Vorbereitung bleibt erhalten.

Die erzwungene Variante allein behebt diesen Kaltstartfehler nicht.
Ein früherer fehlgeschlagener Wi-Fi-Probe ist für diesen beobachteten Fehler nicht erforderlich.
Der Versuch schließt einen zusätzlichen Variantenfehler nicht aus.
USB-Controller `11190000` meldet erneut instabile Clocks und Probe-Fehler `-110`.
PCIe-Controller `11280000` meldet ebenfalls `-110`; die Wi-Fi-Links liegen an anderen Controllern.
Eine gemeinsame Ursache ist nicht bewiesen.
Der nächste Diagnosefokus liegt auf dem MCU-Patchstart und dem Hardwarezustand vor der Firmwareinitialisierung.

Status: **FIRST233 COLD BOOT WIFI FAIL / ORIGINAL AUTOLOAD RESTORED**.

## 94. Register- und IRQ-Trace beim Original-Patchstart

Der Nutzer verlangt den nächsten Versuch und erwägt ein zuvor funktionierendes Image.
Das laufende Image aus Run `37975601363` besteht bereits den früheren 6-GHz-Test aus Abschnitt 56.
Dasselbe Image initialisiert Wi-Fi auch in Abschnitt 75 erfolgreich.
Ein identisches Neuaufspielen liefert daher allein keinen neuen Softwarevergleich.

Eine getrennte Trace-Instanz zeichnet alle mt76-Ereignisse mit 4096 KiB Puffer pro CPU auf.
Der Versuch lädt ausschließlich das installierte Originalmodul.
Der Versuch führt keinen PCIe-Busreset aus.
Die Probe startet bei 331,997150 Sekunden im Boot aus Abschnitt 93.
Der Trace enthält 286 Ereignisse und 17 `dev_irq`-Ereignisse ohne Überlauf oder Verluste.
`MT_PAD_GPIO` bleibt null; der Treiber verwendet 444-Build-Time `20260311120419a`.
Die Ownership-Prüfung liefert für beide Bänder null nach Anforderung der Hostkontrolle.
`MT_TOP_MISC` wechselt im Trace von null auf eins.
Die Firmwarezustandsprüfung erreicht anschließend den Patchdownload.
MCU-RX-Interrupts mit Bit 0 erscheinen bei 332,126422 und 332,140349 Sekunden.
Interrupts und frühe MCU-Antworten fehlen somit nicht grundsätzlich.
Der Trace beweist keine korrekte Verarbeitung sämtlicher DMA-Daten.

Der Patchstart scheitert bei 337,202785 Sekunden nach Nachricht-7-Timeout.
Die Geräteprobe endet bei 342,249281 Sekunden nach Semaphore-Timeout mit `-11`.
`iw dev` bleibt leer; der Originalmodulhash bleibt unverändert.
Die Quellprüfung bestätigt: Der Treiber erreicht Patchstart nach erfolgreichen Rückgaben der Downloadanforderungen und Sendefunktionen.
Diese Rückgaben beweisen keine erfolgreiche Ausführung des Patches auf dem MCU.
Ergebnisse liegen unter `/root/r4pro-force233-diag/mcu-original-20261010T044439Z`.
Das Boarddatum im Verzeichnisnamen weicht von der Hostzeit ab.
Der Versuch deaktiviert anschließend Trace und Ereignisse und entlädt das Originalmodul.

Status: **MCU TRACE PASS / ORIGINAL WIFI FAIL / CAUSE OPEN**.

## 95. Original-Initramfs für den nächsten Kaltstart wiederhergestellt

Der nächste Vergleich entfernt den Einfluss der frühen Trace-Vorbereitung.
Alle drei Dateien in `/root/r4pro-early-trace-backup/SHA256SUMS` bestehen die Hashprüfung.
Die aktuelle Extlinux-Konfiguration entspricht bereits der ursprünglichen Sicherung.
Die Diagnose-Initramfs-Dateien und beide Diagnose-Hooks bleiben im Ergebnisverzeichnis aus Abschnitt 94 gesichert.
Die ursprünglichen Dateien ersetzen Initrd und uInitrd; byteweise Vergleiche mit den Sicherungen bestehen.
Initrd-SHA256: `0246fa6e0bdc53cc7309b457c80b31d3cc7af9c94b8e28f43f1e0b3a58111baf`.
uInitrd-SHA256: `199d837901abf86fd87a90e9890e7702a6e0781cd013fe98d7954d113737f46b`.
Die Diagnose-Hooks verlassen ihre aktiven Initramfs-Verzeichnisse und bleiben wiederherstellbar erhalten.
Beide Wi-Fi-Testtimer melden `disabled`; die Modprobe-Sperren fehlen.
Kernel, DTB, Firmware und EEPROMs bleiben unverändert.
Dieser Schritt spielt kein neues Rohimage auf und verspricht keinen Wi-Fi-Erfolg.

Linux bestätigt vollständig ausgehängte Dateisysteme bei 427,510735 Sekunden.
TF-A meldet weiterhin `Power-down unsupported`.
Der Nutzer muss die Stromversorgung vollständig trennen und USB-Rückspeisung ausschließen.
Der nächste Kaltstart soll mit unveränderter Bestückung und SD erfolgen.
Der bestehende UART-Recorder bleibt für den Vergleich aktiv.

Status: **ORIGINAL INITRAMFS RESTORED / COLD START PENDING**.

## 96. Kaltstart mit Original-Initramfs reproduziert Wi-Fi-Fehler

TF-A bestätigt `Cold boot`; Linux erreicht `multi-user.target` und den Login.
Die Boot-ID lautet `bbff42e8-ced9-4cd4-b851-4c8583b2c198`.
Die Initrd-, uInitrd- und Originalmodulhashes entsprechen den geprüften Sicherungen.
Beide Diagnose-Timer bleiben deaktiviert; die frühe Trace-Instanz fehlt.
Das Originalmodul startet automatisch bei etwa 25,60 Sekunden.
Der ROM-Patch meldet 444-Build-Time `20260311120419a` bei 25,767829 Sekunden.
Der Patchstart scheitert bei 30,802577 Sekunden nach Nachricht-7-Timeout.
Die Semaphore-Freigabe scheitert nach Nachricht-10-Timeout.
Die Geräteprobe endet bei 35,849088 Sekunden mit `-11`.
WM-, DSP- und WA-Start fehlen; `iw dev` bleibt leer.
Beide PCIe-Links melden 8,0 GT/s und zwei Lanes.
Die Hauptfunktion bleibt ungebunden; die zweite Funktion bindet `mt7996e_hif`.
Beide EEPROM-Hashes bleiben unverändert.

USB-Controller `11190000` meldet instabile Clocks; PCIe-Controller `11280000` meldet Probe-Fehler `-110`.
Die AER-Ausgabe zeigt Aktivierung, aber keine neue Fehlerserie.
MxL meldet bei 38,114711 Sekunden einen MMD-Lesefehler für Port 2.
`_phy_start_aneg` liefert danach `-110`; die PHY-Zustandsmaschine erzeugt eine Kernel-Warnung.
Diese Ethernet-Warnung entsteht nach dem Wi-Fi-Fehler; eine gemeinsame Ursache bleibt ungeklärt.
`armbian-led-state.service` bleibt der einzige fehlgeschlagene systemd-Dienst.

Ergebnisse liegen unter `/root/r4pro-force233-diag/original-initramfs-bbff42e8-ced9-4cd4-b851-4c8583b2c198`.
Der Recorder schreibt weiterhin `uart-run-37975601363-first233-coldboot-20261010T104027.log`; dieses Log enthält mehrere Boots.
Die frühe Trace-Vorbereitung ist keine notwendige Voraussetzung für den beobachteten Wi-Fi-Fehler.
Der Versuch beweist weder einen Hardwaredefekt noch eine ausschließlich softwarebedingte Ursache.
Ein nächster unabhängiger Vergleich kann das vorhandene OpenWrt ohne Flash-Schreibzugriffe booten und dessen BE14-Probe prüfen.
Das Board bleibt eingeschaltet; es erfolgen keine weiteren Resets oder Firmwareänderungen.

Status: **BOOT PASS / ORIGINAL INITRAMFS WIFI FAIL / CAUSE OPEN**.

## 97. Referenzimage des erfolgreichen Tests aus f77368177 erneut geschrieben

Der Nutzer fordert das funktionierende Image zum Stand `f77368177`.
Commit `f773681774f69860ce51eeef94099ffb9a86c5c1` dokumentiert den erfolgreichen 6-GHz-Test aus Abschnitt 56.
Dieser Dokumentationscommit erzeugt kein eigenes Image.
Abschnitt 56 nennt ausdrücklich Run `37975601363` als verwendetes Image.
Das lokale Originalimage dieses Runs bleibt verfügbar und besteht seine veröffentlichte SHA256-Prüfung.
Die Image-Metadaten nennen Sources-Revision `b94e6d9`.
Die aktuelle Branchhistorie und sämtliche Fehlversuche bleiben erhalten; es erfolgt kein Git-Reset.

Linux hängt vor der Kartenentnahme alle Dateisysteme bei 178,159440 Sekunden aus.
Der Host erkennt die bekannte 64-GB-SD als `/dev/sdb` im Generic-USB-Kartenleser.
Das Flashscript prüft Größe, USB-Pfad, Removable-Flag, Modell und bisherige Rootfs-UUID.
Das Script heißt lokal `flash-r4pro8x-f77368177-reference.sh`; Bash-Syntaxprüfung und ShellCheck bestehen.
Der Nutzer bestätigt die pkexec-Anfrage.
Das Script sichert Diagnoseergebnisse und ursprüngliche Bootdatei-Sicherungen vor dem Überschreiben.
Die private Sicherung liegt unter `/home/lukas/Work/bpi-r4pro8x-f77368177-reflash.JRISz7/sd-diagnostics-before-reflash.tar.gz`.
Archiv-SHA256: `a656619b70fa0fc1d22e65be1d7f741c0ff429cbab0227dec52b89ac0c79ff92`.

Das Script schreibt 1476395008 Bytes nach vollständigem Aushängen der SD-Partitionen.
Das Script liest anschließend den gesamten geschriebenen Imagebereich zurück.
Image und SD-Rücklesung liefern SHA256 `14bb7d95874d1133945f95b3cecde55306813604a948a0f23987a63fc3301768`.
Der Schreibvorgang entfernt die bisherigen lokalen SD-Diagnoseänderungen; die externe Sicherung erhält deren Ergebnisse.
`udisksctl power-off` trennt den Kartenleser anschließend erfolgreich.
Es erfolgen keine Schreibzugriffe auf Board-EEPROM, eMMC, NAND oder NOR.
Das Neuaufspielen bestätigt keinen aktuellen Wi-Fi-Erfolg; der nächste Kaltstart bleibt erforderlich.
Das Flashlog liegt im selben lokalen Sicherungsverzeichnis.

Status: **REFERENCE IMAGE FLASH PASS / COLD BOOT PENDING**.

## 98. Referenzimage-Start ohne vollständigen UART-Mitschnitt

Der Nutzer meldet den Start nach dem Neuaufspielen.
Die bisherige Recorder-Sitzung existiert nicht mehr; auch die Prozessprüfung findet keinen aktiven Recorder.
Die erste Wiederverbindung erfasst nur 128 Bytes BootROM-Anfang.
Diese Verbindung endet durch geschlossenen Standardeingabekanal.
Die zweite Verbindung nutzt einen offenen PTY-Eingabekanal, empfängt jedoch keine weiteren Boarddaten.
Die zweite Verbindung endet anschließend mit UART-Ein-/Ausgabefehler.
TF-A, U-Boot, Linux und Wi-Fi sind in diesem Versuch nicht aufgezeichnet.
Der unvollständige Mitschnitt beweist keinen BootROM-Hänger und keinen neuen Wi-Fi-Fehler.

Das neue lokale Script heißt `bpi-r4pro8x-uart-reference-recorder.sh`.
Bash-Syntaxprüfung und ShellCheck bestehen.
Der Recorder verbindet den stabilen HOLTEK-Gerätepfad mit 115200 Baud erneut nach Geräteverlust.
Jede Verbindung erhält ein eigenes Log mit Präfix `uart-run-37975601363-reference-reflash-`.
Die alten Mitschnitte bleiben erhalten.
Ein erneuter vollständiger Kaltstart ist für die Auswertung erforderlich.
Es erfolgen keine weiteren Image-, EEPROM- oder Flashänderungen.

Status: **CAPTURE INCOMPLETE / BOOT AND WIFI UNCONFIRMED / RECORDER READY**.

## 99. Vollständig aufgezeichneter Referenzimage-Kaltstart nach Neuaufspielen

Die wiederverbundene Konsole erreicht zunächst die Root-Ersteinrichtung des frisch geschriebenen Images.
Die erste Passwortbestätigung scheitert; die erneute Eingabe mit den vom Nutzer vorgegebenen Testdaten gelingt.
Die optionale Benutzeranlage wird ohne zusätzlichen Benutzer abgebrochen.
Der angeforderte Shutdown hängt alle Dateisysteme bei 302,763487 Sekunden aus.
TF-A meldet weiterhin `Power-down unsupported`.

Der Nutzer kündigt anschließend einen erneuten Start an.
Der Recorder erfasst BootROM, TF-A, U-Boot und Linux vollständig.
TF-A bestätigt `Cold boot`; Linux erreicht `multi-user.target` und den Login.
Die Boot-ID lautet `764a8f5e-3b37-4236-86d1-cd2d6c722cb8`.
Das Log heißt `uart-run-37975601363-reference-reflash-20261010T113150.log` und enthält auch den vorherigen Shutdown.
Der erste Login scheitert durch Terminal-Antwortzeichen; die Wiederholung gelingt.

Der Treiber meldet 444-Build-Time `20260311120419a` bei 26,350113 Sekunden.
Der Patchstart scheitert bei 31,442624 Sekunden nach Nachricht-7-Timeout.
Die Semaphore-Freigabe scheitert nach Nachricht-10-Timeout.
Die Geräteprobe endet bei 36,489149 Sekunden mit `-11`.
WM-, DSP- und WA-Start fehlen; `iw dev` bleibt leer.
Beide Wi-Fi-PCIe-Links melden 8,0 GT/s und zwei Lanes.
Die Hauptfunktion bleibt ungebunden; die zweite Funktion bindet `mt7996e_hif`.
Initrd-, uInitrd-, Originalmodul- und beide EEPROM-Hashes entsprechen den vorher bestätigten Werten.
Die lokalen Modprobe-Sperren und Diagnose-Trace-Instanzen fehlen.

USB-Controller `11190000` meldet erneut instabile Clocks und Probe-Fehler `-110`.
PCIe-Controller `11280000` meldet ebenfalls `-110`.
Die geprüfte Dmesg-Ausgabe enthält diesmal keine MxL-MMD- oder PHY-Kernelwarnung.
`armbian-led-state.service` bleibt der einzige fehlgeschlagene systemd-Dienst.
Das vollständige Neuaufspielen des früher erfolgreich getesteten Images stellt Wi-Fi in diesem Kaltstart nicht wieder her.
Die früheren erfolgreichen 233-Starts und der 6-GHz-Test bleiben gültige historische Befunde.
Ein Hardwaredefekt ist weiterhin nicht bewiesen.
Der nächste unabhängige Vergleich bleibt ein BE14-Test unter vorhandenem OpenWrt ohne Flash-Schreibzugriffe.
Das Board bleibt eingeschaltet; weitere Resets und Änderungen erfolgen nicht.

Status: **REFERENCE REFLASH BOOT PASS / WIFI FAIL / CAUSE OPEN**.

## 100. OpenWrt-eMMC-Vergleich startet BE14 erfolgreich

Der Nutzer startet nach sauberem Armbian-Shutdown das vorhandene OpenWrt von eMMC.
Der Recorder verbindet sich nach UART-Geräteverlust erneut; der Mitschnitt beginnt bei BL2-Übergabe an BL31.
BootROM und früher BL2-Start fehlen in diesem Mitschnitt.
OpenWrt verwendet TF-A 2.10, U-Boot 2024.10 und Linux 6.6.93 aus Juni 2025.
Die Boot-ID lautet `a7287b93-3459-4b86-b9b6-8d4e8bd47666`.
Das Log heißt `uart-run-37975601363-reference-reflash-20261010T114048.log`; das Präfix benennt den Recorder, nicht das gestartete System.
U-Boot meldet einen fehlenden zusätzlichen FIT-Konfigurationsknoten, startet Linux aber erfolgreich.
Das vorhandene OpenWrt mountet seine persistenten Overlays selbstständig; der Versuch verändert keine Firmware- oder Flashkonfiguration.

Der ROM-Patch startet bei 36,995922 Sekunden mit Build-Time `20250605130343a`.
WM startet bei 37,100623 Sekunden mit Build-Time `20250605130338`.
DSP startet bei 37,144978 Sekunden mit Build-Time `20250605125645`.
WA startet bei 37,166386 Sekunden mit Build-Time `20250605130248`.
Der Treiber registriert `mt76-phy0` bei 38,025599 Sekunden.
Die Firmwareausgabe nennt Version `4.4.25.06`, normalen WM-Modus und iFEM.
Die ROM-Patch-Build-Time entspricht der installierten Datei `mt7996_rom_patch_233.bin`.
Die nicht spezialisierte Patchdatei enthält dagegen Build-Time `20250605125803a`.
Patchstart- und Semaphore-Timeout fehlen in der geprüften Dmesg-Ausgabe.

`iw dev` zeigt `phy0.0-ap0`, `phy0.2-ap0` und das MLO-Interface `ap-mld-1`.
Die MLO-Links verwenden 2412 MHz mit 40 MHz, 5180 MHz mit 160 MHz und 6135 MHz mit 320 MHz.
Die AP-Konfiguration stammt aus dem vorhandenen OpenWrt; der Versuch verändert sie nicht.
Die Stationstabellen der beiden Einzel-APs bleiben leer.
Dieser Versuch bestätigt Firmwarestart und Interface-Erkennung, aber keinen Clientverkehr oder Dauerbetrieb.
Beide Wi-Fi-PCIe-Links melden 8,0 GT/s und zwei Lanes.
Die Hauptfunktion bindet `mt7996e`; die zweite Funktion bindet `mt7996e_hif`.
OpenWrt aktiviert WED; Armbians geprüfter Originaltreiber verwendet standardmäßig kein WED.
USB-Controller `11190000` initialisiert hier ohne den beobachteten Armbian-Clock-Timeout.

Die Firmwaredateien liegen unter `/lib/firmware/mediatek/mt7996/`.
SHA256 `mt7996_rom_patch_233.bin`: `14ed39216fffe0a5b34386e4deb5f6278f1edf54da21a850fcfd10aafe65d24f`.
SHA256 `mt7996_wm_233.bin`: `3885b32692fa7cfdfe19956605dabc03512e0e8f0da59b04826ea2205485a2e0`.
SHA256 `mt7996_wa_233.bin`: `a1ec4af9e3069964bf91058b11fae1c4e53208175addc1af72b5d52b11081613`.
SHA256 `mt7996_dsp.bin`: `dabc8450e03e503e7756f1050ddb22ef354726a3e53deb77d5754aa2ac6b80dc`.
Beide I2C-EEPROM-Hashes entsprechen weiterhin den Armbian-Messungen.
Die Treiberdiagnose meldet `efuse mode`; der aktive Datensatz umfasst 7680 Bytes.
Datensatz-SHA256: `1436309d9fb2ee3a40bee9f847ccec55fc5a7eb374fbbbef53237b44dc2ba382`.
Dieser Datensatz unterscheidet sich vom früheren Armbian-Datensatz aus Abschnitt 55.
Die unterschiedlichen Treiberaufbereitungen erlauben daraus keine Aussage über veränderte physische eFuse-Inhalte.

Das BE14 arbeitet in diesem OpenWrt-Boot; ein durchgängiger Hardwareausfall liegt somit nicht vor.
Intermittierende Versorgungs- oder Kontaktprobleme bleiben dadurch nicht ausgeschlossen.
Firmware, Kernel, Treiber, WED und Bootkette unterscheiden sich gleichzeitig vom Armbian-Vergleich.
Der Versuch isoliert deshalb noch keine einzelne Ursache.
Ein nächster isolierter Vergleich kann den gesicherten Juni-2025-Firmwaresatz auf dem SD-Testimage prüfen.
Dieser Vergleich benötigt Dateisicherung und einen passenden 233-Ladepfad; er ist noch nicht ausgeführt.
Das OpenWrt bleibt eingeschaltet; weitere Resets und Firmwareänderungen erfolgen nicht.

Status: **OPENWRT WIFI INIT PASS / CLIENT UNTESTED / ARMBIAN CAUSE OPEN**.

## 101. Latest-Build vorbereitet; neueres Kernelziel noch offen

Der Nutzer verlangt einen neuen Build mit dem Ziel aktueller Firmware und Kernel.
Der alte OpenWrt-Firmwaresatz wird nicht als Produktionsbasis übernommen.
Der Actions-Workflow erhält die manuelle Auswahl `firmware_mode=pinned/latest`.
Der Standard und Pull-Request-Builds bleiben `pinned`.
Preflight prüft die gewählte Firmwareoption vor dem Build.
Compile-Aufruf, Zusammenfassung und Image-Artefaktname übernehmen denselben Modus.
Die Workflow-Strukturprüfung bestätigt Standard und Weitergabe von `latest`.
Der vollständige statische Preflight besteht; die bekannte Maintainer-Warnung bleibt bestehen.

Der isolierte Latest-Installertest löst linux-firmware-HEAD auf `afabaf773c4c2e2c841429933a6a084a5af4d14d` auf.
Der Installer lädt und installiert alle 15 Payloads erfolgreich.
Alle 15 Git-Blob-Hashes entsprechen derzeit dem bestehenden Pin.
Die 233-ROM-Patch-Build-Time bleibt `20260311120705a`.
Ein neuer Firmware-Repository-HEAD bedeutet hier keine neueren ausgewählten Payloads.
Testergebnisse liegen lokal unter `/home/lukas/Work/bpi-r4pro8x-latest-probe.r9FjqD`.

Franks bestehende Branch `6.18-main` steht weiterhin auf `e69eb61a1523c5e993803c05a42c55c7576b07d3`.
Die Branchliste enthält inzwischen auch `7.2-main` und `7.3-rc`.
Die geprüfte `7.2-main`-Makefile meldet Linux 7.2.0.
Die Branch enthält das Device-Tree-Target `mt7988a-bananapi-bpi-r4-pro-8x.dts`.
Diese Prüfung bestätigt keine vollständige Port- oder Patchkompatibilität.
Der Nutzer erhält eine Auswahl zwischen 7.2-Migration, bestehendem 6.18-Port und experimentellem 7.3-rc.
Kernelquelle, Kernelpatches und normale Filogic-Family bleiben bis zur Auswahl unverändert.
GitHub-PR 1 bleibt offen; letzter erfolgreicher Workflowrun ist `38003437809`.
Ein neuer Actions-Build ist noch nicht gestartet; die Kernelzielauswahl bleibt offen.

Status: **STATIC / LATEST INSTALL PASS / KERNEL TARGET PENDING**.

## 102. Neuer Entwicklungsbranch ohne Löschung

Der Nutzer widerruft die Löschung und verlangt den Neustart auf einem neuen Branch.
Das Kernelziel lautet ausdrücklich Linux `7.3-rc6`.
Der neue Branch heißt `bpi-r4pro-8x-7.3-rc6`.
Die Basis ist Commit `f4acdd594da9c1adb7164cf19f0c5f5cc39fd851` des bisherigen Entwicklungsbranches.
Der Arbeitsbaum ist vor der Branchanlage sauber.
Dateien, Commit-Historie, README-Chronik, Images, Backups und UART-Logs bleiben erhalten.
Der alte Branch `bpi-r4pro-8x` bleibt unverändert.
Der neue Branch erhält kein zurückgesetztes oder unabhängiges Git-Verzeichnis.

Dieser Schritt ändert noch keine Kernelquelle, Kernelpatches oder Boardkonfiguration.
Die aktive Buildkonfiguration verwendet weiterhin Franks `6.18-main`.
Ein Image mit `7.3-rc6` ist noch nicht gebaut oder gestartet.
Der nächste Schritt prüft eine exakte rc6-Quelle und die benötigten R4-Pro-Erweiterungen.
Die rc1-Basis von Franks `7.3-rc` wird nicht als rc6 ausgegeben.
Die bereits vorbereitete manuelle Latest-Firmwareauswahl bleibt erhalten.

Status: **NEW BRANCH CREATED / EXACT RC6 MIGRATION PENDING**.

## 103. Exakte rc6-Basis und separater Portierungstest

Der offizielle Tag `v7.3-rc6` verweist auf Commit `a90ee4305c4a5df72c11b31dacfdc76e00fcf78a`.
Franks Branch `7.3-rc` steht auf `32b3bd5458be1657056f9852b0b309f73b65a4d7`.
Seine Basis ist das offizielle rc1, Commit `cee9395acd8043be0644b25c34bfa86623f2b935`.
GitHub meldet 153 Zusatzcommits und keine fehlenden rc1-Commits.
Die Erweiterungen betreffen unter anderem Device Trees, Ethernet, PCS, PHYs, Switch, USB und PCIe.

Der separate Checkout liegt unter `/home/lukas/Work/bpi-r4pro8x-linux-7.3-port`.
Ein mechanischer Diff exportiert Quelländerungen; Firmwarekopien, Buildskripte und `.orig`/`.rej`-Dateien bleiben ausgeschlossen.
Der erste rc6-Checkout scheitert beim Nachladen offizieller Objekte über Franks Server.
Git meldet `upload-pack: not our ref 005735a899203c46717cbc6ffeef95bb5a60185f`.
Der Prüfcheckout verwendet danach Torvalds' Server für die offiziellen Objekte.
Die bestehenden 6.18-Quellen bleiben unverändert.
Ein Patchtest und ein rc6-Imagebuild stehen noch aus.

Status: **SOURCE VERIFIED / PORT TEST PENDING**.

## 104. Board-lokale rc6-Portierung

Die R4-Pro-Family pinnt den offiziellen rc6-Commit aus Abschnitt 103.
Der neue Patchsatz heißt `bpi-r4pro8x-7.3`.
Die normale Filogic-Family und der alte 6.18-Patchsatz bleiben unverändert.
Der erste vollständige Prüfdownload wird zugunsten eines gezielten Sparse-Checkouts abgebrochen.
Ein separater frischer Worktree prüft anschließend die exportierten Patches ohne Dreiwege-Fallback.
Ein erster Test findet dort noch keine ausgecheckten Dateien.
Nach der Indexinitialisierung bestehen alle drei Patches sequenziell `git apply --check` und `git apply`.

Die Frank-Erweiterungen verursachen Dreiwege-Konflikte in `mxl862xx.c`, `mtk_eth_soc.c` und `mtk_eth_soc.h`.
Die Auflösung erhält rc6-EEE-Grenzen und den Statistics-Worker-Stopp beim MaxLinear-Teardown.
Die MediaTek-Probe alloziert NAPI vor der Interface-Registrierung, mit Franks RSS/LRO-Arrays.
Die Fehlerbereinigung entfernt registrierte RX-NAPI-Instanzen.
MaxLinear richtet MDIO vor dem Start des Statistics-Workers ein.
Die Patchdokumentation nennt Herkunft, Umfang und Konfliktauflösung.
Neun geerbte Whitespace-Warnungen bleiben sichtbar; sie blockieren den Patchtest nicht.

Der aktualisierte gemeinsame Device Tree enthält bereits `lan1` bis `lan5`.
Der 8X-Patch aktiviert `fpc` und `lan6`, einschließlich der RJ45-Multiplexer-Auswahl.
Franks aktualisierter Switchtreiber verwendet Portnummer 13 für den LAN-Combo-Port.
Die Wi-Fi-Diagnose protokolliert Register und Firmwarepfad, ohne Variante oder Resetzeiten zu erzwingen.
Der neue MT76-Treiber enthält keine alte RF-Dateierweiterung.
Die alten RF-Dateipatches bleiben archiviert; rc6 verwendet die native OF/eFuse-Auswertung.
Wi-Fi-MAC-Adressen bleiben beim Treiber.
EEPROM-Ethernet-MAC-Zuordnung, USB-Moduloptionen und PTP bleiben erhalten.
Ein board-lokaler Versionsschutz verlangt `7.3.0-rc6` während der Kernelkonfiguration.

Der erste DT-Präprozessorlauf scheitert an einem fehlenden Header im Sparse-Checkout.
Nach dem Headerdownload kompiliert der 8X-DTB erfolgreich.
Der Compiler meldet eine bestehende `avoid_unnecessary_addr_size`-Warnung am MaxLinear-Knoten.
Das SD-Overlay kompiliert und lässt sich mit `fdtoverlay` erfolgreich anwenden.
Die Makefile meldet weiterhin Version 7.3.0-rc6.
`make -s kernelversion` bestätigt `7.3.0-rc6`.
Der Versionsschutz akzeptiert rc6 und verwirft eine simulierte rc1-Version.
Der statische Preflight besteht; die Maintainer-Warnung bleibt bestehen.
Der Preflight findet zunächst noch den alten Cache-Hash; der Check erhält anschließend den neuen rc6-Hash.
Shellcheck besteht mit den üblichen Ausnahmen für Frameworkvariablen und externe Sources.
Der lokale Kconfig-Test scheitert zunächst am fehlenden `ld.lld`.
Ein erneuter Versuch mit GCC scheitert am ebenfalls fehlenden `ld`.
Diese Hostfehler bestätigen keinen Kernel-Kompilierfehler und keinen erfolgreichen Kconfig-Test.
GitHub Actions übernimmt den vollständigen Build mit seinem eigenen Toolchain-Setup.
Ein vollständiger Kernelbuild und Hardwaretests stehen noch aus.

Status: **STATIC / PATCH / DT PASS / BUILD PENDING / HW UNTESTED**.

## 105. Erster rc6-Imagebuild gestartet

Commit `eb42b5284e7cdb8c7201a09c60183f26b34b735a` enthält die rc6-Portierung.
Der Commit ist auf `origin/bpi-r4pro-8x-7.3-rc6` gepusht.
Der alte Branch bleibt unverändert.
Der manuelle Actions-Aufruf wählt `firmware_mode=latest`.
Der Firmwareinstaller löst die Quelle während dieses Builds erneut auf und auditiert die tatsächlichen Payloads.
Ein unveränderter Firmware-HEAD kann weiterhin bytegleiche Payloads liefern.

Run: `38051805424`.
URL: https://github.com/GermanatorLM/build/actions/runs/38051805424
GitHub bestätigt `workflow_dispatch`, den richtigen Branch und den richtigen Build-Commit.
Der Actions-Preflight besteht erfolgreich.
Der Imagejob läuft mit `latest`; die Runner-Vorbereitung beginnt.
Der Run ist gestartet; ein vollständiges Ergebnis liegt noch nicht vor.
Es erfolgt keine SD-Schreiboperation und kein Board-Reset.

Status: **BUILD STARTED / RESULT PENDING / HW UNTESTED**.
