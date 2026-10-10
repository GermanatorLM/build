# Armbian für Banana Pi BPI-R4 Pro 8X

Dieses Repository ist ein Entwicklungs-Fork des Armbian Build Frameworks für
den **Banana Pi BPI-R4 Pro 8X (MT7988A, 8 GiB DDR4)**.

Der aktuelle Entwicklungsbranch ist:

```text
bpi-r4pro-8x
```

> **Bring-up-Status:** `BOOT PASS` erreicht. Ethernet-Core und beide
> Aeonsemi-10G-PHYs sind auf der Zielhardware bestätigt. `HW PASS` ist noch
> offen; der nächste isolierte Fix ergänzt die von der MT7996-444-Variante
> angeforderte unsuffigierte Wi-Fi-Firmware.

## Zielbild

Die erste stabile Zielkette ist bewusst klein gehalten:

```text
BootROM
  -> BL2 / MediaTek ATF
  -> U-Boot
  -> SD-Karte
  -> extlinux
  -> Linux 6.18
  -> Debian Trixie / Armbian Login
```

Danach erfolgt der Hardware-Bring-up einzeln und in dieser Reihenfolge:

```text
Management-Ethernet
  -> interne 2.5G PHYs
  -> Aeonsemi AS21xxx / 10G
  -> MaxLinear MxL862xx DSA
  -> PCIe / NVMe
  -> MT7996 Wi-Fi 7
```

Damit bleibt bei Fehlern erkennbar, welcher Commit und welche Hardwarestufe
die Regression eingeführt hat.

## Aktueller technischer Aufbau

| Bereich | Auswahl | Status |
|---|---|---|
| Board | Banana Pi BPI-R4 Pro 8X | implementiert |
| SoC | MediaTek MT7988A | implementiert |
| RAM | 8 GiB DDR4 | ATF mit `DDR4_4BG_MODE=1` |
| Distribution | Debian Trixie | vorgesehen |
| Kernel | Frank Wunderlich `BPI-Router-Linux`, `6.18-main` / 6.18.53 | BUILD PASS |
| Linux DTB | `mt7988a-bananapi-bpi-r4-pro-8x.dtb` | integriert |
| SD DTBO | `mt7988a-bananapi-bpi-r4-pro-sd.dtbo` | integriert |
| U-Boot | Armbian Filogic-Basis + minimaler R4-Pro-SD-Target / 2025.04 | BUILD PASS |
| Bootformat | extlinux | integriert |
| Firmware | `pinned` / `latest` / `ref`, 13 PHY/Wi-Fi-Payloadpfade + MT7988-WED-Blobs | integriert |
| Automatischer Check | `tools/bpi-r4pro8x-check.sh` | vorhanden |
| Hardwaretest | UART/SD | BOOT PASS (zweifach reproduziert) |
| Hardwaretest | Netzwerk/PCIe/Wi-Fi | HW PASS noch offen |

## Schnellstart

