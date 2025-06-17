
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#==============================================================================
# HÀM TIỆN ÍCH
#==============================================================================

# Hàm ghi log có màu mè
log_info() { echo -e "\e[1;32m[INFO]\e[0m  $*"; }
log_warn() { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
log_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $*" >&2
    exit 1
}
step() { echo -e "\n\e[1;34m>>> $*\e[0m"; }

# Hàm hiển thị hướng dẫn sử dụng
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Tự động cài đặt Arch Linux cho hệ thống Legacy (BIOS/MBR)."
    echo
    echo "Options:"
    echo "  -u, --user <name>      Tên user (mặc định: ka)"
    echo "  -d, --disk <device>    Ổ đĩa cài đặt (ví dụ: sda) (mặc định: sda)"
    echo "  -H, --hostname <name>  Tên máy (mặc định: arch-legacy)"
    echo "  -f, --filesystem <fs>  Hệ thống tệp (ext4|btrfs) (mặc định: ext4)"
    echo "  -h, --help             Hiển thị trợ giúp này"
}

#==============================================================================
# CHƯƠNG TRÌNH CHÍNH
#==============================================================================

main() {
    # --- Cấu hình Mặc định ---
    local USER_NAME="ka"
    local DISK="vda"
    local HOSTNAME="arch-legacy"
    local FILESYSTEM="ext4" # Mặc định là ext4
    # Các cấu hình hệ thống khác
    local TIME_ZONE="Asia/Ho_Chi_Minh"
    local LOCALE="en_US.UTF-8"
    local KEYMAP="us"

    # --- Phân tích các tham số dòng lệnh ---
    local TEMP
    TEMP=$(getopt -o u:d:H:f:h --long user:,disk:,hostname:,filesystem:,help -n "$0" -- "$@")
    if [ $? != 0 ]; then log_error "Terminating..."; fi
    eval set -- "$TEMP"; unset TEMP
    while true; do
        case "$1" in
            -u|--user) USER_NAME="$2"; shift 2 ;;
            -d|--disk) DISK="$2"; shift 2 ;;
            -H|--hostname) HOSTNAME="$2"; shift 2 ;;
            -f|--filesystem)
                if [[ "$2" == "ext4" || "$2" == "btrfs" ]]; then FILESYSTEM="$2"; else log_error "Filesystem không hợp lệ: '$2'."; fi; shift 2 ;;
            -h|--help) usage; exit 0 ;; --) shift; break ;; *) log_error "Internal error!" ;;
        esac
    done

    # --- Bắt đầu ---
    clear; log_info "Bắt đầu cài đặt Arch Linux (Legacy BIOS Mode)."
    echo "-------------------------------------------------"; 
    echo "Cấu hình sẽ được sử dụng:"; 
    echo "  - User:           ${USER_NAME}"; 
    echo "  - Hostname:       ${HOSTNAME}"; 
    echo "  - Disk:           /dev/${DISK}"; 
    echo "  - Filesystem:     ${FILESYSTEM}"; 
    echo "-------------------------------------------------"
    read -sp "Nhập mật khẩu cho user '${USER_NAME}' và 'root': " PASSWORD; 
    echo; echo
    if [ -z "${PASSWORD}" ]; then log_error "Mật khẩu không được để trống."; fi
    echo "CẢNH BÁO: TOÀN BỘ DỮ LIỆU TRÊN /dev/${DISK} SẼ BỊ XÓA."
    read -rp "Bạn có chắc chắn muốn bắt đầu? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "Đã hủy."; exit 0; fi

    # GIAI ĐOẠN 1: CÀI ĐẶT ARCH CƠ BẢN
    step "Giai đoạn 1: Cài đặt hệ thống Arch cơ bản"

    local DEVICE="/dev/${DISK}"; log_info "Phân vùng ổ đĩa ${DEVICE} cho Legacy BIOS (MBR)..."
    wipefs -a "$DEVICE" &>/dev/null || true; sgdisk --zap-all "$DEVICE" &>/dev/null
    (echo o; echo n; echo p; echo 1; echo; echo +512M; echo a; echo 1; echo n; echo p; echo 2; echo; echo; echo t; echo 2; echo 8e; echo w;) | fdisk "${DEVICE}"
    local PART_BOOT="${DEVICE}1"; local PART_LVM="${DEVICE}2"; partprobe "$DEVICE" || true; sleep 2
    log_info "Thiết lập LVM, định dạng và mount...";
    timedatectl set-ntp true; pvcreate "${PART_LVM}"; vgcreate vg0 "${PART_LVM}"; local RAM_SIZE_MB; RAM_SIZE_MB=$(free -m | awk '/^Mem:/{print $2}'); lvcreate -L "${RAM_SIZE_MB}M" vg0 -n swap; lvcreate -l 100%FREE vg0 -n root
    mkfs.fat -F32 "${PART_BOOT}"; if [ "${FILESYSTEM}" = "btrfs" ]; then mkfs.btrfs -f /dev/vg0/root; else mkfs.ext4 -F /dev/vg0/root; fi
    mkswap /dev/vg0/swap; swapon /dev/vg0/swap; mount /dev/vg0/root /mnt; mkdir -p /mnt/boot; mount "${PART_BOOT}" /mnt/boot
    log_info "Tối ưu mirror và pacstrap..."; pacman -Sy --noconfirm --needed reflector &>/dev/null
    reflector --country 'VN,SG,JP' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    local -a PACKAGES_TO_INSTALL=(base base-devel linux-lts linux-firmware networkmanager lvm2 grub neovim git)
    if [ "${FILESYSTEM}" = "btrfs" ]; then PACKAGES_TO_INSTALL+=( "btrfs-progs" ); fi
    pacstrap /mnt "${PACKAGES_TO_INSTALL[@]}"

    log_info "Tạo fstab và chuẩn bị cấu hình chroot..."
    genfstab -U /mnt >> /mnt/etc/fstab

    # === SỬA LỖI: DÙNG SCRIPT CON ĐỂ CHẠY TRONG CHROOT ===
    # 1. Tạo file chứa các biến
    cat << VAR_FILE > /mnt/root/install_vars.sh
