#!/usr/bin/env bash
# Native toolchain on GitHub-hosted Ubuntu (x64 or arm64). Skips apt/llvm/cmake
# steps when the runner (or a prior layer) already satisfies Bun's needs.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

dpkg_ok() {
  dpkg -s "$1" &>/dev/null
}

apt_missing=()
apt_need() {
  dpkg_ok "$1" || apt_missing+=("$1")
}

# Core build deps (many are preinstalled on ubuntu-* GitHub images).
for p in \
  wget curl git python3 python3-pip ninja-build \
  software-properties-common apt-transport-https \
  ca-certificates gnupg lsb-release unzip \
  libxml2-dev ruby ruby-dev bison gawk perl make golang-go ccache \
  build-essential; do
  apt_need "$p"
done

for p in \
  gcc-13 g++-13 libgcc-13-dev libstdc++-13-dev \
  libatomic1 libc6-dev libgfortran5; do
  apt_need "$p"
done

if ((${#apt_missing[@]})); then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${apt_missing[@]}"
fi

have_llvm21() {
  [[ -d /usr/lib/llvm-21/bin ]] && [[ -x /usr/lib/llvm-21/bin/clang-21 ]]
}

if ! have_llvm21; then
  wget -q https://apt.llvm.org/llvm.sh
  chmod +x llvm.sh
  sudo -E ./llvm.sh 21 all
  rm -f llvm.sh
fi

cmake_version_ge() {
  local need="$1" have
  command -v cmake >/dev/null || return 1
  have=$(cmake --version | sed -n '1s/.* \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
  [[ -n "$have" ]] || return 1
  # True if have >= need: the lexicographic minimum under sort -V must be need.
  [[ $(printf '%s\n' "$need" "$have" | sort -V | head -n1) == "$need" ]]
}

ARCH="$(uname -m)"
CMAKE_VER="3.30.5"
if ! cmake_version_ge "3.30.0"; then
  if [ "$ARCH" = "aarch64" ]; then
    CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-aarch64.sh"
    CMAKE_SH_NAME="cmake-${CMAKE_VER}-linux-aarch64.sh"
  else
    CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-x86_64.sh"
    CMAKE_SH_NAME="cmake-${CMAKE_VER}-linux-x86_64.sh"
  fi
  # Optional: GitHub Actions caches this directory between runs (see build-linux-gnu.yml).
  if [[ -n "${BUN_GHA_CMAKE_CACHE_DIR:-}" ]]; then
    mkdir -p "$BUN_GHA_CMAKE_CACHE_DIR"
    CMAKE_SH="${BUN_GHA_CMAKE_CACHE_DIR}/${CMAKE_SH_NAME}"
    if [[ ! -f "$CMAKE_SH" ]]; then
      wget -q -O "$CMAKE_SH" "$CMAKE_URL"
    fi
    sudo sh "$CMAKE_SH" --skip-license --prefix=/usr
  else
    wget -q -O /tmp/cmake.sh "$CMAKE_URL"
    sudo sh /tmp/cmake.sh --skip-license --prefix=/usr
    rm -f /tmp/cmake.sh
  fi
fi

if [[ -x /usr/bin/gcc-13 ]]; then
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 130 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-13 \
    --slave /usr/bin/gcc-ar gcc-ar /usr/bin/gcc-ar-13 \
    --slave /usr/bin/gcc-nm gcc-nm /usr/bin/gcc-nm-13 \
    --slave /usr/bin/gcc-ranlib gcc-ranlib /usr/bin/gcc-ranlib-13
fi

if [ "$ARCH" = "aarch64" ]; then
  ARCH_PATH="aarch64-linux-gnu"
else
  ARCH_PATH="x86_64-linux-gnu"
fi

sudo mkdir -p "/usr/lib/gcc/${ARCH_PATH}/13"
if [ -e "/usr/lib/${ARCH_PATH}/libstdc++.so.6" ]; then
  sudo ln -sf "/usr/lib/${ARCH_PATH}/libstdc++.so.6" "/usr/lib/gcc/${ARCH_PATH}/13/"
fi
echo "/usr/lib/gcc/${ARCH_PATH}/13" | sudo tee /etc/ld.so.conf.d/gcc-13.conf >/dev/null
echo "/usr/lib/${ARCH_PATH}" | sudo tee -a /etc/ld.so.conf.d/gcc-13.conf >/dev/null
sudo ldconfig

LLVM_V=21
shopt -s nullglob
for f in /usr/lib/llvm-${LLVM_V}/bin/*; do
  sudo ln -sf "$f" /usr/bin/
done
shopt -u nullglob
sudo ln -sf "/usr/bin/clang-${LLVM_V}" /usr/bin/clang
sudo ln -sf "/usr/bin/clang++-${LLVM_V}" /usr/bin/clang++
sudo ln -sf "/usr/bin/lld-${LLVM_V}" /usr/bin/lld
sudo ln -sf "/usr/bin/ld.lld" /usr/bin/ld
sudo ln -sf /usr/bin/clang /usr/bin/cc
sudo ln -sf /usr/bin/clang++ /usr/bin/c++

echo "CC=clang" >> "${GITHUB_ENV}"
echo "CXX=clang++" >> "${GITHUB_ENV}"
echo "AR=llvm-ar-${LLVM_V}" >> "${GITHUB_ENV}"
echo "RANLIB=llvm-ranlib-${LLVM_V}" >> "${GITHUB_ENV}"