```bash
git clone https://github.com/GermanatorLM/build.git
cd build
git switch bpi-r4pro-8x

bash tools/bpi-r4pro8x-check.sh

./compile.sh build \
  BOARD=bananapir4pro8x \
  BRANCH=current \
  RELEASE=trixie \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

Die vollständige Build-, Flash-, UART- und Hardware-Checkliste steht in:

```text
docs/bpi-r4pro8x-bringup.md
```

## Firmware-Bundle

Die R4-Pro-spezifischen Binärblobs werden nicht unversioniert über einen
`latest`-Link geholt. Das Manifest liegt unter:

```text
packages/bpi-r4pro8x-firmware/manifest.tsv
```

Der Installer:

```text
packages/bpi-r4pro8x-firmware/install.sh
```

verwendet einen **festen Git-Snapshot**

```text
hhd-dev/linux-firmware
17c8530777b28c3b909dc505b95cf895159bd8b9
```

und prüft jeden Download gegen **Dateigröße und Git-Blob-ID**. Damit führt eine
spätere Änderung des Remote-Branches nicht stillschweigend zu anderen
Firmware-Dateien.

Im fertigen Image wird zusätzlich eine SHA256-Auditliste erzeugt:

```text
/usr/share/doc/bpi-r4pro8x-firmware/SHA256SUMS
```

Enthalten sind:

- Aeonsemi `as21x1x_fw.bin`
- MT7988 internes 2.5G-PHY-PMB
- MT7987 `i2p5ge-phy-DSPBitTb.bin`
- MT7987 `i2p5ge-phy-pmb.bin`
- MT7996 DSP
- MT7996 EEPROM 444
- MT7996 ROM Patch 444
- MT7996 WA 444
- MT7996 WM 444
- MT7996 EEPROM 233
- MT7996 ROM Patch 233
- MT7996 WA 233
- MT7996 WM 233

Die beiden vorhandenen MT7988-WED-Firmwaredateien
`mt7988_wo_0.bin` und `mt7988_wo_1.bin` werden weiterhin aus Armbians
vorhandenem Filogic-Blobbestand übernommen.

### Firmware-Build-Flags

Standard bleibt der fest gepinnte Stand:

```text
BPI_R4PRO8X_FIRMWARE_MODE=pinned
```

Ohne Angabe des Flags wird automatisch `pinned` verwendet.

Aktuellsten Firmwarestand aus dem **kanonischen**
`git.kernel.org/.../linux-firmware.git` verwenden:

```bash
BPI_R4PRO8X_FIRMWARE_MODE=latest
```

Bestimmten Commit, Tag oder Branch verwenden:

```bash
BPI_R4PRO8X_FIRMWARE_MODE=ref
BPI_R4PRO8X_FIRMWARE_REF=<commit-tag-oder-branch>
```

Beispiel als vollständiger Build:

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

Bei `latest` und `ref` wird der gewählte Ref zuerst auf einen konkreten
40-stelligen Commit aufgelöst. Dieser wird zusammen mit den tatsächlich
installierten Git-Blob-IDs, Größen und SHA256-Werten im Image abgelegt:

```text
/usr/share/doc/bpi-r4pro8x-firmware/SOURCE
/usr/share/doc/bpi-r4pro8x-firmware/RESOLVED_MANIFEST.tsv
/usr/share/doc/bpi-r4pro8x-firmware/SHA256SUMS
```

Damit ist `latest` zwar als Build-Eingabe absichtlich beweglich, das erzeugte
Image bleibt aber exakt auf den tatsächlich verwendeten Firmwarecommit
zurückverfolgbar. Für reproduzierbare Vergleichstests mit `ref` sollte
vorzugsweise direkt ein vollständiger Commit-SHA verwendet werden.

## Kernel-Ergänzungen für R4 Pro

Die R4-Pro-spezifischen Optionen bleiben board-lokal und verändern die normale
BPI-R4-Konfiguration nicht global:

```text
CONFIG_NET_DSA_MXL862=y
CONFIG_NET_DSA_TAG_MXL862_8021Q=y
CONFIG_AS21XXX_PHY=y
CONFIG_MEDIATEK_2P5GE_PHY=y
CONFIG_NET_MEDIATEK_SOC_WED=y
```

Da der eingebaute AS21xxx-Treiber seine per Device Tree benannte Firmware
nicht über `MODULE_FIRMWARE()` deklariert, nimmt ein board-lokaler
`initramfs-tools`-Hook `aeonsemi/as21x1x_fw.bin` explizit in das finale
Initramfs auf.

## Warum U-Boot zunächst minimal ist

Für den ersten Bring-up muss U-Boot nur zuverlässig:

1. UART initialisieren,
2. die SD-Karte lesen,
3. Armbians GPT/extlinux-Layout starten.

PCIe, Switch, 10G-PHY und Wi-Fi müssen im Bootloader noch nicht funktionieren.
Nach dem Kernelstart übernimmt Franks vollständiger Linux-Device-Tree die
Hardwarebeschreibung. Dadurch werden frühe Bootfehler nicht mit
Netzwerk-/PCIe-Problemen vermischt.

# Entwicklungs-Chronik

Diese Tabelle ist die zentrale Änderungsakte für den R4-Pro-Port. **Jede weitere
funktionale Änderung, jeder Fix und jede neue Hardwarestufe muss hier als neue
Zeile ergänzt werden.**

Für bereits vorhandene Commits ist die kurze SHA eingetragen. Bei einem neuen
Commit darf in derselben Commit-Zeile `SELF` stehen; der Commit-Subject macht
die Zeile eindeutig und verhindert einen sinnlosen Folgecommit nur zum
Nachtragen der eigenen SHA.

| Nr. | Commit | Grobschritt | Wesentliche Dateien | Stand |
|---:|---|---|---|---|
| 01 | `c4cc3bc` | Board-Target angelegt | `config/boards/bananapir4pro8x.csc` | implementiert |
| 02 | `e97354e` | R4-Pro-Family mit Frank-Kernel und 8-GB-ATF angelegt | `config/sources/families/filogic-r4pro.conf` | implementiert |
| 03 | `8a2a1a3` | Kernel-Patchsteuerung korrigiert: leerer Patchsatz statt erfundener Disable-Variable | `filogic-r4pro.conf` | korrigiert |
| 04 | `aa1d0e3` | Minimalen R4-Pro-U-Boot-SD-Target ergänzt | `451-add-bpi-r4pro-8x.patch` | implementiert |
| 05 | `85e919b` | Falsche Hunk-Zeilenanzahl im U-Boot-Patch korrigiert | U-Boot-Patch | korrigiert |
| 06 | `be3394e` | Gepinntes Firmware-Manifest mit 9 Payloads ergänzt | `packages/bpi-r4pro8x-firmware/manifest.tsv` | implementiert |
| 07 | `e7e03e7` | Firmware-Downloader/Verifier/Installer ergänzt | `packages/bpi-r4pro8x-firmware/install.sh` | implementiert |
| 08 | `97438f1` | Firmware-Bundle in den Board-Image-Build eingebunden | `bananapir4pro8x.csc` | implementiert |
| 09 | `9152ca5` | Automatischen statischen Preflight-Check ergänzt | `tools/bpi-r4pro8x-check.sh` | implementiert |
| 10 | `02c323d` | Build-, UART- und Hardware-Bring-up-Checkliste ergänzt | `docs/bpi-r4pro8x-bringup.md` | dokumentiert |
| 11 | `458570c` | README zum R4-Pro-Entwicklungsjournal umgebaut und Chronik-Regel eingeführt | `README.md` | dokumentiert |
| 12 | `d73fac1` | Manifest um einen expliziten `latest`-Ref erweitert | `manifest.tsv` | implementiert |
| 13 | `76bac9d` | Firmware-Installer um `pinned`, `latest` und frei wählbaren `ref` erweitert; verwendeter Commit wird auditiert | `install.sh` | implementiert |
| 14 | `c181c0c` | Firmware-Auswahl als Armbian-Build-Flags in den Board-Build verdrahtet | `bananapir4pro8x.csc` | implementiert |
| 15 | `94f7f02` | Preflight-Check um Firmware-Modi und Image-Auditprüfung erweitert | `bpi-r4pro8x-check.sh` | implementiert |
| 16 | `92c34e6` | Beim vorherigen Checker-Edit beschädigten TSV-Loop repariert | `bpi-r4pro8x-check.sh` | korrigiert |
| 17 | `4519df7` | Kconfig-Symbolprüfung im Checker präzisiert | `bpi-r4pro8x-check.sh` | korrigiert |
| 18 | `5ce7924` | Dynamische Firmwarequelle von der gepinnten Mirror-Quelle getrennt; `latest/ref` auf kanonisches linux-firmware gelegt | `manifest.tsv` | implementiert |
| 19 | `baf158c` | Installer löst `latest/ref` über `git.kernel.org` auf und lädt vom aufgelösten Commit | `install.sh` | implementiert |
| 20 | `5161209` | Preflight prüft die kanonische dynamische Firmwarequelle | `bpi-r4pro8x-check.sh` | implementiert |
| 21 | `8ca4003` | Build- und Bring-up-Doku um Firmware-Auswahlflags und Auditpfade ergänzt | `docs/bpi-r4pro8x-bringup.md` | dokumentiert |
| 22 | `438088f` | README um Firmware-Build-Flags erweitert und Chronik bis zum aktuellen Stand fortgeführt | `README.md` | dokumentiert |
| 23 | `4477252` | GitHub-Actions-Workflow für statischen Preflight und vollständigen gepinnten Trixie-Minimal-Build ergänzt | `.github/workflows/bpi-r4pro8x-build.yml` | implementiert |
| 24 | `ee04f57` | README-Chronik um den ausführbaren CI-Buildpfad ergänzt | `README.md` | dokumentiert |
| 25 | `CI #1` | Erster Remote-Preflight erfolgreich; erster Vollbuild scheitert vor dem eigentlichen Armbian-Build durch doppelte Docker-CLI (`docker` innerhalb Docker) | GitHub Actions Run `37543735463` | STATIC PASS / BUILD BLOCKED |
| 26 | `08090e2` | CI-Aufruf von `./compile.sh docker` auf `./compile.sh build` korrigiert; Armbian darf selbst nach Docker relaunch'en | `.github/workflows/bpi-r4pro8x-build.yml` | korrigiert |
| 27 | `85d1326` | README-Chronik um ersten CI-Lauf und Docker-CLI-Fix ergänzt | `README.md` | dokumentiert |
| 28 | `CI #3` | Preflight erneut erfolgreich; `./compile.sh build` wird auf GitHub automatisch zu Docker relaunch'ed und endet weiterhin im Docker-in-Docker-Guard | GitHub Actions Run `37544227560` | STATIC PASS / BUILD BLOCKED |
| 29 | `2673b53` | CI setzt `PREFER_DOCKER=no`, damit Armbian den nativen sudo-Buildpfad statt des problematischen Docker-Relaunchs nutzt | `.github/workflows/bpi-r4pro8x-build.yml` | korrigiert |
| 30 | `442e396` | README-Chronik um zweiten CI-Befund und nativen Buildpfad ergänzt | `README.md` | dokumentiert |
| 31 | `CI #5` | Preflight erfolgreich; Build weiterhin im Docker-Guard, weil der gespeicherte Workflow trotz früherer Absicht noch tatsächlich `./compile.sh docker` enthielt | GitHub Actions Run `37544731262` | STATIC PASS / BUILD BLOCKED |
| 32 | `16465ec` | Tatsächlichen Workflow-Command auf `./compile.sh build ... PREFER_DOCKER=no` korrigiert und CI-Doku präzisiert | `.github/workflows/bpi-r4pro8x-build.yml`, `README.md` | korrigiert |
| 33 | `CI #6` | Preflight erfolgreich; echter Port-Build erreicht und U-Boot 2025.04 erfolgreich gebaut. Postprocessing scheitert danach, weil TF-A 2.14 `fiptool` nicht mehr am von Armbians altem Filogic-Hook erwarteten Pfad erzeugt | GitHub Actions Run `37545232848` | STATIC PASS / U-BOOT BUILD PASS / BUILD BLOCKED |
| 34 | `3f3d673` | R4-Pro-spezifischen `uboot_custom_postprocess` ergänzt: TF-A-2.14-`fiptool` wird über den Top-Level-Target mit `PLAT=mt7988` gebaut; normaler Filogic/R4-Pfad bleibt unverändert | `config/sources/families/filogic-r4pro.conf`, `README.md` | korrigiert |
| 35 | `CI #7` | Vollständiger Trixie-Minimal-Build erfolgreich: U-Boot 2025.04, TF-A/FIP, Linux 6.18.53, gepinnte 9-Blob-Firmware und finales SD-Image erzeugt | GitHub Actions Run `37545758241` | BUILD PASS |
| 36 | `SELF` | Erfolgreichen BUILD-PASS-Meilenstein samt Image-/Kernelstand in der README-Chronik dokumentiert | `README.md` | dokumentiert |
| 37 | `HW #1` | Erster physischer SD-/UART-Boot: BL2/DRAM (8192 MB), BL31, U-Boot, SD/extlinux und Kernel 6.18.53 starten; U-Boot verwirft jedoch das SD-Overlay wegen fehlendem `fdtoverlay_addr_r`, danach fehlt das Rootfs-Gerät | UART-Log `uart-2026-10-07-07e66bd41.log`, `docs/bpi-r4pro8x-bringup.md` | BOOT BLOCKED |
| 38 | `SELF` | R4-Pro-lokales U-Boot-Text-Environment mit `fdtoverlay_addr_r=0x62080000` ergänzt und Preflight dagegen abgesichert; gemeinsame Filogic-Konfiguration bleibt unverändert | `451-add-bpi-r4pro-8x.patch`, `bpi-r4pro8x-check.sh`, `README.md` | STATIC PASS |
| 39 | `CI #8` | Overlay-Adressfix vollständig gebaut; erzeugtes SD-Image per SHA256 und eingebettetem `fdtoverlay_addr_r=0x62080000` auditiert und bitgenau auf die 64-GB-SD-Karte geschrieben | GitHub Actions Run `37606136761`, `docs/bpi-r4pro8x-bringup.md` | BUILD PASS |
| 40 | `HW #2` | Zwei aufeinanderfolgende physische SD-Cold-Boots laden das R4-Pro-SD-Overlay, mounten `mmcblk0p5` read/write und erreichen SSH, Login-Prompt sowie `multi-user.target`; Ethernet scheitert weiterhin beim SRAM-Pool | UART-Logs `uart-2026-10-07-a298f8ac3-hw2.log` und `uart-2026-10-07-a298f8ac3-hw2-repeat.log`, `docs/bpi-r4pro8x-bringup.md` | BOOT PASS / HW BLOCKED |
| 41 | `SELF` | Frühesten HW-Fehler auf fehlendes `CONFIG_SRAM` in der Current-Konfiguration zurückgeführt und `SRAM` im vorhandenen R4-Pro-8X-Kernel-Hook aktiviert; gemeinsame Filogic-Konfiguration bleibt unverändert | `bananapir4pro8x.csc`, `bpi-r4pro8x-check.sh`, `docs/bpi-r4pro8x-bringup.md` | STATIC PASS / BUILD PENDING |
| 42 | `CI #9` | Board-lokalen SRAM-Fix vollständig gebaut, `CONFIG_SRAM=y` im Raw-Image nachgewiesen, Artefakt-Hash verifiziert und das Image mit identischem Roh-Rücklese-Hash auf die 64-GB-SD-Karte geschrieben | GitHub Actions Run `37632230455`, `docs/bpi-r4pro8x-bringup.md` | BUILD PASS / HW TEST PENDING |
| 43 | `HW #3` | Physischer SD-Cold-Boot bestätigt den SRAM-Fix: Ethernet-MAC, beide DSA-Bäume und der MaxLinear-Switch initialisieren; der bisherige SRAM-Pool-Fehler ist verschwunden. Die beiden Aeonsemi-10G-PHYs scheitern nun früher reproduzierbar, weil ihre Firmware beim Built-in-Probe noch nicht im Initramfs verfügbar ist | UART-Log `uart-2026-10-07-3d97a2121-hw3.log`, `docs/bpi-r4pro8x-bringup.md` | ETHERNET CORE HW PASS / 10G PHY BLOCKED |
| 44 | `SELF` | Bereits gepinnte Aeonsemi-Firmware per R4-Pro-8X-spezifischem `initramfs-tools`-Hook in das finale Initramfs aufgenommen; ein eingebetteter Firmware-SHA256 invalidiert den Initramfs-Cache bei Payloadwechseln | `bananapir4pro8x.csc`, `bpi-r4pro8x-check.sh`, `docs/bpi-r4pro8x-bringup.md` | STATIC PASS / BUILD PENDING |
| 45 | `CI #10` | Aeonsemi-Initramfs-Fix vollständig gebaut; Image- und ZIP-Integrität geprüft und die 290272-Byte-Firmware mit identischem SHA256 im finalen `uInitrd` nachgewiesen | GitHub Actions Run `37664464391`, `docs/bpi-r4pro8x-bringup.md` | BUILD PASS / HW TEST PENDING |
| 46 | `SD #4` | Neues Image auf die eindeutig als USB/removable identifizierte 64-GB-SD-Karte geschrieben. Ein erster Rücklesehash wich nach unerwünschtem read/write-Automount ab; nach deaktiviertem Automount erneut geschrieben und über exakt 1472200704 Bytes bitgenau verifiziert | `docs/bpi-r4pro8x-bringup.md` | SD WRITE/READBACK PASS |
| 47 | `HW #4` | Zwei SD-Boots bestätigen den Initramfs-Fix: Beide Aeonsemi-AS21xxx-PHYs laden reproduzierbar Firmware 1.9.1 und binden an den spezifischen Treiber ohne die bisherigen 60-Sekunden-Timeouts. Der vollständige Wiederholungs-Cold-Boot erreicht Login; Wi-Fi scheitert danach separat an fehlendem unsuffigiertem MT7996-ROM-Patch | UART-Logs `uart-2026-10-08-4ce2a690c-hw4-capture.log` und `uart-2026-10-08-4ce2a690c-hw4-repeat.log`, `docs/bpi-r4pro8x-bringup.md` | AEONSEMI 10G PHY HW PASS / WI-FI BLOCKED |
| 48 | `SELF` | Den vom R4-Pro-8X-Cold-Boot und Frank-Kernel ausgewählten MT7996-444-Firmwaresatz am bestehenden linux-firmware-Commit verifiziert und zusätzlich zum unveränderten 233-Satz gepinnt; Preflight sowie vollständiger 13-Payload-Install-/Audit-Test bestanden | `manifest.tsv`, `bpi-r4pro8x-check.sh`, `docs/bpi-r4pro8x-bringup.md` | STATIC PASS / BUILD PENDING |
| 49 | `CI #11` | MT7996-444-Firmwarefix vollständig gebaut; heruntergeladenes Artefakt, Image-SHA256, read-only Rootfs, extlinux und alle 13 gepinnten Firmware-Auditeinträge verifiziert | GitHub Actions Run `37837041222`, `docs/bpi-r4pro8x-bringup.md` | BUILD PASS / HW TEST PENDING |
| 50 | `PR BOT` | Upstream-Wartungscheck meldet das fehlende Imager-Bild `board-images/bananapir4pro8x.png` im separaten Repository `armbian/armbian.github.io`; alle portrelevanten Build- und Analysechecks bleiben erfolgreich | GitHub Actions Run `37837035403`, `docs/bpi-r4pro8x-bringup.md` | EXTERNAL ASSET OPEN / BUILD UNAFFECTED |
| 51 | `SD #5` | MT7996-444-Testimage auf die eindeutig als USB/removable identifizierte 64-GB-SD-Karte geschrieben; Desktop-Automount vorab deaktiviert und exakt 1476395008 Bytes mit identischem SHA256 roh zurückgelesen | `docs/bpi-r4pro8x-bringup.md` | SD WRITE/READBACK PASS / HW TEST READY |
| 52 | `HW #5` | Vollständiger SD-Cold-Boot bestätigt den MT7996-444-Firmwaresatz: ROM-Patch sowie WM, DSP und WA laden und das System erreicht Login und `multi-user.target`. Der Wi-Fi-Probe scheitert danach separat an fehlender RF-/EEPROM-Kalibration | UART-Log `uart-2026-10-09-632a0a6e0-hw5.log`, `docs/bpi-r4pro8x-bringup.md` | MT7996 444 FW HW PASS / WIFI CALIBRATION BLOCKED |
| 53 | `SELF` | Die beiden vom gebauten MT7996-Treiber gewählten internen-FEM-EEPROM-Defaults für 444 und 233 am bestehenden Firmware-Pin verifiziert und dem auditierten Board-Paket hinzugefügt | `manifest.tsv`, `bpi-r4pro8x-check.sh`, `docs/bpi-r4pro8x-bringup.md` | STATIC PASS / BUILD PENDING |
| 54 | `SELF` | Den optionalen board-spezifischen MT7996-EEPROM-Abruf im R4-Pro-lokalen Kernel-Patchsatz auf direkten Dateizugriff umgestellt; fehlende Datei löst keinen 60-Sekunden-Sysfs-Fallback mehr aus | `filogic-r4pro.conf`, Kernel-Patch, `bpi-r4pro8x-check.sh`, `docs/bpi-r4pro8x-bringup.md` | STATIC PASS / BUILD PENDING |
| 55 | `CI #12` | MT7996-Kalibrationsfix vollständig gebaut; Kernel-Patch, heruntergeladenes Artefakt, Image-SHA256, read-only Rootfs, extlinux und alle 15 gepinnten Firmware-Auditeinträge verifiziert | GitHub Actions Run `37898648988`, `docs/bpi-r4pro8x-bringup.md` | BUILD PASS / HW TEST PENDING |
| 56 | `SD #6` | MT7996-Kalibrationstestimage auf die eindeutig identifizierte 64-GB-SD-Karte geschrieben; Automount vorab deaktiviert und exakt 1476395008 Bytes mit identischem SHA256 roh zurückgelesen | `docs/bpi-r4pro8x-bringup.md` | SD WRITE/READBACK PASS / HW TEST READY |
| 57 | `HW #6` | Vollständiger SD-Cold-Boot bestätigt den MT7996-Kalibrationsfix: Die optionale RF-Datei endet sofort mit `-ENOENT`, der Treiber nutzt den EEPROM-Default und registriert `mt76-phy0`; Login und `multi-user.target` werden ohne die bisherigen 60-Sekunden-Fallbacks erreicht | UART-Log `uart-2026-10-09-c77e5da20-hw6.log`, `docs/bpi-r4pro8x-bringup.md` | MT7996 PROBE HW PASS / OTHER HW BLOCKERS REMAIN |

