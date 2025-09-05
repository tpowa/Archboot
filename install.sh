#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>

if [[ -z "${1}" ]]; then
    echo "Error: No directory given!"
    exit 1
fi
if ! [[ -d "${1}" ]]; then
    echo "Error: Directory does not exist!"
    exit 1
fi
echo "Installing files and symlinks to ${1}"
cp -r etc usr "${1}"/
for i in aarch64 riscv64 x86_64; do
    symlink -s "${1}"/usr/bin/archboot-${i}-create-container.sh ../lib/archboot/run/container.sh
    symlink -s "${1}"/usr/bin/archboot-${i}-create-repository.sh ../lib/archboot/run/repository.sh
    symlink -s "${1}"/usr/bin/archboot-${i}-iso.sh ../lib/archboot/run/iso.sh
    symlink -s "${1}"/usr/bin/archboot-${i}-release.sh ../lib/archboot/run/release.sh
    symlink -s "${1}"/usr/bin/archboot-${i}-server-release.sh ../lib/archboot/run/server-release.sh
done
for i in aarch64 riscv64; do
    symlink -s "${1}"/usr/bin/archboot-${i}-pacman-container-tarball.sh ../lib/archboot/run/container-tarball.sh
done
for i in aarch64 x86_64; do
    symlink -s "${1}"/usr/bin/archboot-${i}-uki.sh ../lib/archboot/run/uki.sh
done
