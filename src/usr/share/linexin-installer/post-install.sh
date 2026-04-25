#!/bin/bash
set -e

echo "=============================================="
echo "    ArqOS Post-Installation Cleanup"
echo "=============================================="

echo "[1/9] Removing live ISO sudo configuration..."
rm -f /etc/sudoers.d/g_wheel

echo "[2/9] Removing archiso mkinitcpio configuration..."
rm -f /etc/mkinitcpio.conf.d/archiso.conf

echo "[3/9] Fixing linux.preset..."
# To jest KLUCZOWE - napraw preset ZANIM uruchomisz mkinitcpio
cat > /etc/mkinitcpio.d/linux.preset << 'EOF'
# mkinitcpio preset file for the 'linux' package

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default' 'fallback')

default_image="/boot/initramfs-linux.img"

fallback_image="/boot/initramfs-linux-fallback.img"
fallback_options="-S autodetect"
EOF

echo "linux.preset fixed"

echo "[4/9] Removing live ISO systemd services..."
rm -f /etc/systemd/system/etc-pacman.d-gnupg.mount
rm -rf /etc/systemd/system/getty@tty1.service.d
rm -rf /etc/systemd/system/multi-user.target.wants/pacman-init.service
rm -rf /etc/systemd/system/pacman-init.service

echo "[5/9] Removing autologin configuration..."
rm -f /etc/gdm/custom.conf
rm -f /etc/sddm.conf.d/autologin.conf

echo "[6/9] Removing live ISO polkit rules..."
rm -f /etc/polkit-1/rules.d/49-nopasswd_global.rules
rm -f /etc/polkit-1/rules.d/49-nopasswd-calamares.rules
rm -f /etc/polkit-1/rules.d/49-nopasswd-linexin.rules

echo "[7/9] Removing live ISO motd..."
rm -f /etc/motd

echo "[8/9] Cleaning live ISO user files..."
rm -f /root/.zlogin
rm -f /root/.automated_script.sh

echo "[9/9] Enabling essential services..."
# NetworkManager
if systemctl list-unit-files | grep -q NetworkManager.service; then
    systemctl enable NetworkManager
    echo "NetworkManager enabled"
fi

# Display Manager (sprawdź który jest zainstalowany)
if systemctl list-unit-files | grep -q gdm.service; then
    systemctl enable gdm
    echo "GDM enabled"
elif systemctl list-unit-files | grep -q sddm.service; then
    systemctl enable sddm
    echo "SDDM enabled"
elif systemctl list-unit-files | grep -q lightdm.service; then
    systemctl enable lightdm
    echo "LightDM enabled"
fi

# Bluetooth (jeśli zainstalowany)
if systemctl list-unit-files | grep -q bluetooth.service; then
    systemctl enable bluetooth
    echo "Bluetooth enabled"
fi

echo "=============================================="
echo "    Post-installation cleanup complete!"
echo "=============================================="

exit 0
