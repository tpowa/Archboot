#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
_dir="../lib/archboot/run"
_comp_dir="${1}/usr/share/bash-completion/completions"
_dest="${1}/usr/bin"
_completion=(
    archboot-{aarch,riscv,x86_}64-create-container.sh
    archboot-{aarch,riscv,x86_}64-iso.sh
    archboot-{aarch,x86_}64-uki.sh
)

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
    ln -s "${_dir}"/container.sh "${_dest}"/archboot-${i}-create-container.sh
    ln -s "${_dir}"/repository.sh "${_dest}"/archboot-${i}-create-repository.sh
    ln -s "${_dir}"/iso.sh "${_dest}"/archboot-${i}-iso.sh
    ln -s "${_dir}"/release.sh "${_dest}"/archboot-${i}-release.sh
    ln -s "${_dir}"/server-release.sh "${_dest}"/archboot-${i}-server-release.sh
done
for i in aarch64 riscv64; do
    ln -s "${_dir}"/container-tarball.sh "${_dest}"/archboot-${i}-pacman-container-tarball.sh
done
for i in aarch64 x86_64; do
    ln -s "${_dir}"/uki.sh "${_dest}"/archboot-${i}-uki.sh
done
mkdir -p "${_comp_dir}"
for i in ${_completion[@]}; do
    ln -s ${i} "${_comp_dir}/${i}"
done
