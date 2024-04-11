#!/bin/bash
rsync --delete --delete-before -L -a archboot.com:release ~/public_html/
rsync --delete --delete-before -L -a archboot.com:pkg ~/public_html/
for i in aarch64 riscv64 x86_64; do
    cd ~/public_html/release/${i}/
    _DIR="$(ls -1rvd */ | head -n1)"
    ln -s "${_DIR}" latest
done
