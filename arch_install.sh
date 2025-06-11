#!/usr/bin/env bash
set -euo pipefail

# arch_install.sh (v7 - Standalone & Fixed)

# --- Kiểm tra tham số ---
if [ "$#" -ne 3 ]; then
    echo "Sử dụng: $0 <disk_name> <hostname> <password>" >&2
    exit 1
fi

DISK="$1"
HOSTNAME="$2"
PASSWORD="$3"
DEVICE="/dev/${DISK}"

# --- Cảnh báo ---
echo "[ARCH_INSTALL] Sẽ xóa dữ liệu trên ${DEVICE}."
read -rp "Bạn có chắc chắn muốn tiếp tục không? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "[ARCH_INSTALL] Đã hủy."
  exit 1
fi

# --- Xóa và Phân vùng ---
echo "[ARCH_INSTALL] Đang phân vùng ${DEVICE}..."
wipefs -a "$DEVICE" &>/dev/null || true
sgdisk --zap-all "$DEVICE" &>/dev/null
parted -s "$DEVICE" mklabel gpt
parted -s "$DEVICE" mkpart "" fat32 1MiB 513MiB
parted -s "$DEVICE" set 1 esp on
parted -s "$DEVICE" mkpart "" ext4 513MiB 100%
parted -s "$DEVICE" set 2 lvm on
PART_BOOT="${DEVICE}1"
PART_LVM="${DEVICE}2"
partprobe "$DEVICE" || true; sleep 2
timedatectl set-ntp true

# --- LVM ---
echo "[ARCH_INSTALL] Đang thiết lập LVM..."
pvcreate "${PART_LVM}"
vgcreate vg0 "${PART_LVM}"
lvcreate -L 4G vg0 -n swap
lvcreate -l 100%FREE vg0 -n root

# --- Định dạng và Mount ---
echo "[ARCH_INSTALL] Đang định dạng và mount..."
mkfs.fat -F32 "$PART_BOOT"
mkfs.btrfs -f /dev/vg0/root
mkswap /dev/vg0/swap
swapon /dev/vg0/swap
mount /dev/vg0/root /mnt
mkdir -p /mnt/boot
mount "$PART_BOOT" /mnt/boot

# --- Tối ưu Mirror và Pacstrap ---
echo "[ARCH_INSTALL] Đang tối ưu mirror và cài đặt gói..."
pacman -Sy --noconfirm --needed reflector &>/dev/null
#reflector --country 'VN,SG,JP,KR,TW' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
reflector \
#  --verbose \
  --protocol https \
  --country 'VN,SG,JP,KR,TW,US,TH,HK' \
  --age 12 \
  --sort rate \
  --latest 30 \
  --save /etc/pacman.d/mirrorlist

if [ ! -s /etc/pacman.d/mirrorlist ]; then
    echo "!!!!!! LỖI: reflector không tìm thấy mirror nào. Kiểm tra lại kết nối mạng hoặc các tham số quốc gia."
    exit 1
fi
echo "[ARCH_INSTALL] Đã tạo danh sách mirror mới. Nội dung:"
cat /etc/pacman.d/mirrorlist
echo "[ARCH_INSTALL] Cài đặt các gói với pacstrap (bao gồm btrfs-progs)..."
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware btrfs-progs \
    networkmanager lvm2 grub efibootmgr sudo git curl libnewt zsh dash neovim reflector \
    intel-ucode

# --- fstab ---
echo "[ARCH_INSTALL] Đang tạo fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- Cấu hình trong chroot ---
echo "[ARCH_INSTALL] Đang cấu hình hệ thống cơ bản..."
arch-chroot /mnt /bin/bash -c "
    set -euo pipefail;
    ln -sf /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime;
    hwclock --systohc;
    sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen;
    locale-gen;
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf;
    echo '${HOSTNAME}' > /etc/hostname;
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block btrfs lvm2 filesystems fsck)/' /etc/mkinitcpio.conf;
    mkinitcpio -P;
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH --recheck;
    grub-mkconfig -o /boot/grub/grub.cfg;
    useradd -m -g wheel -s /bin/bash ka;
    echo 'ka:${PASSWORD}' | chpasswd;
    echo 'root:${PASSWORD}' | chpasswd;
    echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers;
    systemctl enable NetworkManager;
"
echo "[ARCH_INSTALL] Hoàn thành."

