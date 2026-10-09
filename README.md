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