DISK="${DISK}"
HOSTNAME="${HOSTNAME}"
USER_NAME="${USER_NAME}"
PASSWORD="${PASSWORD}"
LOCALE="${LOCALE}"
TIME_ZONE="${TIME_ZONE}"
FILESYSTEM="${FILESYSTEM}"
KEYMAP="${KEYMAP}"
VAR_FILE

    # 2. Tạo script con để thực thi các lệnh
    cat << 'CHROOT_SCRIPT' > /mnt/root/chroot_config.sh
#!/usr/bin/env bash
set -euo pipefail
# Đọc các biến từ file config
source /root/install_vars.sh

# Cấu hình cơ bản
ln -sf "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime
hwclock --systohc
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "${HOSTNAME}" > /etc/hostname
cat << EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
EOF

# Cấu hình Initramfs
# Gán giá trị mặc định cho ext4
HOOKS_LINE="base udev autodetect keyboard keymap modconf block lvm2 filesystems fsck"
# Kiểm tra và ghi đè nếu là btrfs
if [ "${FILESYSTEM}" = "btrfs" ]; then
    HOOKS_LINE="base udev autodetect keyboard keymap modconf block btrfs lvm2 filesystems fsck"
fi
sed -i "s/^HOOKS=.*/HOOKS=(${HOOKS_LINE})/" /etc/mkinitcpio.conf
mkinitcpio -P

# Cài đặt GRUB
grub-install --target=i386-pc "/dev/${DISK}"
grub-mkconfig -o /boot/grub/grub.cfg

# Tạo user
useradd -m -U -G wheel -s /bin/bash "${USER_NAME}"
echo "${USER_NAME}:${PASSWORD}" | chpasswd
echo "root:${PASSWORD}" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

systemctl enable NetworkManager
CHROOT_SCRIPT

    # 3. Cấp quyền và thực thi script con
    chmod 644 /mnt/root/install_vars.sh
    chmod 755 /mnt/root/chroot_config.sh
    arch-chroot /mnt /bin/bash /root/chroot_config.sh

    # 4. Dọn dẹp
    rm /mnt/root/chroot_config.sh /mnt/root/install_vars.sh
    # ==========================================================

    log_info "CÀI ĐẶT HOÀN TẤT!"
    log_info "Bây giờ anh có thể unmount và khởi động lại."
    printf "\n  umount -R /mnt\n  reboot\n\n"
}

main "$@"
