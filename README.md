# EnGenius IPQ807x OpenWrt overlay

OpenWrt support for four EnGenius IPQ807x access points — including the
**ECW336**, a tri-band Wi-Fi 6E AP with no OpenWrt support anywhere else — as a
**patch overlay**, not a fork.

This repository contains **only our own work**: a 50-patch series and the files
it adds. No upstream code is vendored here. `setup.sh` clones a pinned base tree
and applies the series, so what is ours and what is other people's stays
unambiguous.

> Unofficial. Not affiliated with, endorsed by, or supported by EnGenius or
> Senao; those names identify the affected products only. For interoperability
> and self-hosting **on hardware you own**.

## Boards

| SKU | `product_id` | Board | Radios | Uplink | Hardware-tested |
|---|---|---|---|---|---|
| **ECW336** (Wi-Fi 6E) | 291 (`0x0123`) | AP-HK01-C6 | QCN5024 2.4 + QCN5054 5 + **QCN9074 6 GHz on PCIe** | 5 GbE AQR114C | **Yes** |
| EWS377AP v3 | 282 (`0x011a`) | AP-HK07 | QCN5024 + QCN5054 | 2.5 GbE QCA8081 | No |
| ECW230v3 | 284 (`0x011c`) | AP-HK07 | QCN5024 + QCN5054 | 2.5 GbE QCA8081 | No |
| EWS377-FIT | 300 (`0x012c`) | AP-HK07 | QCN5024 + QCN5054 | 2.5 GbE QCA8081 | No |

**Only the ECW336 has been booted.** The three AP-HK07 boards build from the
same tree and share the platform plumbing, but nobody has run them. Treat them
as candidates for testing.

### Downloads

Per-device releases, each carrying its own images, checksums and install notes:

