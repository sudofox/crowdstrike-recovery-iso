#!/bin/bash

# Variables
ISO_URL="http://tinycorelinux.net/12.x/x86/release/TinyCore-current.iso"
ISO_NAME="TinyCore-current.iso"
WORK_DIR="$(pwd)/tciso"
SCRIPT_NAME="remove_driver.sh"
ISO_OUTPUT="CustomTinyCore.iso"
DRIVER_DIR="/Windows/System32/drivers/CrowdStrike"
DRIVER_PATTERN="C-00000291*.sys"
PROBLEMATIC_TIMESTAMP="0409" # Problematic version timestamp
LOG_FILE="/tmp/driver_removal.log"

# Download Tiny Core Linux ISO
if [ ! -f "$ISO_NAME" ]; then
    echo "Downloading Tiny Core Linux ISO..."
    wget -O $ISO_NAME $ISO_URL
    if [ $? -ne 0 ]; then
        echo "Failed to download Tiny Core Linux ISO."
        exit 1
    fi
fi

# Prepare the script to remove the driver
cat <<EOF > $SCRIPT_NAME
#!/bin/bash
DRIVER_DIR="$DRIVER_DIR"
DRIVER_PATTERN="$DRIVER_PATTERN"
PROBLEMATIC_TIMESTAMP="$PROBLEMATIC_TIMESTAMP"
LOG_FILE="$LOG_FILE"

# Loop through all NTFS partitions
for partition in \$(lsblk -o NAME,FSTYPE | grep ntfs | awk '{print \$1}'); do
    PARTITION_PATH="/dev/\$partition"
    MOUNT_POINT="/mnt/\$partition"
    mkdir -p \$MOUNT_POINT
    mount -t ntfs-3g \$PARTITION_PATH \$MOUNT_POINT

    if [ \$? -eq 0 ]; then
        echo "Mounted NTFS partition: \$PARTITION_PATH" | tee -a \$LOG_FILE
        FULL_DRIVER_DIR="\$MOUNT_POINT\$DRIVER_DIR"
        for file in \$FULL_DRIVER_DIR/\$DRIVER_PATTERN; do
            if [ -f "\$file" ]; then
                echo "Found matching file: \$file" | tee -a \$LOG_FILE
                file_timestamp=\$(echo \$file | grep -oP '\\d{4}(?=\\.sys\$)')
                echo "Extracted timestamp: \$file_timestamp" | tee -a \$LOG_FILE
                if [ "\$file_timestamp" = "\$PROBLEMATIC_TIMESTAMP" ]; then
                    rm -f "\$file"
                    echo "Problematic driver file \$file removed successfully." | tee -a \$LOG_FILE
                else
                    echo "Driver file \$file does not match the problematic timestamp." | tee -a \$LOG_FILE
                fi
            else
                echo "Driver file \$file not found." | tee -a \$LOG_FILE
            fi
        done
        umount \$MOUNT_POINT
    else
        echo "Failed to mount NTFS partition: \$PARTITION_PATH" | tee -a \$LOG_FILE
    fi
    rmdir \$MOUNT_POINT
done
EOF

# Make the script executable
chmod +x $SCRIPT_NAME

# Create work dir and also iso dir
mkdir -p $WORK_DIR/iso

# Extract the Tiny Core Linux ISO
sudo mount -o loop $ISO_NAME $WORK_DIR/iso
cp -r $WORK_DIR/iso/* $WORK_DIR/
sudo umount $WORK_DIR/iso

# Add the script to Tiny Core Linux
mkdir -p $WORK_DIR/tce/optional/
cp $SCRIPT_NAME $WORK_DIR/tce/optional/

# Modify the boot configuration to run the script at startup without quiet mode and boot to CLI
echo "append initrd=/boot/core.gz tce=/cdrom/tce waitusb=5:LABEL=TCALIVE tce-load=boot $SCRIPT_NAME" >> $WORK_DIR/boot/isolinux/isolinux.cfg
echo "default 64" >> $WORK_DIR/boot/isolinux/isolinux.cfg
echo "prompt 1" >> $WORK_DIR/boot/isolinux/isolinux.cfg
echo "label 64" >> $WORK_DIR/boot/isolinux/isolinux.cfg
echo "kernel /boot/vmlinuz" >> $WORK_DIR/boot/isolinux/isolinux.cfg
echo "append initrd=/boot/core.gz tce=/cdrom/tce waitusb=5:LABEL=TCALIVE tce-load=boot $SCRIPT_NAME" >> $WORK_DIR/boot/isolinux/isolinux.cfg

# Check if mkisofs is installed
if ! command -v mkisofs &> /dev/null; then
    echo "mkisofs not found. Installing..."
    if command -v yum &> /dev/null; then
        sudo yum install -y genisoimage
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y genisoimage
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y genisoimage
    else
        echo "Neither apt-get, yum, nor dnf found. Please install genisoimage manually."
        exit 1
    fi
fi

# Recreate the ISO
mkisofs -l -J -R -V "CustomTinyCore" -no-emul-boot -boot-load-size 4 -boot-info-table -b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat -o $ISO_OUTPUT $WORK_DIR

# Clean up
rm -rf $WORK_DIR
rm $SCRIPT_NAME

echo "Custom ISO created: $ISO_OUTPUT"
