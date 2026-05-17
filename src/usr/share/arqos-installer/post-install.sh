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
        pacman -Sy gnome --noconfirm --overwrite '*'

        # Usuń KDE jeśli jest zainstalowane
        # if pacman -Qi plasma-desktop &>/dev/null; then
            print_msg "Removing KDE Plasma..."
            pacman -Rsc plasma-desktop --noconfirm || true
        # fi

        print_msg "GNOME installation complete"
        return 0

    elif [[ "$de_value" == "1" ]]; then
        print_msg "KDE Plasma selected (already installed)"
        # Usuń GNOME jeśli jest zainstalowane
        # print_msg "Removing GNOME..."
        # pacman -Rsc gnome --noconfirm || true


        print_msg "KDE Plasma configuration complete"
        return 0

elif [[ "$de_value" == "2" ]]; then
        print_msg "Installing Budgie Desktop Environment..."
    # 1. aktualizacja systemu NAJPIERW (bez mieszania w DE)
        pacman -Syu --noconfirm
    # 2. usunięcie KDE (jeśli jest)
        pacman -Rns plasma-desktop kwin-x11 --noconfirm || true
        pacman -S budgie --noconfirm
        print_msg "Budgie installation complete"
    return 0
fi
}




# ===== FUNKCJA USTAWIAJĄCA DOMYŚLNEGO USERA =====
set_default_user() {
    print_msg "Setting default user for display manager..."

    # Znajdź utworzonego użytkownika z pliku add_users.sh lub /etc/passwd
    # Najpierw sprawdź czy skrypt add_users.sh istnieje i zawiera USERNAME
    if [ -f /add_users.sh ]; then
        CREATED_USER=$(grep "^USERNAME=" /add_users.sh | cut -d"'" -f2)
        print_msg "Found username from add_users.sh: $CREATED_USER"
    fi

    # Jeśli nie znaleziono w skrypcie, sprawdź /etc/passwd
    if [ -z "$CREATED_USER" ]; then
        CREATED_USER=$(grep ":/home/" /etc/passwd | grep -v "nologin\|false" | head -1 | cut -d: -f1)
        print_msg "Found username from /etc/passwd: $CREATED_USER"
    fi

    if [ -z "$CREATED_USER" ]; then
        print_error "No regular user found"
        return 1
    fi

    print_msg "Configuring display manager for user: $CREATED_USER"

    # Konfiguracja dla SDDM (KDE Plasma)
    if systemctl list-unit-files | grep -q sddm.service; then
        print_msg "Configuring SDDM..."
        mkdir -p /etc/sddm.conf.d

        cat > /etc/sddm.conf.d/default-user.conf << EOF
[Theme]
Current=breeze

[Users]
DefaultUser=$CREATED_USER
RememberLastUser=true
RememberLastSession=true
HideUsers=
HideShells=
EOF

        chmod 644 /etc/sddm.conf.d/default-user.conf
        print_msg "✓ SDDM configured with default user: $CREATED_USER"
    fi

    # Konfiguracja dla GDM (GNOME)
    if systemctl list-unit-files | grep -q gdm.service; then
        print_msg "Configuring GDM..."
        mkdir -p /etc/gdm

        cat > /etc/gdm/custom.conf << EOF
[daemon]
# DefaultSession will be selected by user
# TimedLoginEnable=false means no automatic login
TimedLoginEnable=false
TimedLogin=$CREATED_USER
TimedLoginDelay=0

# Do not automatically login
AutomaticLoginEnable=false
AutomaticLogin=

[security]

[xdmcp]

[chooser]

[debug]
EOF

        chmod 644 /etc/gdm/custom.conf
        print_msg "✓ GDM configured (no autologin)"
    fi

    # Konfiguracja dla LightDM
    if systemctl list-unit-files | grep -q lightdm.service; then
        print_msg "Configuring LightDM..."

        if [ -f /etc/lightdm/lightdm.conf ]; then
            # Upewnij się że autologin jest wyłączony
            sed -i 's/^autologin-user=.*/# autologin-user=/' /etc/lightdm/lightdm.conf
            sed -i 's/^autologin-session=.*/# autologin-session=/' /etc/lightdm/lightdm.conf

            # Pokaż listę użytkowników
            if grep -q "^#*greeter-hide-users=" /etc/lightdm/lightdm.conf; then
                sed -i "s/^#*greeter-hide-users=.*/greeter-hide-users=false/" /etc/lightdm/lightdm.conf
            else
                echo "greeter-hide-users=false" >> /etc/lightdm/lightdm.conf
            fi
        fi

        print_msg "✓ LightDM configured to show user list"
    fi

    print_msg "✓ Default user configuration complete"
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

# GDM
rm -f /etc/gdm/custom.conf

# SDDM
rm -f /etc/sddm.conf.d/autologin.conf
rm -f /etc/sddm.conf.d/90-archiso.conf
rm -f /etc/sddm.conf

# LightDM
rm -f /etc/lightdm/lightdm.conf.d/autologin.conf

# Usuń wszelkie live ISO autologin leftovers
find /etc/systemd/system/getty@tty1.service.d -type f -delete 2>/dev/null || true

echo "Autologin configuration removed"

echo "[6/9] Removing live ISO polkit rules..."
rm -f /etc/polkit-1/rules.d/49-nopasswd_global.rules

echo "[7/9] Removing live ISO motd..."
rm -f /etc/motd

echo "[8/9] Cleaning live ISO user files..."
rm -f /root/.zlogin
rm -f /root/.automated_script.sh

echo "[9/9] Enabling essential services..."

# Pacman keys setting
script -q -c "pacman-key --init" /dev/null
script -q -c "pacman-key --populate archlinux" /dev/null
pacman -Syu --noconfirm || true

# NetworkManager
if systemctl list-unit-files | grep -q NetworkManager.service; then
    systemctl enable NetworkManager
    echo "NetworkManager enabled"
fi

# ===== WYWOŁANIE FUNKCJI WYBORU DE =====
check_de_selection

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

set_default_user

echo "=============================================="
echo "    Essential services configuration complete"
echo "=============================================="

# Wyczyść pliki konfiguracyjne
print_msg "Cleaning up configuration files..."
rm -f "$DE_SELECTION_FILE" "$FLATPAK_FILE" "$UPDATES_FILE"

pacman -Rsc arqos-installer --noconfirm || true

echo "=============================================="
echo "    Post-installation cleanup complete!"
echo "=============================================="

exit 0