| Board | Release | Status |
|---|---|---|
| ECW336 (Wi-Fi 6E) | [`ecw336-v0.4.0`](https://github.com/ParkWardRR/openwrt-engenius-nss-edma/releases/tag/ecw336-v0.4.0) | hardware-verified |
| EWS377AP v3 | [`ews377ap-v3-v0.4.0`](https://github.com/ParkWardRR/openwrt-engenius-nss-edma/releases/tag/ews377ap-v3-v0.4.0) | **UNTESTED** |
| ECW230v3 | [`ecw230v3-v0.4.0`](https://github.com/ParkWardRR/openwrt-engenius-nss-edma/releases/tag/ecw230v3-v0.4.0) | **UNTESTED** |
| EWS377-FIT | [`ews377-fit-v0.4.0`](https://github.com/ParkWardRR/openwrt-engenius-nss-edma/releases/tag/ews377-fit-v0.4.0) | **UNTESTED** |

Each ships five images. **`…-initramfs-uImage.itb` boots from RAM over u-boot
TFTP and writes nothing to flash** — that is the safe way to try an untested
board. The combined build is
[`v0.4.0-engenius-ipq807x`](https://github.com/ParkWardRR/openwrt-engenius-nss-edma/releases/tag/v0.4.0-engenius-ipq807x).

On the ECW336, verified on hardware: all three radios on the unit's own Senao
calibration, the 5 GbE port passing traffic, A/B boot from either slot, all five
front LEDs, and NSS offload active with ECM acceleration.

## Build

```sh
git clone https://github.com/ParkWardRR/engenius-ap-openwrt.git
cd engenius-ap-openwrt
./setup.sh                 # clones the pinned base, applies the series, wires feeds
cd build-tree
make menuconfig            # qualcommax / ipq807x, then a DEVICE_engenius_* profile
make -j$(nproc)
```

Profiles: `engenius_ecw336`, `engenius_ews377ap-v3`, `engenius_ecw230v3`,
`engenius_ews377-fit`.

The base and feed are pinned in [`BASE`](BASE). The base is OpenWrt main plus
Julius Bairaktaris's NSS/EDMA series on kernel 6.18; NSS runs on top of the
upstream `qca_edma` / `qca_ppe` drivers rather than the out-of-tree
`qca-nss-dp` / `qca-ssdk` ones.

> **After any change that can move a kernel CONFIG symbol, delete the kernel
> build tree.** OpenWrt rebuilds the kernel without rebuilding already-built
> kmods, and a stale out-of-tree kmod does not fail to load — it *corrupts*.
> Selecting `nss-tools` turns on `CONFIG_NET_SCHED`, which inserts `tc_index`
> into `struct sk_buff` and shifts every later field by 4. That surfaced as a
> ~4 GiB DMA map on the first copy-engine RX post and a `wiphy_register` oops
> with `skb->tail = 0xffff0000` — both of which look exactly like NSS bugs and
> are not.

## Installing

**Write the INACTIVE A/B slot and keep a UART adapter attached.** These units
keep `rootfs` at `0x1000000` and `rootfs_1` at `0x87c0000`, selected by the
u-boot env `active_fw`, so a bad image is undone by flipping one variable.

- **The bootloader env is append-only — never erase or rebuild it.** On the
  ECW336 the unit's only real MAC lives in the env (u-boot reports the ART copy
  invalid and falls back to a Qualcomm dummy), so `env default -a` is permanent
  identity loss. A *valid-but-incomplete* env is the one thing that hard-bricks
  these boards.
- **`rootfs` is not an offset — it means "the slot I am running from".** The
  A/B labels are *slot-relative* and swap with `active_fw`: booted from FW1,
  `rootfs` is `0x1000000` and `rootfs_1` is `0x87c0000`; booted from FW2 those
  same two names point the other way round. So `rootfs_1` is always the write
  target and `rootfs` never is — but only if you read `/proc/mtd` **fresh**, on
  the slot you are actually running. A remembered offset, or a capture from
  before a slot switch, writes the live slot. (This is also what the "ECW230v3
  labels are reversed" reports were: check, don't assume.)
- `0:WIFIFW` is **per slot** too (FW1 `0x7ec0000`, FW2 `0xf680000`), so
  restoring a slot to stock means writing both its rootfs *and* its wififw.
- The env is **shared across slots**, which cuts both ways: a stock unit's
  `cloud_id=3` private-cloud routing survived an OpenWrt excursion in the other
  slot and came back for free — and equally, anything you change there persists
  after you roll back.
- Expect **one** failed controller check-in after rolling a slot back to stock:
  the stock overlay does not keep its negotiated controller secret across the
  excursion, so the AP re-negotiates once and then goes steady. The device
  record stays registered and assigned.
- Treat `0:ART` as read-only — it holds factory calibration and the MACs.

## Board identity: trust `compatible`, not the labels

Relevant if you touch the DTS, because every convenient label here is wrong:

- The ECW336's stock DTB sits in the config slot named `hk07` and even carries
  `model = "…IPQ8074/AP-HK07"`, yet its `compatible` is
  `qcom,ipq8074-ap-hk01-c6`. The board is **AP-HK01-C6** — an HK01 host plus a
  Pine-class QCN9074 6 GHz card. `C6` is board revision 6; it has nothing to do
  with 6 GHz, and there is no "6E HK01".
- The stock kernel is a **multi-board blob** carrying ~25 reference DTBs
  (`hk01`…`hk14`, `ac0x`, `oak0x`), and its FIT `configurations/default` points
  at `config@hk08` — matching neither the board nor the DTB that boots. The
  default is a build artifact.
- `machid` is a **slot selector, not a product ID**: an EWS377-FIT reports the
  same `machid=0x8010006` as the ECW336, differing only in `hw_id`. Each
  vendor's firmware writes its own board content into the slot its hardware
  matches.

Read the DTB's `compatible`; ignore the slot name, the `model` string and the
FIT default.

## What the series adds

- Device trees for all four boards, sharing `ipq8072-engenius-ap-hk07.dtsi`
- `Device/` recipes in `image/ipq807x.mk` with each SKU's Senao `product_id`
- `ipq-wifi` board data per SKU (plus a separate QCN9074 blob for the ECW336)
- `leds-ipq-ledc` — a new driver for the IPQ807x LEDC block, which must
  `devm_ioremap()` rather than request the region, since LEDC sits inside a TCSR
  block already owned by `1905000.hwlock`
- Board registrations that otherwise **fail silently**: `11-ath11k-caldata`
  (`0:art` offsets `0x1000` for the internal pair, `0x26800` for the QCN9074),
  `board.d/02_network`, and the `platform.sh` sysupgrade case, which resolves
  `CI_UBIPART` from the running slot so sysupgrade works from either slot
- `nss-tools`: symlink `qca-nss{0,1}.bin` → `…-retail.bin`, since `qca-nss-drv`
  hardcodes the names it requests while `nss-firmware` installs the retail ones
- `mac80211`: do not autoload the ath11k **bus** drivers on an NSS build, so
  `nss.init` can arm the plane before the radios bind
- `wifi-scripts`: never inherit `country '00'` from another radio — one 6 GHz
  radio otherwise stopped a tri-band board from bringing up *any* BSS
- `ath11k`: make the `nss` members unconditional so the tree also builds with
  `CONFIG_ATH11K_NSS_SUPPORT` off

## Related repositories

- [ECW336-firmware-tools](https://github.com/ParkWardRR/ECW336-firmware-tools) —
  stock-firmware analysis, the no-brick flash procedure, bring-up runbooks
- [engenius-field-guide](https://github.com/ParkWardRR/engenius-field-guide) —
  Senao/EnGenius firmware format, model codes, cross-flashing, self-hosting
- [pelegrun](https://github.com/ParkWardRR/pelegrun-engenius-ews377-ecw230-firmware-tools) —
  no-brick cross-flash and recovery toolkit for the AP-HK07 SKUs; it also reads
  ECW336 images and envs, and refuses a re-head that would move an image across
  the board boundary described above
- [openwrt-engenius-nss-edma](https://github.com/ParkWardRR/openwrt-engenius-nss-edma) —
  the full build tree these patches came from, and where prebuilt images are
  published

## Acknowledgements

This overlay is only the EnGenius part. It stands on other people's work:

- [Julius Bairaktaris](https://github.com/JuliusBairaktaris) — the
  `openwrt-nss-edma` tree this applies onto and the `nss-packages` feed it
  builds against.
- [Christian Marangi (Ansuel)](https://github.com/Ansuel) — the upstream EDMA
  and PPE drivers.
- [Robert Marko (robimarko)](https://github.com/robimarko) — maintaining the
  OpenWrt qualcommax target.
- [qosmio](https://github.com/qosmio/openwrt-ipq) — the NSS packaging and
  firmware tarballs the feed builds on.
- Qualcomm and CodeLinaro — the open-source NSS host components.

## License

GPL-2.0, see [LICENSE](LICENSE) — these patches are a derivative of OpenWrt and
of the base tree above, and carry the same terms. The NSS components and the
base tree keep their own upstream licenses.