| 58 | `SELF` | Fehlenden PCA9555-Treiber in der gebauten Konfiguration bestätigt und `GPIO_PCA953X` im Board-Hook aktiviert. XS-PHY-Meldung nachträglich als vorübergehenden Probe-Aufschub eingeordnet | `bananapir4pro8x.csc`, `bpi-r4pro8x-check.sh`, `docs/bpi-r4pro8x-bringup.md` | STATIC PASS / BUILD PENDING |
| 59 | `SELF` | Speicher ausschließlich lesend geprüft. SPI-NAND und WLAN-EEPROM bestätigt. Gemeinsamer MMC-Controller verhindert gleichzeitigen SD/eMMC-Zugriff. NOR-Bestückung beim Pro 8X bleibt unbelegt | `docs/bpi-r4pro8x-bringup.md` | STORAGE INVENTORY / EMMC TEST PENDING |
| 60 | `SELF` | Hersteller-NAND-Boot gestartet. U-Boot schreibt nach ungültigen Environment-Prüfsummen selbstständig nach UBI. Autoboot nicht rechtzeitig gestoppt. Kein Linux-Prompt oder eMMC-Nachweis | UART-Beobachtungen, `docs/bpi-r4pro8x-bringup.md` | NAND TEST INCOMPLETE / AUTOMATIC UBI WRITES |
| 61 | `SELF` | UART nach Debug-Neuverbindung wieder erreichbar. Hersteller-Linux erkennt eMMC 8GTF4R mit HS400, Bootpartitionen und RPMB. EXT_CSD lesbar. Hersteller-System mountet NAND und NVMe schreibbar | UART-Mitschnitt, `docs/bpi-r4pro8x-bringup.md` | EMMC DETECTION PASS ON VENDOR KERNEL |
| 62 | `SELF` | Ethernet-MACs im Hersteller-System lesend geprüft. U-Boot speichert seine zufällige eth0-Adresse als `ethaddr`. eth1 und eth2 bleiben zufällig. Keine Werks-MAC bestätigt | UART-Mitschnitt, `docs/bpi-r4pro8x-bringup.md` | PERSISTED RANDOM MAC / FACTORY MAC UNCONFIRMED |
| 63 | `SELF` | Vorhandenes Hersteller-System von eMMC bis zur Root-Konsole gebootet. Root-FIT stammt aus `mmcblk0p5`. eMMC-Overlay ist schreibbar. MACs unterscheiden sich vom NAND-System; mehrere Hersteller-Warnungen bleiben sichtbar | UART-Mitschnitt, `docs/bpi-r4pro8x-bringup.md` | VENDOR EMMC BOOT PASS / ARMBIAN EMMC UNTESTED |
| 64 | `SELF` | MAC-Herkunft lesend geklärt: eMMC-Environment enthält eth0-Adresse. Alle drei NAND-NVMEM-MAC-Felder enthalten nur `ff`; eth1 und eth2 nutzen Linux-Zufallsadressen | UART-Mitschnitt, `docs/bpi-r4pro8x-bringup.md` | MAC SOURCE TRACE PASS / FACTORY MAC UNCONFIRMED |
| 65 | `SELF` | `da:68:a5:94:9a:ee` als Nutzer-Referenz dokumentiert, ohne Konfigurationsänderung. NAND und eMMC verwenden Linux 6.6.93; Kernel-Payloads haben unterschiedliche Größen und SHA256-Werte | UART-Mitschnitt, `docs/bpi-r4pro8x-bringup.md` | VENDOR IMAGES NOT IDENTICAL |
| 66 | `SELF` | OpenWrt-Importer für CRC-geprüfte eMMC-MAC implementiert. Board-EEPROM an `0x57` erhält nur nach Bestätigung einen gesicherten Datensatz ab `0x40`. Lokale Format- und Sicherheitstests bestehen | `packages/bpi-r4pro8x-mac/`, `tools/bpi-r4pro8x-mac-test.sh` | STATIC PASS / EEPROM WRITE UNTESTED |
| 67 | `SELF` | Board-lokalen EEPROM-Boot-Leser vor Netzwerkstart eingebunden. Basis-MAC setzt eth0; Zufallsadressen von eth1/eth2 erhalten stabile Ableitungen. Isolierte Integrationstests und Unit-Prüfung bestehen | Board-Hook, MAC-Paket, Preflight, Workflow | STATIC PASS / BUILD AND HW PENDING |
| 68 | `SELF` | Herstellerseite bestätigt P24C02A ausdrücklich für den R4 Pro. Quelle ergänzt; Write-Protect-Verschaltung und erster EEPROM-Schreibtest bleiben offen | MAC-Paketdokumentation, Bring-up-Dokumentation | EEPROM TYPE DOCUMENTED / WRITE UNTESTED |
| 69 | `SELF` | Echter OpenWrt-Vorabcheck zeigt fehlende `od`- und `cksum`-Werkzeuge. Helfer nutzen jetzt `hexdump` und eine getestete POSIX-Checksumme in AWK. Datensatzformat bleibt unverändert | MAC-Paket, Fixture-Tests | STATIC PASS / OPENWRT COMPATIBILITY FIX |
| 70 | `SELF` | Erste Import-Vorschau verweigert Hersteller-DT mit `page-size` statt `pagesize`. Beide Schreibweisen unterstützt. Erneute Vorschau liest eMMC-MAC korrekt; EEPROM-Hash bleibt unverändert | MAC-Paket, UART-Mitschnitt | OPENWRT IMPORT DRY-RUN PASS / WRITE PENDING |
| 71 | `SELF` | USB-Stick V7 Data Drive 3.0 identifiziert. Drei alte Partitionen durch GPT und ext4 ersetzt. Schreib-/Lesetest besteht | USB-Backup-Datenträger, UART-Mitschnitt | USB BACKUP STORAGE PASS / EEPROM WRITE PENDING |
| 72 | `SELF` | OpenWrt-Importer sichert Daten auf USB und programmiert die EEPROM-MAC. Vollständige Rückleseprüfung, Leser und schreibfreie Wiederholung bestehen | MAC-Paket, EEPROM, UART-Mitschnitt | EEPROM PROVISIONING HW PASS / ARMBIAN BOOT PENDING |
| 73 | `SELF` | SPI-NAND-Cold-Boot erhält EEPROM-Datensatz. Importer liest weiterhin eMMC-MAC. Leser und schreibfreie Wiederholung bestehen; OpenWrt-Netzwerk bleibt unverändert | MAC-Paket, UART-Mitschnitt | NAND IMPORT REPEAT PASS / EEPROM PERSISTENCE PASS |
| 74 | `SELF` | Armbian-Bootleser erzeugt fortlaufende MACs für alle RJ45-Interfaces und interne Controller. Fehlender gültiger EEPROM-Datensatz nutzt festen Fallback. Kollisionsrisiko dokumentiert | MAC-Paket, Fixture-Tests | STATIC PASS / NEW IMAGE AND HW PENDING |
| 75 | `SELF` | Frontplattennamen lan1–lan6, wan und fpc eingeführt. Hersteller bestätigt FPC-Port 3. Hardwarebasierte GMAC-Umbenennung ordnet eth0 dem MxL und eth1 dem internen Switch zu | 8X-DT-Patch, Naming-Dienst, Fixture-Tests | STATIC PASS / BUILD AND HW PENDING |
| 76 | `SELF` | Gemeinsamen festen Fallback entfernt. Leeres bekanntes EEPROM erhält einmalig einen zufälligen lokalen MAC-Block mit Backup und Rückleseprüfung. WLAN bleibt beim Treiber | MAC-Paket, Provisionierungs-Tests | STATIC PASS / RANDOM PROVISIONING HW PENDING |
| 77 | `SELF` | CI-Run 37972445834 scheitert vor dem Imagebuild an SC2015. Explizite Bedingungen ersetzen zwei UND/ODER-Ketten ohne Verhaltensänderung | Naming-Script, OpenWrt-Importer | STATIC PASS / BUILD PENDING |
| 78 | `SELF` | CI-Run 37972714444 scheitert beim 8X-DTB: port6 ist vor seiner Definition nicht auflösbar. lan6-Label direkt im Knoten gesetzt | 8X-DT-Patch | STATIC AND DT COMPILE PASS / BUILD PENDING |
| 79 | `SELF` | CI-Run 37975601363 baut erfolgreich. SD-Schreiben und Rückleseprüfung bestehen. Cold Boot bestätigt Frontplattennamen und zehn EEPROM-MACs | Image, UART-Mitschnitt | BUILD / SD / BOOT / PORT IDENTITY PASS |
| 80 | `SELF` | Wi-Fi-Probe nutzt 444 statt zuvor erfolgreichem 233. Erneuter Probe und PCIe-Funktionsreset scheitern ebenfalls. Alle Firmware-Hashes stimmen | UART-Mitschnitte, Hardwaretests | WIFI FAIL / FULL POWER CYCLE PENDING |
| 81 | `SELF` | Board-lokaler MT7996-Patch protokolliert Variantenerkennung, Hardware-Register und ROM-Patch-Pfad. Automatische Auswahl bleibt unverändert | Kernel-Diagnosepatch, Preflight | STATIC PASS / BUILD AND HW PENDING |
| 82 | `SELF` | Vollständige Stromtrennung ermöglicht 233-Firmwarestart ohne Patch-Timeout. phy0 und wlan0 vorhanden. 6 GHz bleibt mit Länderkennung 00 gesperrt | UART-Kaltstartlog, Wi-Fi-Inventar | WIFI PROBE HW PASS / RF TEST PENDING |
| 83 | `SELF` | Wi-Fi-I2C-EEPROM erneut vollständig gelesen und unverändert bestätigt. Laufende Regulatory-Domain auf Nutzerwunsch auf DE gesetzt; untere 6-GHz-Kanäle freigegeben | UART-Diagnose, Laufzeitkonfiguration | DE RUNTIME PASS / RF TEST PENDING |
| 84 | `SELF` | RF-Datei meldet externe EEPROM-Daten statt Erfolg ohne Daten. MT7996 verwirft gültige Datei nicht mehr vor eFuse-Lesen | R4-Pro-Kernelpatch, C-Stub-Tests, Preflight | STATIC / C-STUB PASS / BUILD AND HW PENDING |
| 85 | `SELF` | Nutzer-Hotspot auf 5975 MHz gefunden. WPA3-SAE, PMF, DHCP und zehn Gateway-Pings bestehen mit bisherigem Kernel | UART-Mitschnitt, private RAM-Konfiguration | 6GHZ CLIENT SMOKE PASS / REPEAT AND THROUGHPUT PENDING |
| 86 | `SELF` | USB-Geräte erkannt, aber ACM, Serial und USB-Netzwerktreiber fehlen. Board-Hook aktiviert Module für RAK5166, RM520N-GL und AHM27292U | Board-Hook, Preflight, Bring-up-Dokumentation | STATIC PASS / BUILD AND HW PENDING |
| 87 | `SELF` | PTP-Clock-Unterstützung und PHY-Timestamping im Board-Hook aktiviert. linuxptp ergänzt. Aktueller WAN-Port meldet keine Hardware-Clock | Board-Hook, Paketliste, Preflight | STATIC PASS / BUILD AND PTP HW PENDING |
| 88 | `SELF` | CI-Run 37992263277 baut USB-Erweiterungen, PTP, linuxptp und Wi-Fi-Patches erfolgreich. Download, Imagekonfiguration und 15 Firmware-Prüfsummen bestehen | GitHub Actions, Buildlog, Imageprüfung | BUILD PASS / IMAGE AUDIT PASS / HW TEST PENDING |
| 89 | `SELF` | Image aus Run 37992263277 auf 64-GB-SD geschrieben. Vollständiger Rücklese-Hash stimmt. Kartenleser sicher abgeschaltet | SD-Schreiblog, SHA256, Bring-up-Dokumentation | SD FLASH PASS / HW TEST PENDING |
| 90 | `SELF` | Neues Image erreicht Erstlogin. QMI, Modem-Serial, ACM und ALFA-RNDIS binden. PTP-Kern registriert. Wi-Fi-444-Probe scheitert erneut | UART-Bootlog, Bring-up-Dokumentation | BOOT PASS / USB BIND PASS / WIFI FAIL / HW PARTIAL |
| 91 | `SELF` | Wi-Fi-Diagnose bestätigt Firmware-Hashes und fehlendes Radio. Board für vollständige Stromtrennung heruntergefahren. TF-A unterstützt Power-down nicht | UART-Diagnoselog, Bring-up-Dokumentation | WIFI FAIL / FULL POWER CYCLE PENDING |
| 92 | `SELF` | Bestätigter Stromtrennungstest reproduziert Variante 444 mit Registerwert null und Probe-Timeout. Firmware-Hashes stimmen. LED-State-Dienst scheitert separat | Vollständiger UART-Kaltstart, Bring-up-Dokumentation | BOOT PASS / WIFI FAIL / POWER CYCLE NOT SUFFICIENT |
| 93 | `SELF` | Treiber-Neustart und Rebind reproduzieren Wi-Fi-Timeout. Register-Tracing bestätigt Remap-Rücklesung, Resetbit und Variantenregisterwert null | UART-Registertrace, Bring-up-Dokumentation | REGISTER TRACE PASS / WIFI FAIL |
| 94 | `SELF` | Isolierter Wi-Fi-Bus-Reset scheitert mit -25 und PCIe-AER-Fehlern. Zweiter Reset wird nicht ausgeführt. Board sauber heruntergefahren | UART-Resetlog, Bring-up-Dokumentation | BUS RESET FAIL / POWER CYCLE REQUIRED |
| 95 | `SELF` | Kaltstart stellt Wi-Fi-PCIe-Erkennung nach Bus-Reset wieder her. Keine erneute AER-Fehlerserie im Bootlog. Wi-Fi-Probe scheitert unverändert | UART-Wiederherstellungsboot, Bring-up-Dokumentation | BOOT PASS / PCIE RECOVERY PASS / WIFI FAIL |
| 96 | `SELF` | Board-lokale Diagnose liest MT_PAD_GPIO vor und nach internem Wi-Fi-Reset. Resetfolge und Variantenauswahl bleiben erhalten. Patch- und C-Tests bestehen | Wi-Fi-Patch, Preflight, Bring-up-Dokumentation | STATIC PASS / BUILD AND RESET COMPARISON PENDING |
| 97 | `SELF` | Diagnosebuild 38003437809 besteht Preflight und Imagebau. Download und Imageaudit bestehen. Neue Resetmeldung im gebauten Treiber bestätigt | GitHub Actions, Buildlog, Imageaudit, UART | BUILD PASS / IMAGE AUDIT PASS / HW TEST PENDING |
| 98 | `SELF` | Geprüftes Reset-Diagnoseimage auf 64-GB-SD geschrieben. Vollständiger Rücklese-Hash stimmt. Kartenleser sicher abgeschaltet | SD-Schreiblog, SHA256, Bring-up-Dokumentation | SD FLASH PASS / RESET COMPARISON PENDING |
| 99 | `SELF` | Neues Diagnoseimage bootet. Variantenregister ist vor und nach internem Reset null. Wi-Fi-444-Firmwarestart scheitert weiterhin mit -11 | UART-Kaltstart, Bring-up-Dokumentation | BOOT PASS / RESET DIAGNOSTIC HW PASS / WIFI FAIL |
| 100 | `SELF` | Früher erfolgreiches Image 37975601363 für vollständigen Rücktest geprüft. Firmware-Audits stimmen überein. SD-Schreibschutz vorbereitet; Board sauber heruntergefahren | Imagevergleich, UART, Bring-up-Dokumentation | COMPARISON PREPARATION PASS / SD TRANSFER PENDING |
| 101 | `SELF` | Vergleichsimage 37975601363 auf identifizierte 64-GB-SD geschrieben. Vollständiger Rücklese-Hash stimmt. Kartenleser abgeschaltet; UART-Aufzeichnung vorbereitet | SD-Schreiblog, Bring-up-Dokumentation | COMPARISON SD FLASH PASS / COLD BOOT PENDING |
| 102 | `SELF` | Früher erfolgreiches Image reproduziert beim Kaltstart denselben Wi-Fi-Patchstart-Timeout. Firmware- und EEPROM-Hashes stimmen; beide PCIe-Funktionen bleiben sichtbar | Vollständiges Vergleichs-UART-Log, Bring-up-Dokumentation | BOOT PASS / WIFI COMPARISON FAIL / CAUSE OPEN |
| 103 | `SELF` | Kaltstart ohne externe USB-Geräte reproduziert Wi-Fi-Patchstart-Timeout. Nur USB-Hubs bleiben sichtbar. Firmware- und EEPROM-Hashes stimmen weiterhin | Separates UART-Log, Bring-up-Dokumentation | BOOT PASS / USB ISOLATION NO RECOVERY / WIFI FAIL |
| 104 | `SELF` | Nach BE14-Neueinsetzen startet ein Boot mit erneut angeschlossenen Modulen die 233-Firmware und meldet mt76-phy0. Ursache bleibt unisoliert | Nachträglich ausgewertetes UART-Log, Bring-up-Dokumentation | BOOT / WIFI FIRMWARE START PASS / CLIENT UNTESTED |
| 105 | `SELF` | Folgender isolierter Boot nach BE14-Neueinsetzen ohne andere Module verwendet wieder 444-Firmware und scheitert mit -11. Hashprüfungen bestehen | Separates UART-Log, Bring-up-Dokumentation | BOOT PASS / WIFI FAIL / VARIANT CHANGE OBSERVED |
| 106 | `SELF` | Angeforderter Warmstart bestätigt TF-A-Software-Reset. Wi-Fi-444-Patchstart scheitert weiterhin. Linux anschließend sauber heruntergefahren; Kalt-/Warmvergleich vorbereitet | UART-Mitschnitt, Bring-up-Dokumentation | WARM BOOT PASS / WIFI FAIL / COLD-WARM PAIR PENDING |
| 107 | `SELF` | Angefordertes Kalt-/Warmvergleichspaar abgeschlossen. Beide Starts wählen 444-Payload und scheitern mit -11. Firmware- und EEPROM-Prüfungen bestehen | Durchgehendes UART-Log, Bring-up-Dokumentation | COLD AND WARM BOOT PASS / WIFI FAIL / CAUSE OPEN |
| 108 | `SELF` | Erstes Vergleichspaar mit wieder eingesetzten Modulen reproduziert Wi-Fi-444-Timeout in Kalt- und Warmstart. Linux heruntergefahren; zweites Paar vorbereitet | Separates UART-Log, Bring-up-Dokumentation | PAIR 1 BOOT PASS / WIFI FAIL / PAIR 2 PENDING |
| 109 | `SELF` | Zweites Paar abgeschlossen. Alle vier Starts mit eingesetzten Modulen wählen 444-Payload und scheitern mit -11. Hashprüfungen bestehen | Beide Vergleichslogs, Bring-up-Dokumentation | FOUR BOOTS PASS / FOUR WIFI FAILURES / CAUSE OPEN |
| 110 | `SELF` | Lesende Analyse bestätigt registerbasierte Variantenauswahl vor Kalibration. Remap ist gesperrt. Gefilterte Diagnoseprobe vorbereitet, aber Sicherheitsprüfung verhindert Ausführung | Treiberquelle, PCIe-/UART-Vergleich, Bring-up-Dokumentation | SOURCE ANALYSIS PASS / PROBE AUTHORIZATION PENDING |

