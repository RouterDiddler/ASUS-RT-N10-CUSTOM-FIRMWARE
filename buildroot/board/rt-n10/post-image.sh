#!/bin/bash
# RT-N10 B1 (RT3350) - images for the old U-Boot 1.1.3
#
# Produces in $BINARIES_DIR:
#   uImage-uboot  RAM test image: kernel + embedded initramfs, for
#                   tftpboot <addr> uImage; bootm <addr>
#   uImage-flash  kernel without initramfs, root=/dev/mtdblock4 (squashfs)
#   firmware.bin  kernel + rootfs area (0x050000-0x3effff): uImage-flash
#                 padded to the "kernel" partition, rootfs.squashfs padded to
#                 the "rootfs" partition. This is what would go to flash at
#                 0x50000. The settings blocks cfg-a (0x030000) and cfg-b
#                 (0x3f0000) are outside it, writing it keeps the settings.
#                 (this script never writes to flash)
#
# Every uImage is LZMA-alone compressed with a small dictionary and the real
# uncompressed size in the header, because the 2011 U-Boot LZMA decoder
# cannot handle "size unknown" streams or large dictionaries on 32 MB RAM.
#
# Usage:
#   Buildroot post-image script: BR2_ROOTFS_POST_IMAGE_SCRIPT="board/rt-n10/post-image.sh"
#   by hand, from the Buildroot top dir: LC_ALL=C ./board/rt-n10/post-image.sh output/images
#
# Environment knobs:
#   LZMA_DICT   dictionary size (default 65536, verified on this U-Boot)
#   TFTP_DIR    copy uImage-uboot there as "uImage" if writable (default /srv/tftp, empty = off)
#   NO_FLASH=1  skip the flash kernel / firmware.bin

set -euo pipefail
export LC_ALL=C

LZMA_DICT="${LZMA_DICT:-65536}"
TFTP_DIR="${TFTP_DIR-/srv/tftp}"

# flash layout, must match arch/mips/boot/dts/ralink/rt3350_asus_rt-n10-b1.dts
FW_OFFSET=$((0x50000))		# U-Boot boots 0xbfc50000
FW_SIZE=$((0x3a0000))		# 0x050000 - 0x3f0000 (cfg-b is the last block)
KERNEL_PART_SIZE=$((0x220000))	# mtd3 "kernel" at 0x050000
ROOTFS_PART_SIZE=$((0x180000))	# mtd4 "rootfs" at 0x270000
ERASE_BLOCK=$((0x10000))

BINARIES_DIR="${BINARIES_DIR:-${1:-output/images}}"
BASE_DIR="${BASE_DIR:-$(cd "$BINARIES_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$BASE_DIR/build}"
HOST_DIR="${HOST_DIR:-$BASE_DIR/host}"

pick() { if [ -x "$HOST_DIR/bin/$1" ]; then echo "$HOST_DIR/bin/$1"; else command -v "$1"; fi; }
XZ="${XZ:-$(pick xz)}"
MKIMAGE="${MKIMAGE:-$(pick mkimage)}"
NM="${NM:-$(ls "$HOST_DIR"/bin/*-linux-*-nm 2>/dev/null | head -n1)}"
for t in "$XZ" "$MKIMAGE" "$(command -v python3)"; do
	[ -x "$t" ] || { echo "HATA: gerekli araç bulunamadı: $t" >&2; exit 1; }
done

LINUX_DIR="$(ls -td "$BUILD_DIR"/linux-[0-9]* 2>/dev/null | grep -vE 'headers|-flash$' | head -n1 || true)"
ORIG_UIMAGE="$BINARIES_DIR/uImage"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$LINUX_DIR/arch/mips/boot/vmlinux.bin" ] || { echo "HATA: $LINUX_DIR/arch/mips/boot/vmlinux.bin yok" >&2; exit 1; }
[ -f "$ORIG_UIMAGE" ] || { echo "HATA: $ORIG_UIMAGE yok (adres bilgisi buradan okunuyor)" >&2; exit 1; }

# Load/Entry/name from the uImage built by the kernel (big-endian header)
read -r LOAD ENTRY NAME < <(python3 -I - "$ORIG_UIMAGE" <<'EOF'
import struct, sys
h = open(sys.argv[1], "rb").read(64)
magic, _, _, _, load, ep = struct.unpack(">6I", h[:24])
if magic != 0x27051956:
    sys.exit("HATA: geçerli bir uImage değil (magic yanlış)")
name = h[32:64].split(b"\x00")[0].decode(errors="replace") or "Linux"
print(f"0x{load:08x} 0x{ep:08x} {name}")
EOF
)

# make_uimage <vmlinux.bin> <vmlinux ELF> <output> <label>
make_uimage() {
	local raw="$1" elf="$2" out="$3" label="$4" entry
	# the flash kernel has a different entry point: read it from its ELF
	entry=$(python3 -I - "$elf" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read(64)
assert d[:4] == b"\x7fELF" and d[5] == 1, "little-endian ELF expected"
print(f"0x{struct.unpack('<I', d[24:28])[0]:08x}")
EOF
)
	echo ">>> [$label] kernel: $raw"
	echo ">>> [$label] Load=$LOAD Entry=$entry Name=$NAME dict=$LZMA_DICT"

	"$XZ" --format=lzma --lzma1=preset=9,dict="$LZMA_DICT" -T1 -c "$raw" > "$WORK/k.lzma"
	python3 -I - "$raw" "$WORK/k.lzma" <<'EOF'
import os, sys
size = os.path.getsize(sys.argv[1])
d = bytearray(open(sys.argv[2], "rb").read())
d[5:13] = size.to_bytes(8, "little")
open(sys.argv[2], "wb").write(d)
EOF
	"$MKIMAGE" -A mips -O linux -T kernel -C lzma -a "$LOAD" -e "$entry" -n "$NAME" \
		-d "$WORK/k.lzma" "$out" >/dev/null

	# BSS is not in vmlinux.bin but is cleared after decompression: use _end
	local bss_end
	bss_end=$("$NM" "$elf" 2>/dev/null | sed -n 's/^\([0-9a-f]*\) [Bb] _end$/\1/p')
	python3 -I - "$out" "$LZMA_DICT" "$raw" "$LOAD" "$label" "${bss_end:-0}" <<'EOF'
import os, struct, sys
out, want_dict, raw, load, label = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4], 16), sys.argv[5]
bss_end = int(sys.argv[6], 16)
d = open(out, "rb").read(64 + 13)
dict_sz = struct.unpack("<I", d[65:69])[0]
unc = struct.unpack("<Q", d[69:77])[0]
ok = True
if dict_sz != want_dict:
    print(f"HATA: dictionary {dict_sz}, beklenen {want_dict}"); ok = False
if unc == 0xFFFFFFFFFFFFFFFF:
    print("HATA: boyut alanı hâlâ FFFF... (bilinmiyor)"); ok = False
elif unc != os.path.getsize(raw):
    print(f"HATA: boyut alanı {unc}, beklenen {os.path.getsize(raw)}"); ok = False
if not ok:
    sys.exit(1)
img = os.path.getsize(out)
end = max(load + unc, bss_end)
print(f">>> [{label}] Doğrulama OK: dict={dict_sz}, açılmış={unc} bayt, uImage={img} bayt ({img/1048576:.2f} MB)")
print(f">>> [{label}] Kernel RAM'de 0x{load:08x} - 0x{end:08x} arasına açılacak (BSS dahil).")
safe = (end + 0x100000 + 0xFFFFF) & ~0xFFFFF	# >= 1 MB margin above the kernel
print(f">>> [{label}] Güvenli tftpboot adresi: 0x{max(safe, 0x80A00000):08x} veya üstü (32 MB RAM sınırı 0x82000000)")
EOF
}

# ---- 1) RAM test image (kernel + initramfs) ----
make_uimage "$LINUX_DIR/arch/mips/boot/vmlinux.bin" "$LINUX_DIR/vmlinux" \
	"$BINARIES_DIR/uImage-uboot" "RAM"

if [ -n "$TFTP_DIR" ] && [ -d "$TFTP_DIR" ] && [ -w "$TFTP_DIR" ]; then
	cp "$BINARIES_DIR/uImage-uboot" "$TFTP_DIR/uImage"
	chmod 644 "$TFTP_DIR/uImage"
	echo ">>> $TFTP_DIR/uImage güncellendi"
elif [ -n "$TFTP_DIR" ]; then
	echo ">>> Not: $TFTP_DIR yazılabilir değil, kopyalama atlandı. Elle: sudo cp $BINARIES_DIR/uImage-uboot $TFTP_DIR/uImage"
fi

[ "${NO_FLASH:-0}" = 1 ] && { echo ">>> NO_FLASH=1, flash imajı atlandı"; exit 0; }

# ---- 2) flash kernel: same tree and config, but no embedded initramfs,
#         writable settings blocks (cfg-a/cfg-b), kernel and rootfs ----
FLASH_DIR="$LINUX_DIR-flash"
CROSS="$(ls "$HOST_DIR"/bin/*-linux-*-gcc 2>/dev/null | grep -v 'br_real' | head -n1)"
CROSS="${CROSS%gcc}"
[ -n "$CROSS" ] || { echo "HATA: cross derleyici bulunamadı" >&2; exit 1; }
SQUASHFS="$BINARIES_DIR/rootfs.squashfs"
[ -f "$SQUASHFS" ] || { echo "HATA: $SQUASHFS yok (BR2_TARGET_ROOTFS_SQUASHFS)" >&2; exit 1; }

echo ">>> [FLASH] kernel derleniyor: $FLASH_DIR"
rsync -a --delete "$LINUX_DIR/" "$FLASH_DIR/"
"$FLASH_DIR/scripts/config" --file "$FLASH_DIR/.config" --set-str INITRAMFS_SOURCE ""
FLASH_DTS="$FLASH_DIR/arch/mips/boot/dts/ralink/rt3350_asus_rt-n10-b1.dts"
# the partition table in the DTS must match the sizes above
python3 -I - "$FLASH_DTS" "$FW_OFFSET" "$KERNEL_PART_SIZE" "$ROOTFS_PART_SIZE" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
fw, k, r = (int(x) for x in sys.argv[2:5])
want = {"cfg-a": (0x30000, 0x10000), "factory": (0x40000, 0x10000), "kernel": (fw, k),
        "rootfs": (fw + k, r), "cfg-b": (fw + k + r, 0x10000)}
