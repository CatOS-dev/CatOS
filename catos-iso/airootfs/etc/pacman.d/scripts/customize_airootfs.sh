#!/usr/bin/env bash

## Script to perform several important tasks before `mkarchcraftiso` create filesystem image.

set -e -u

## 增加catos源
# echo '[catos]' >> /etc/pacman.conf
# echo 'SigLevel = Never' >> /etc/pacman.conf
# echo 'Server = https://pkgs.catos.info/$arch' >> /etc/pacman.conf

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Remove stale SDDM configuration left by older catos-kde-settings packages.
rm -rf /etc/sddm.conf /etc/sddm.conf.d

##grub
#echo 'GRUB_THEME="/usr/share/grub/themes/vimix-color-1080p/theme.txt"' >> /etc/default/grub
echo 'GRUB_THEME="/usr/share/grub/themes/catos-grub-theme-dark-1080p/theme.txt"' >> /etc/default/grub

echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub




