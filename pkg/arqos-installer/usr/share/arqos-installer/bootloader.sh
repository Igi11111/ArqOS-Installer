#!/bin/bash
set -e

echo "=============================================="
echo "    Installing Bootloader for ArqOS"
echo "=============================================="

# Usuń hooki archiso z mkinitcpio.conf
echo "[1/4] Fixing mkinitcpio.conf..."
if [ -f /etc/mkinitcpio.conf ]; then
    sed -i 's/archiso//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_loop_mnt//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_common//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_nbd//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_http//g' /etc/mkinitcpio.conf
    sed -i 's/archiso_pxe_nfs//g' /etc/mkinitcpio.conf
    sed -i 's/memdisk//g' /etc/mkinitcpio.conf
    sed -i 's/  */ /g' /etc/mkinitcpio.conf
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf
    echo "mkinitcpio.conf fixed"
else
    echo "Warning: /etc/mkinitcpio.conf not found!"
fi

if [ -f /etc/mkinitcpio.conf.d/archiso.conf ]; then
    echo "Removing archiso.conf..."
    rm -f /etc/mkinitcpio.conf.d/archiso.conf
fi

echo "[2/4] Rebuilding initramfs..."
if ! mkinitcpio -P; then
    echo "Error: Failed to rebuild initramfs"
    exit 1
fi

echo "[3/4] Detecting firmware type..."
if [ -d /sys/firmware/efi ]; then
    echo "Detected: UEFI system"
    FIRMWARE="UEFI"
else
    echo "Detected: BIOS/Legacy system"
    FIRMWARE="BIOS"
fi

echo "[4/4] Installing GRUB..."

if [ "$FIRMWARE" = "UEFI" ]; then
    # UEFI Installation
    echo "Installing GRUB for UEFI..."

    if ! mountpoint -q /boot/efi; then
        echo "Error: /boot/efi is not mounted!"
        exit 1
    fi

    if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArqOS --recheck; then
        echo "Error: GRUB installation failed"
        exit 1
    fi

    echo "GRUB installed to /boot/efi"

else
    # BIOS Installation
    echo "Installing GRUB for BIOS..."

    ROOT_PARTITION=$(findmnt -n -o SOURCE / | head -1)

    if [ -z "$ROOT_PARTITION" ]; then
        echo "Error: Cannot determine root partition"
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
                echo "Error: GRUB installation failed"
                exit 1
            fi
        else
            echo "No BIOS Boot partition found!"
            echo "This is UNRELIABLE but attempting with --force..."
            echo ""
            echo "NOTE: For proper installation, recreate partitions with:"
            echo "  - 1MB BIOS Boot partition (type: ef02) at the start"
            echo "  OR convert to MBR/DOS partition table"
            echo ""

            # Próbuj z --force (blocklists)
            if grub-install --target=i386-pc --force "$DISK" 2>&1 | tee /tmp/grub-install.log; then
                echo "GRUB installed with blocklists (UNRELIABLE)"
                echo "System may fail to boot after kernel updates!"
            else
                echo "=========================================="
                echo "CRITICAL: GRUB installation failed!"
                echo "=========================================="
                echo ""
                echo "Your disk uses GPT without a BIOS Boot partition."
                echo "Options to fix:"
                echo ""
                echo "1. Restart installation and add 1MB BIOS Boot partition"
                echo "2. Convert disk to MBR (if <2TB)"
                echo "3. Enable UEFI in BIOS settings"
                echo ""
                cat /tmp/grub-install.log
                exit 1
            fi
        fi
    else
        # MBR/DOS - zwykła instalacja
        echo "MBR partition table - installing normally"
        if ! grub-install --target=i386-pc "$DISK"; then
            echo "Error: GRUB installation failed"
            exit 1
        fi
    fi

    echo "GRUB installed to $DISK"
fi

# Konfiguruj GRUB
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
    echo "Error: Failed to generate GRUB config"
    exit 1
fi

echo "Installing Grub theme by yeyushengfan258"
bash /etc/install-grub-theme.sh

echo "=============================================="
echo "    Bootloader installation complete!"
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