found = {m[0]: (int(m[1], 16), int(m[2], 16))
         for m in re.findall(r'label = "([^"]+)";\s*reg = <(0x[0-9a-f]+) (0x[0-9a-f]+)>', s)}
bad = [f"{n}: DTS {found.get(n)}, beklenen {w}" for n, w in want.items() if found.get(n) != w]
if fw + k + r + 0x10000 != 0x400000:
    bad.append("kernel+rootfs+cfg-b flash sonuna (0x400000) denk gelmiyor")
if bad:
    sys.exit("HATA: DTS bölüm tablosu post-image.sh ile uyuşmuyor:\n  " + "\n  ".join(bad))
EOF
# flash kernel: settings blocks (rtn10-cfg) and kernel/rootfs (rtn10-upgrade) are writable
for m in rtn10-cfg-ro rtn10-fw-ro; do
	[ "$(grep -c "$m" "$FLASH_DTS")" -eq 2 ] || { echo "HATA: DTS'te iki $m işareti olmalı" >&2; exit 1; }
done
sed -i -e '/rtn10-cfg-ro/d' -e '/rtn10-fw-ro/d' "$FLASH_DTS"
KMAKE=(make -C "$FLASH_DIR" -j"$(nproc)" ARCH=mips CROSS_COMPILE="$CROSS" BR_BINARIES_DIR="$BINARIES_DIR")
"${KMAKE[@]}" olddefconfig >/dev/null
grep -q '^CONFIG_INITRAMFS_SOURCE=""' "$FLASH_DIR/.config" || { echo "HATA: flash kernel config'inde initramfs kaldı" >&2; exit 1; }
"${KMAKE[@]}" vmlinux.bin >/dev/null

make_uimage "$FLASH_DIR/arch/mips/boot/vmlinux.bin" "$FLASH_DIR/vmlinux" \
	"$BINARIES_DIR/uImage-flash" "FLASH"

# ---- 3) firmware.bin = kernel | squashfs, each padded ----
python3 -I - "$BINARIES_DIR/uImage-flash" "$SQUASHFS" "$BINARIES_DIR/firmware.bin" \
	"$KERNEL_PART_SIZE" "$ROOTFS_PART_SIZE" "$FW_SIZE" "$ERASE_BLOCK" "$FW_OFFSET" <<'EOF'
import hashlib, sys
kpath, rpath, out = sys.argv[1:4]
kpart, rpart, fwsize, eb, fwoff = (int(x) for x in sys.argv[4:9])
if kpart + rpart != fwsize:
    sys.exit(f"HATA: bölümler firmware alanını tam kaplamıyor ({kpart}+{rpart} != {fwsize})")
k = open(kpath, "rb").read()
r = open(rpath, "rb").read()
if k[:4] != b"\x27\x05\x19\x56":
    sys.exit("HATA: kernel uImage değil")
if r[:4] != b"hsqs":
    sys.exit("HATA: rootfs squashfs değil (magic 'hsqs' yok)")
if len(k) > kpart:
    sys.exit(f"HATA: kernel {len(k)} bayt, kernel bölümü {kpart} bayt — sığmıyor")
if len(r) > rpart:
    sys.exit(f"HATA: rootfs {len(r)} bayt, rootfs bölümü {rpart} bayt — sığmıyor")
img = k + b"\xff" * (kpart - len(k)) + r + b"\xff" * (rpart - len(r))
assert len(img) == fwsize
open(out, "wb").write(img)
print(f">>> [FLASH] kernel : {len(k):>8} / {kpart} bayt (%{100*len(k)/kpart:.0f}), boş {kpart-len(k)}")
print(f">>> [FLASH] rootfs : {len(r):>8} / {rpart} bayt (%{100*len(r)/rpart:.0f}), boş {rpart-len(r)}")
print(f">>> [FLASH] firmware.bin: {len(img)} bayt (0x{len(img):x}), flash 0x{fwoff:06x}-0x{fwoff+len(img)-1:06x}"
      f" (firmware alanı 0x{fwoff:06x}-0x{fwoff+fwsize-1:06x})")
print(f">>> [FLASH] ayarlar: cfg-a 0x030000, cfg-b 0x{fwoff+fwsize:06x} (firmware.bin dışında, korunur)")
print(f">>> [FLASH] rootfs flash offset 0x{fwoff+kpart:06x}, md5 {hashlib.md5(img).hexdigest()}")
EOF
echo ">>> Hazır: $BINARIES_DIR/uImage-uboot (RAM testi), $BINARIES_DIR/uImage-flash, $BINARIES_DIR/firmware.bin"
echo ">>> NOT: bu script flash'a hiçbir şey yazmaz."
