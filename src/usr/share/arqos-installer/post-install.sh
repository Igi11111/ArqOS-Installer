#!/bin/bash
set -e

# ===== NAJPIERW ZDEFINIUJ FUNKCJE POMOCNICZE =====
print_msg() {
    echo "[INFO] $1"
}



# ===== ZMIENNE =====
DE_SELECTION_FILE="/de_selection"
FLATPAK_FILE="/install_flatpaks"
UPDATES_FILE="/install_updates"

# ===== FUNKCJA SPRAWDZAJĄCA DE =====
check_de_selection() {
    echo "=============================================="
    echo "    Checking Desktop Environment selection"
    echo "=============================================="

    if [[ ! -f "$DE_SELECTION_FILE" ]]; then
        print_msg "DE selection file not found at $DE_SELECTION_FILE"
        echo "Available files in root:"
        ls -la / | grep -E "de_selection|install_|selection" || echo "No selection files found"
        return 2
    fi

    local de_value
    de_value=$(cat "$DE_SELECTION_FILE" 2>/dev/null | tr -d '[:space:]')

    print_msg "Read DE selection value: '$de_value'"

    if [[ "$de_value" == "0" ]]; then
        print_msg "Installing GNOME desktop environment..."
        # pacman -Sy gnome --noconfirm --overwrite '*'

        # Usuń KDE jeśli jest zainstalowane
        if pacman -Qi plasma-desktop &>/dev/null; then
            print_msg "Removing KDE Plasma..."
            pacman -Rsc plasma-desktop --noconfirm || true
        fi

        print_msg "GNOME installation complete"
        return 0

    elif [[ "$de_value" == "1" ]]; then
        print_msg "KDE Plasma selected (already installed)"

        # Usuń GNOME jeśli jest zainstalowane
        if pacman -Qi gnome &>/dev/null; then
            print_msg "Removing GNOME..."
            pacman -Rsc gnome --noconfirm || true
        fi

        print_msg "KDE Plasma configuration complete"
        return 0

    else
        print_msg "Invalid DE selection value: '$de_value' (expected 0 or 1)"
        return 2
    fi
}

# ===== GŁÓWNY SKRYPT =====
echo "=============================================="
echo "    ArqOS Post-Installation Cleanup"
echo "=============================================="

echo "[1/9] Removing live ISO sudo configuration..."
rm -f /etc/sudoers.d/g_wheel

echo "[2/9] Removing archiso mkinitcpio configuration..."
rm -f /etc/mkinitcpio.conf.d/archiso.conf

echo "[3/9] Fixing linux.preset..."
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

# Display Manager
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

# Bluetooth
if systemctl list-unit-files | grep -q bluetooth.service; then
    systemctl enable bluetooth
    echo "Bluetooth enabled"
fi

echo "=============================================="
echo "    Essential services configuration complete"
echo "=============================================="

# ===== WYWOŁANIE FUNKCJI WYBORU DE =====
check_de_selection

# Wyczyść pliki konfiguracyjne
print_msg "Cleaning up configuration files..."
rm -f "$DE_SELECTION_FILE" "$FLATPAK_FILE" "$UPDATES_FILE"

echo "=============================================="
echo "    Post-installation cleanup complete!"
echo "=============================================="

exit 0
