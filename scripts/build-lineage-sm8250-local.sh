#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${WORKSPACE:-$ROOT_DIR/kernel_workspace}"
CLANG_VERSION="${CLANG_VERSION:-clang-r547379}"
LINEAGE_VERSION="${LINEAGE_VERSION:-lineage-23.2}"
KSU_IMPL="${KSU_IMPL:-backslashxx}"
JOBS="${JOBS:-$(nproc --all)}"

case "$KSU_IMPL" in
  rsuntk|backslashxx) ;;
  *)
    echo "KSU_IMPL must be 'rsuntk' or 'backslashxx'" >&2
    exit 2
    ;;
esac

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

for cmd in git curl tar make zip clang grep sed nproc; do
  need_cmd "$cmd"
done

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

if [ ! -d clang-aosp/bin ]; then
  mkdir -p clang-aosp
  curl -L \
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${CLANG_VERSION}.tar.gz" \
    -o "${CLANG_VERSION}.tar.gz"
  tar -C clang-aosp -zxf "${CLANG_VERSION}.tar.gz"
fi

if [ ! -d android-kernel/.git ]; then
  git clone --recursive https://github.com/LineageOS/android_kernel_oneplus_sm8250 \
    -b "$LINEAGE_VERSION" android-kernel --depth=1
fi

cd "$WORKSPACE/android-kernel"
git reset --hard
git clean -fdx

if [ "$KSU_IMPL" = "rsuntk" ]; then
  curl -LSs https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh | bash -s main
  bash "$ROOT_DIR/patches/kernel-4.19-patch.sh"
  echo "CONFIG_KSU_MANUAL_HOOK=y" >> arch/arm64/configs/vendor/kona-perf_defconfig
  KSU_VERSION="$(cd KernelSU && expr "$(git rev-list --count HEAD)" + 29971)"
else
  curl -LSs https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh | bash -s master
  bash "$ROOT_DIR/patches/kernel-4.19-backslashxx-patch.sh"
  KSU_VERSION="$(grep -oP 'KSU_VERSION\s*=\s*\K\d+' KernelSU/kernel/Makefile | tail -n1)"
fi

grep -q "ksu_handle_execveat" fs/exec.c
grep -q "ksu_handle_faccessat" fs/open.c
grep -q "ksu_handle_stat" fs/stat.c
grep -q "ksu_handle_sys_reboot" kernel/reboot.c
if [ "$KSU_IMPL" = "rsuntk" ]; then
  grep -q "ksu_handle_sys_read" fs/read_write.c
fi

sed -i 's/ -dirty//g' scripts/setlocalversion

export ARCH=arm64
export SUBARCH=arm64
export BRAND_SHOW_FLAG=oneplus
export PATH="$WORKSPACE/clang-aosp/bin:$PATH"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-local}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-$USER}"

BA_CMD="CLANG_TRIPLE=aarch64-linux-gnu-"
EX_CMD="LD=ld.lld LLVM=1"
DEFCONFIG="vendor/kona-perf_defconfig vendor/oplus.config"

make O=out CC=clang $BA_CMD $EX_CMD $DEFCONFIG
grep -E 'CONFIG_KSU|CONFIG_CFI|CONFIG_KPROBES|CONFIG_KALLSYMS' out/.config || true
make -j"$JOBS" O=out CC=clang $BA_CMD $EX_CMD

cd "$WORKSPACE"
rm -rf AnyKernel3
git clone --depth=1 https://github.com/osm0sis/AnyKernel3
sed -i 's/do.devicecheck=1/do.devicecheck=0/g' AnyKernel3/anykernel.sh
sed -i 's!BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!BLOCK=auto;!g' AnyKernel3/anykernel.sh
sed -i 's/IS_SLOT_DEVICE=0;/IS_SLOT_DEVICE=auto;/g' AnyKernel3/anykernel.sh
rm -rf AnyKernel3/.git* AnyKernel3/README.md
cp android-kernel/out/arch/arm64/boot/Image AnyKernel3/

cd AnyKernel3
ZIP_NAME="AK3-${LINEAGE_VERSION}-OPlus-SM8250-${KSU_IMPL}_KSU_${KSU_VERSION}.zip"
zip -r "$ZIP_NAME" ./*

mkdir -p "$ROOT_DIR/artifacts"
cp "$ZIP_NAME" "$ROOT_DIR/artifacts/"
cp "$WORKSPACE/android-kernel/out/arch/arm64/boot/Image" "$ROOT_DIR/artifacts/Image-${KSU_IMPL}"

echo "Built $ROOT_DIR/artifacts/$ZIP_NAME"