## Verbindliche Regel für kommende Änderungen

Ab jetzt gilt für diesen Branch:

1. **Eine technische Änderung = ein nachvollziehbarer Grobschritt.**
2. Jeder Fix bekommt eine eigene Chronikzeile; alte Fehler werden nicht aus der
   Historie „wegdokumentiert“.
3. Jede neue Hardwarefunktion wird erst als **HW PASS** markiert, wenn sie nach
   einem Cold Boot reproduzierbar funktioniert.
4. Ein erfolgreicher Compile ohne Hardwaretest wird nur als **BUILD PASS**
   bezeichnet.
5. Ein reiner statischer Check wird nur als **STATIC PASS** bezeichnet.
6. Neue Firmwarestände müssen Quelle, Pin und Verifikation dokumentieren.
7. Neue Kernel-/U-Boot-/ATF-Pins werden mit Grund und erwarteter Wirkung
   eingetragen.
8. Solange der Bring-up läuft, soll die Historie nicht so gesquasht werden, dass
   die einzelnen Debugschritte nicht mehr nachvollziehbar sind.

## Statusbegriffe

| Status | Bedeutung |
|---|---|
| `IMPLEMENTED` | Code ist vorhanden, aber noch nicht vollständig gebaut/getestet |
| `STATIC PASS` | lokale/statische Validierung bestanden |
| `BUILD PASS` | Armbian-Image wurde erfolgreich erzeugt |
| `BOOT PASS` | Bootkette bis Login reproduzierbar |
| `HW PASS` | konkrete Hardwarefunktion nach Cold Boot reproduzierbar |
| `BLOCKED` | reproduzierbarer Fehler, nächster Debugschritt dokumentiert |

