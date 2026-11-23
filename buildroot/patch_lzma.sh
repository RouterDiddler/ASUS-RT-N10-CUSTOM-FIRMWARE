#!/usr/bin/env bash
# Eski U-Boot (1.1.3, 2011) LZMA decoder'ı ile uyumluluk için:
#   1) Dictionary boyutunu 64 KiB'a sabitler (büyük dictionary'yi kaldıramıyor)
#   2) LZMA-alone header'ındaki "uncompressed size" alanını gerçek boyutla
#      doldurur (modern xz bunu 0xFF ile "bilinmiyor" bırakıyor, eski
#      decoder bunu işleyemiyor)
#
# Buildroot kök dizininde çalıştır:
#   ./patch_lzma.sh
#
# Önce "make" ile host araçlarının (host-xz dahil) en az bir kere
# derlenmiş/kurulmuş olması gerekir, aksi halde output/host/bin/lzma
# henüz mevcut olmaz.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

LZMA_BIN="output/host/bin/lzma"

if [[ ! -d output/host/bin ]]; then
    echo "HATA: output/host/bin yok. Önce en az bir kere 'make' çalıştırıp"
    echo "host araçlarının kurulmasını bekle, sonra bu scripti tekrar çalıştır."
    exit 1
fi

if [[ ! -f "$LZMA_BIN" ]]; then
    echo "UYARI: $LZMA_BIN henüz yok. Host-xz paketi henüz derlenmemiş olabilir."
    echo "Çözüm: önce 'make host-xz' çalıştır, sonra bu scripti tekrar dene."
    exit 1
fi

if [[ ! -f "${LZMA_BIN}.orig" ]]; then
    echo "==> Orijinal lzma yedekleniyor..."
    cp "$LZMA_BIN" "${LZMA_BIN}.orig"
else
    echo "==> Yedek zaten var (${LZMA_BIN}.orig), üzerine yazılmıyor."
fi

echo "==> Wrapper yazılıyor: $LZMA_BIN"
cat > "$LZMA_BIN" <<'WRAPEOF'
#!/usr/bin/env bash
# Eski U-Boot uyumlu LZMA wrapper.
# Kernel/rootfs build sistemi bunu iki şekilde çağırabilir:
#   cat dosya | lzma -9 > çıktı        (stdin'den)
#   lzma -9 -c dosya > çıktı           (dosya argümanıyla)
set -euo pipefail

files=()
for a in "$@"; do
    case "$a" in
        -*) ;;
        *)  files+=("$a") ;;
    esac
done

if [[ ${#files[@]} -gt 0 ]]; then
    infile="${files[0]}"
    tmp_created=0
else
    infile="$(mktemp)"
    cat > "$infile"
    tmp_created=1
fi

xz --format=lzma --lzma1=preset=9e,dict=65536 -c "$infile" > "${infile}.xz_out"

python3 - "$infile" "${infile}.xz_out" <<'PYEOF'
import sys, os
infile, xzfile = sys.argv[1], sys.argv[2]
size = os.path.getsize(infile)
data = bytearray(open(xzfile, "rb").read())
data[5:13] = size.to_bytes(8, "little")
sys.stdout.buffer.write(data)
PYEOF

rm -f "${infile}.xz_out"
if [[ $tmp_created -eq 1 ]]; then
    rm -f "$infile"
fi
WRAPEOF

chmod +x "$LZMA_BIN"

echo "==> Tamamlandı. Şimdi temiz yeniden derleme yap:"
echo "    rm -f output/build/linux-*/arch/mips/boot/vmlinux.bin.lzma \\"
echo "          output/build/linux-*/arch/mips/boot/uImage.lzma \\"
echo "          output/images/uImage output/images/rootfs.cpio.lzma"
echo "    make linux-rebuild"
echo "    mkimage -l output/images/uImage"
