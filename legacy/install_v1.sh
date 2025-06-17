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
    local DEVICE="/dev/${DISK}"

    log_info "Kiểm tra kết nối mạng..."
    if ! ping -c 3 google.com &>/dev/null; then
        log_error "Không có kết nối mạng. Vui lòng kết nối bằng 'nmtui' và chạy lại."
    fi

    log_info "Đồng bộ đồng hồ hệ thống..."
    timedatectl set-ntp true

    log_info "Phân vùng ổ đĩa ${DEVICE} cho Legacy BIOS (MBR)..."
    wipefs -a "$DEVICE" &>/dev/null || true
    sgdisk --zap-all "$DEVICE" &>/dev/null
    
    # Tự động hóa fdisk để tạo MBR partition table và các phân vùng
    # 1. Boot partition: 512M, active
    # 2. Swap partition: 4G
    # 3. Root partition: Phần còn lại
    (
    echo o # Tạo một bảng phân vùng DOS mới
    echo n # Thêm phân vùng mới (boot)
    echo p # Phân vùng chính
    echo 1 # Phân vùng số 1
    echo   # Sector đầu tiên (mặc định)
    echo +512M # Sector cuối cùng (+512M)
    echo a # Đặt cờ bootable cho phân vùng 1
    echo n # Thêm phân vùng mới (swap)
    echo p # Phân vùng chính
    echo 2 # Phân vùng số 2
    echo   # Sector đầu tiên (mặc định)
    echo +4G  # Sector cuối cùng (+4G)
    echo t # Thay đổi loại phân vùng
    echo 2 # Chọn phân vùng số 2
    echo 82 # Đặt thành Linux swap
    echo n # Thêm phân vùng mới (root)
    echo p # Phân vùng chính
    echo 3 # Phân vùng số 3
    echo   # Sector đầu tiên (mặc định)
    echo   # Sector cuối cùng (mặc định, phần còn lại)
    echo w # Ghi các thay đổi và thoát
    ) | fdisk "${DEVICE}"

    local PART_BOOT="${DEVICE}1"
    local PART_SWAP="${DEVICE}2"
    local PART_ROOT="${DEVICE}3"
    partprobe "${DEVICE}" || true; sleep 2

    log_info "Định dạng và Mount các phân vùng..."
    # Phân vùng boot cho Legacy thường là ext2/ext4, nhưng FAT32 cũng hoạt động và linh hoạt hơn
    mkfs.fat -F32 "${PART_BOOT}"
    mkswap "${PART_SWAP}"
    swapon "${PART_SWAP}"
    if [ "${FILESYSTEM}" = "btrfs" ]; then
        log_info "Định dạng root với Btrfs..."
        mkfs.btrfs -f "${PART_ROOT}"
    else
        log_info "Định dạng root với Ext4..."
        mkfs.ext4 -F "${PART_ROOT}"
    fi
    mount "${PART_ROOT}" /mnt
    mkdir -p /mnt/boot
    mount "${PART_BOOT}" /mnt/boot
    
    log_info "Tối ưu mirror và pacstrap..."
    pacman -Sy --noconfirm --needed reflector &>/dev/null
    reflector --country 'VN,SG,JP,HK,TW,DE,US' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    local -a PACKAGES_TO_INSTALL=(base base-devel linux-lts linux-firmware networkmanager grub neovim git)
    if [ "${FILESYSTEM}" = "btrfs" ]; then PACKAGES_TO_INSTALL+=( "btrfs-progs" ); fi
    pacstrap /mnt "${PACKAGES_TO_INSTALL[@]}"

    log_info "Tạo fstab và cấu hình chroot..."
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Dùng heredoc để truyền biến, đơn giản hơn cho script này
    arch-chroot /mnt /bin/bash -c "
        set -euo pipefail;
        # Cấu hình cơ bản
        ln -sf /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime;
        hwclock --systohc;
        sed -i 's/^#${LOCALE}/${LOCALE}/' /etc/locale.gen;
        locale-gen;
        echo 'LANG=${LOCALE}' > /etc/locale.conf;
        echo 'KEYMAP=${KEYMAP}' > /etc/vconsole.conf;
        echo '${HOSTNAME}' > /etc/hostname;
        cat << EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain   ${HOSTNAME}
EOF

        # Tạo Initramfs
        mkinitcpio -P;

        # Cài đặt GRUB cho Legacy BIOS
        # Cài vào Master Boot Record (MBR) của ổ đĩa
        grub-install --target=i386-pc /dev/${DISK};
        grub-mkconfig -o /boot/grub/grub.cfg;

        # Tạo user và đặt mật khẩu
        useradd -m -U -G wheel -s /bin/bash ${USER_NAME};
        echo '${USER_NAME}:${PASSWORD}' | chpasswd;
        echo 'root:${PASSWORD}' | chpasswd;
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel;
        
        # Bật NetworkManager
        systemctl enable NetworkManager;
    "

    log_info "CÀI ĐẶT HOÀN TẤT!"
    log_info "Bây giờ anh có thể unmount và khởi động lại."
    printf "\n  umount -R /mnt\n  reboot\n\n"
}

main "$@