## Relevante Dateien

```text
config/boards/bananapir4pro8x.csc
config/sources/families/filogic-r4pro.conf
patch/u-boot/u-boot-filogic/451-add-bpi-r4pro-8x.patch
packages/bpi-r4pro8x-firmware/manifest.tsv
packages/bpi-r4pro8x-firmware/install.sh
tools/bpi-r4pro8x-check.sh
docs/bpi-r4pro8x-bringup.md
README.md
```

## CI-Buildpfad

Für reproduzierbare Remote-Tests existiert zusätzlich:

```text
.github/workflows/bpi-r4pro8x-build.yml
```

Der Workflow führt zwei voneinander abhängige Jobs aus:

```text
R4 Pro static preflight
        |
        v
R4 Pro Trixie minimal image (pinned firmware)
```

Der Image-Build ruft `./compile.sh build` mit `PREFER_DOCKER=no` auf und
verwendet damit im GitHub-Runner bewusst Armbians nativen/sudo-Pfad. Standardmäßig
`BPI_R4PRO8X_FIRMWARE_MODE=pinned`. Logs werden auch bei Fehlern als
GitHub-Actions-Artefakt gesichert; ein erfolgreich erzeugtes Image wird separat
als kurzlebiges CI-Artefakt abgelegt.

## Letzter erfolgreicher Build

