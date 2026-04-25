#!/bin/bash
set -e

echo "=============================================="
echo "    Installing Bootloader for ArqOS v2"
echo "=============================================="

echo ""
echo "[1/5] Cleaning archiso configurations..."

# KROK 1: Usuń wszystkie pliki archiso z mkinitcpio.conf.d
if [ -d /etc/mkinitcpio.conf.d ]; then
    echo "Removing all files from /etc/mkinitcpio.conf.d/..."
    rm -rf /etc/mkinitcpio.conf.d/*
    echo "✓ Cleaned /etc/mkinitcpio.conf.d/"
fi

# KROK 2: Napraw preset files - usuń referencje do archiso
echo "Fixing preset files..."
for preset in /etc/mkinitcpio.d/*.preset; do
    if [ -f "$preset" ]; then
        echo "  Checking $preset..."

        # Usuń linie zawierające archiso
        sed -i '/archiso/d' "$preset" 2>/dev/null || true

        # Usuń puste linie ALL_config= lub PRESETS=
        sed -i '/^ALL_config=$/d' "$preset" 2>/dev/null || true
        sed -i '/^PRESETS=()$/d' "$preset" 2>/dev/null || true

        echo "  ✓ Fixed $preset"
    fi
done

# KROK 3: Napraw główny plik konfiguracyjny
echo "Fixing /etc/mkinitcpio.conf..."
if [ -f /etc/mkinitcpio.conf ]; then
    # Backup
    cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup

    # Usuń wszystkie hooki archiso
    sed -i 's/archiso//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_loop_mnt//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_common//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_nbd//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_http//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_nfs//g' /etc/mkinitcpio.conf
    sed -i 's/memdisk//g' /etc/mkinitcpio.conf

    # Wyczyść podwójne spacje
    sed -i 's/  */ /g' /etc/mkinitcpio.conf

    # Ustaw standardowe HOOKS
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf

    echo "✓ Fixed /etc/mkinitcpio.conf"
else
    echo "✗ Warning: /etc/mkinitcpio.conf not found!"
fi

echo ""
echo "[2/5] Verifying configuration..."

# Sprawdź czy nie ma już referencji do archiso
if grep -r "archiso" /etc/mkinitcpio.conf /etc/mkinitcpio.d/ 2>/dev/null; then
    echo "✗ WARNING: Still found archiso references!"
    echo "Attempting aggressive cleanup..."

    # Agresywne czyszczenie - usuń wszystkie linie z archiso
    find /etc/mkinitcpio.d/ -type f -name "*.preset" -exec sed -i '/archiso/d' {} \;

    echo "✓ Aggressive cleanup done"
else
    echo "✓ No archiso references found"
fi

echo ""
echo "[3/5] Rebuilding initramfs..."

# Najpierw spróbuj dla konkretnego kernela
if [ -f /boot/vmlinuz-linux ]; then
    echo "Rebuilding for linux kernel..."
    if mkinitcpio -p linux 2>&1 | tee /tmp/mkinitcpio.log; then
        echo "✓ Initramfs rebuilt successfully"
    else
        echo "✗ Error rebuilding initramfs"
        echo "Log:"
        cat /tmp/mkinitcpio.log
        exit 1
    fi
else
    echo "✗ Kernel not found at /boot/vmlinuz-linux"
    exit 1
fi

echo ""
echo "[4/5] Detecting firmware type..."
if [ -d /sys/firmware/efi ]; then
    echo "Detected: UEFI system"
    FIRMWARE="UEFI"
else
    echo "Detected: BIOS/Legacy system"
    FIRMWARE="BIOS"
fi

echo ""
echo "[5/5] Installing GRUB..."

if [ "$FIRMWARE" = "UEFI" ]; then
    # UEFI Installation
    echo "Installing GRUB for UEFI..."

    if ! mountpoint -q /boot/efi; then
        echo "✗ Error: /boot/efi is not mounted!"
        exit 1
    fi

    if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArqOS --recheck; then
        echo "✗ Error: GRUB installation failed"
        exit 1
    fi

    echo "✓ GRUB installed to /boot/efi"

else
    # BIOS Installation
    echo "Installing GRUB for BIOS..."

    ROOT_PARTITION=$(findmnt -n -o SOURCE / | head -1)

    if [ -z "$ROOT_PARTITION" ]; then
        echo "✗ Error: Cannot determine root partition"
        exit 1
    fi

    # Wyciągnij nazwę dysku
    if [[ "$ROOT_PARTITION" =~ nvme ]]; then
        DISK=$(echo "$ROOT_PARTITION" | sed 's/p[0-9]*$//')
    else
        DISK=$(echo "$ROOT_PARTITION" | sed 's/[0-9]*$//')
    fi

    echo "Root partition: $ROOT_PARTITION"
    echo "Installing to disk: $DISK"

    # Sprawdź typ tablicy partycji
    PART_TABLE=$(parted -s "$DISK" print 2>/dev/null | grep "Partition Table" | awk '{print $3}')

    echo "Partition table type: $PART_TABLE"

    if [ "$PART_TABLE" = "gpt" ]; then
        echo "=========================================="
        echo "WARNING: GPT on BIOS system detected!"
        echo "=========================================="

        # Sprawdź czy istnieje partycja BIOS Boot
        HAS_BIOSBOOT=$(parted -s "$DISK" print 2>/dev/null | grep -c "bios_grub" || true)

        if [ "$HAS_BIOSBOOT" -gt 0 ]; then
            echo "BIOS Boot partition found - installing normally"
            if ! grub-install --target=i386-pc "$DISK"; then
                echo "✗ Error: GRUB installation failed"
                exit 1
            fi
        else
            echo "No BIOS Boot partition found!"
            echo "Attempting with --force (UNRELIABLE)..."

            if grub-install --target=i386-pc --force "$DISK" 2>&1 | tee /tmp/grub-install.log; then
                echo "⚠ GRUB installed with blocklists (UNRELIABLE)"
                echo "⚠ System may fail to boot after kernel updates!"
            else
                echo "✗ CRITICAL: GRUB installation failed!"
                cat /tmp/grub-install.log
                exit 1
            fi
        fi
    else
        # MBR/DOS - zwykła instalacja
        echo "MBR partition table - installing normally"
        if ! grub-install --target=i386-pc "$DISK"; then
            echo "✗ Error: GRUB installation failed"
            exit 1
        fi
    fi

    echo "✓ GRUB installed to $DISK"
fi

# Konfiguruj GRUB
echo ""
echo "Configuring GRUB..."
if [ -f /etc/default/grub ]; then
    sed -i '/GRUB_DISABLE_OS_PROBER/d' /etc/default/grub
    echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi

# Skanuj inne systemy
if command -v os-prober >/dev/null 2>&1; then
    echo "Scanning for other operating systems..."
    os-prober || true
fi

# Generuj config
echo "Generating GRUB configuration..."
if ! grub-mkconfig -o /boot/grub/grub.cfg; then
    echo "✗ Error: Failed to generate GRUB config"
    exit 1
fi

echo ""
echo "=============================================="
echo "  ✓ Bootloader installation complete!"
echo "=============================================="

# Jeśli użyto blocklists, ostrzeż
if [ "$PART_TABLE" = "gpt" ] && [ "$HAS_BIOSBOOT" -eq 0 ] && [ "$FIRMWARE" = "BIOS" ]; then
    echo ""
    echo "⚠️  WARNING: System installed with blocklists!"
    echo "⚠️  Bootloader may break after kernel updates."
    echo "⚠️  Consider reinstalling with proper partitioning."
    echo ""
fi

exit 0
