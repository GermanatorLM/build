# Armbian für Banana Pi BPI-R4 Pro 8X

Dieses Repository ist ein Entwicklungs-Fork des Armbian Build Frameworks für
den **Banana Pi BPI-R4 Pro 8X (MT7988A, 8 GiB DDR4)**.

Der aktuelle Entwicklungsbranch ist:

```text
bpi-r4pro-8x
```

> **Bring-up-Status:** Der Port ist strukturell angelegt und um ein gepinntes
> Firmware-Bundle, statische Checks und eine Hardware-Bring-up-Checkliste
> ergänzt. Ein erfolgreicher vollständiger Image-Build oder Hardware-Boot ist
> damit noch nicht behauptet. Jede erreichte Stufe wird hier nachgetragen.

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
| Kernel | Frank Wunderlich `BPI-Router-Linux`, `6.18-main` | integriert, Build ausstehend |
| Linux DTB | `mt7988a-bananapi-bpi-r4-pro-8x.dtb` | integriert |
| SD DTBO | `mt7988a-bananapi-bpi-r4-pro-sd.dtbo` | integriert |
| U-Boot | Armbian Filogic-Basis + minimaler R4-Pro-SD-Target | integriert, Build ausstehend |
| Bootformat | extlinux | integriert |
| Firmware | `pinned` / `latest` / `ref`, 9 PHY/Wi-Fi-Payloadpfade + MT7988-WED-Blobs | integriert |
| Automatischer Check | `tools/bpi-r4pro8x-check.sh` | vorhanden |
| Hardwaretest | UART/SD/Netzwerk/PCIe/Wi-Fi | noch offen |

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
| 22 | `SELF` | README um Firmware-Build-Flags erweitert und Chronik bis zum aktuellen Stand fortgeführt | `README.md` | dokumentiert |

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

## Nächster Meilenstein

Der nächste sinnvolle Stand ist:

```text
STATIC PASS
  -> vollständiger Trixie-Minimal-Build
  -> SD-Image
  -> UART-Log
  -> BL2
  -> U-Boot
  -> extlinux
  -> Linux 6.18
  -> Login
```

Erst danach werden Netzwerk, NVMe und Wi-Fi einzeln als Hardware-Meilensteine
abgearbeitet.

---

## Upstream Armbian

Dieses Repository basiert auf dem
[Armbian Build Framework](https://github.com/armbian/build). Die allgemeine
Armbian-Dokumentation befindet sich unter
[docs.armbian.com](https://docs.armbian.com/Developer-Guide_Overview/).

Für Änderungen, die nicht spezifisch zum BPI-R4 Pro 8X gehören, gelten weiterhin
die Upstream-Armbian-Konventionen und `CONTRIBUTING.md`.