GitHub Actions Run:

```text
37837041222
```

Erzeugtes Image:

```text
Armbian-unofficial_26.11.0-trunk_Bananapir4pro8x_trixie_current_6.18.53_minimal.img
```

Build-Ergebnis:

```text
STATIC PASS
DEPENDENCY REVIEW PASS
BOARD CONFIG PASS
SHELLCHECK PASS
U-BOOT BUILD PASS
TF-A/FIP PASS
KERNEL 6.18.53 PASS
CONFIG_SRAM=y PASS
PINNED FIRMWARE PASS (13 Payloads)
AEONSEMI FIRMWARE IN UINITRD PASS
IMAGE BUILD PASS
```

Das CI-Artefakt enthält das Image plus `.sha` und Build-Metadaten. Sein
SHA256-Hash ist `ca35eea557130266d1ef8ad68f5f5f2b83be6e3b9737eec7f17f0a5d17a842f9`.
Der allgemeine SD-`BOOT PASS` ist mit diesem Image erneut erreicht. Der
Ethernet-SRAM-Fix ist auf der Zielhardware bestätigt: MAC, DSA und der
MaxLinear-Switch initialisieren ohne den bisherigen SRAM-Pool-Fehler. Der
Aeonsemi-Initramfs-Fix ist auf der Hardware reproduzierbar bestätigt. Der
nächste isolierte Blocker war die fehlende unsuffigierte MT7996-Wi-Fi-
Firmwarevariante. Der board-lokale Manifest-Fix ist als `BUILD PASS` bestätigt;
der Hardwaretest steht noch aus.

## Nächster Meilenstein

Der nächste sinnvolle Stand ist:

```text
BOOT PASS
ETHERNET CORE HW PASS
AEONSEMI 10G PHY HW PASS
  -> neues MT7996-444-Image auf SD schreiben und Cold Boot aufzeichnen
  -> Wi-Fi-Probe ohne Firmware-Timeout abschließen
  -> Management-Ethernet und interne 2.5G-PHYs einzeln prüfen
  -> Linktests an allen externen Ports
```

Danach werden PCIe/NVMe und Wi-Fi weiterhin einzeln als Hardware-Meilensteine
abgearbeitet.

---

## Upstream Armbian

Dieses Repository basiert auf dem
[Armbian Build Framework](https://github.com/armbian/build). Die allgemeine
Armbian-Dokumentation befindet sich unter
[docs.armbian.com](https://docs.armbian.com/Developer-Guide_Overview/).

Für Änderungen, die nicht spezifisch zum BPI-R4 Pro 8X gehören, gelten weiterhin
die Upstream-Armbian-Konventionen und `CONTRIBUTING.md`.
