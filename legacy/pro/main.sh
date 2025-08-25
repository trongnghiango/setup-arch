#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#==============================================================================
# HÀM TIỆN ÍCH
#==============================================================================
log_info() { echo -e "\e[1;32m[INFO]\e[0m  $*"; }
log_warn() { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
log_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $*" >&2
    exit 1
}
step() { echo -e "\n\e[1;34m>>> $*\e[0m"; }

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Tự động cài đặt Arch Linux + Desktop (Legacy BIOS) với hỗ trợ Dual-Boot."
    echo
    echo "Options:"
    echo "  -u, --user <name>      Tên user (mặc định: ka)"
    echo "  -d, --disk <device>    Ổ đĩa cài đặt (ví dụ: sda) (bắt buộc cho cài đặt sạch)"
    echo "  -H, --hostname <name>  Tên máy (mặc định: arch-legacy)"
    echo "  -f, --filesystem <fs>  Hệ thống tệp (ext4|btrfs) (mặc định: ext4)"
    echo "  -m, --manager <type>   Trình quản lý dotfiles (rsync|stow) (mặc định: rsync)"
    echo "  -b, --dual-boot <part> Kích hoạt chế độ dual-boot với phân vùng Windows (ví dụ: sda1)."
    echo "  -h, --help             Hiển thị trợ giúp này"
}

#==============================================================================
# CHƯƠNG TRÌNH CHÍNH
#==============================================================================
main() {
    # --- Cấu hình Mặc định & Tham số ---
    local USER_NAME="ka" DISK="" HOSTNAME="arch-legacy" FILESYSTEM="ext4" DOTFILES_MANAGER="rsync"
    local DUAL_BOOT_MODE=false WIN_PART=""
    local PROGS_LIST_URL="https://raw.githubusercontent.com/trongnghiango/programs-list/refs/heads/main/progs.csv"
    local TIME_ZONE="Asia/Ho_Chi_Minh" LOCALE="en_US.UTF-8"

    # Cấu hình các Repo Dotfiles
    local RSYNC_DOTFILES_REPO="https://github.com/trongnghiango/voidrice.git"
    local STOW_DOTFILES_REPO="https://github.com/trongnghiango/dotfiles-stow.git"
    local DOTFILES_REPO=""

    # Phân tích tham số dòng lệnh
    local TEMP
    TEMP=$(getopt -o u:d:H:f:m:b:h --long user:,disk:,hostname:,filesystem:,manager:,dual-boot:,help -n "$0" -- "$@")
    if [ $? != 0 ]; then log_error "Terminating..."; fi
    eval set -- "$TEMP"; unset TEMP
    while true; do
        case "$1" in
            -u|--user) USER_NAME="$2"; shift 2 ;;
            -d|--disk) DISK="$2"; shift 2 ;;
            -H|--hostname) HOSTNAME="$2"; shift 2 ;;
            -f|--filesystem)
                if [[ "$2" == "ext4" || "$2" == "btrfs" ]]; then FILESYSTEM="$2"; else log_error "Filesystem không hợp lệ: '$2'."; fi; shift 2 ;;
            -m|--manager)
                if [[ "$2" == "rsync" || "$2" == "stow" ]]; then DOTFILES_MANAGER="$2"; else log_error "Trình quản lý dotfiles không hợp lệ: '$2'."; fi; shift 2 ;;
            -b|--dual-boot) DUAL_BOOT_MODE=true; WIN_PART="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            --) shift; break ;;
            *) log_error "Internal error!" ;;
        esac
    done

    # --- Xác thực và chuẩn bị biến ---
    if [ "$DUAL_BOOT_MODE" = true ]; then
        if [ -z "$WIN_PART" ]; then log_error "Chế độ dual-boot yêu cầu chỉ định phân vùng Windows (--dual-boot)."; fi
        DISK=$(echo "$WIN_PART" | sed 's/[0-9]*$//')
        log_info "Chế độ Dual-Boot được kích hoạt. Mục tiêu là ổ đĩa /dev/${DISK}."
    else
        if [ -z "$DISK" ]; then log_error "Chế độ cài đặt sạch yêu cầu chỉ định ổ đĩa (--disk)."; fi
        log_info "Chế độ Cài đặt Sạch được kích hoạt."
    fi

    # --- Bắt đầu ---
    clear; log_info "Bắt đầu quy trình cài đặt Arch Linux (Legacy BIOS Mode)."
    echo "-------------------------------------------------"; echo "Cấu hình sẽ được sử dụng:"; echo "  - User:             ${USER_NAME}"; echo "  - Hostname:         ${HOSTNAME}"; echo "  - Disk:             /dev/${DISK}"; echo "  - Filesystem:       ${FILESYSTEM}"; echo "  - Dotfiles Manager: ${DOTFILES_MANAGER}";
    if [ "$DUAL_BOOT_MODE" = true ]; then echo "  - Mode:             Dual-Boot (với /dev/${WIN_PART})"; else echo "  - Mode:           Cài đặt sạch (Clean Install)"; fi
    echo "-------------------------------------------------"
    read -sp "Nhập mật khẩu cho user '${USER_NAME}' và 'root': " PASSWORD; echo; echo
    if [ -z "${PASSWORD}" ]; then log_error "Mật khẩu không được để trống."; fi
    
    if [ "$DUAL_BOOT_MODE" = true ]; then echo "CẢNH BÁO: Phân vùng Windows /dev/${WIN_PART} sẽ KHÔNG BỊ XÓA. Script sẽ tạo phân vùng mới trong không gian trống."; else echo "CẢNH BÁO: TOÀN BỘ DỮ LIỆU TRÊN /dev/${DISK} SẼ BỊ XÓA."; fi
    read -rp "Bạn có chắc chắn muốn bắt đầu? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "Đã hủy."; exit 0; fi

    # GIAI ĐOẠN 1: CÀI ĐẶT ARCH CƠ BẢN
    step "Giai đoạn 1: Cài đặt hệ thống Arch cơ bản"
    local DEVICE="/dev/${DISK}"; local PART_BOOT=""; local PART_LVM=""

    if [ "$DUAL_BOOT_MODE" = true ]; then
        log_info "Phân vùng /dev/${DISK} cho dual-boot. KHÔNG xóa dữ liệu..."
        local NEXT_PART_NUM=$(($(lsblk -lnpo NAME,TYPE "${DEVICE}" | grep -c "part") + 1))
        local BOOT_PART_NUM=${NEXT_PART_NUM}
        local LVM_PART_NUM=$((NEXT_PART_NUM + 1))
        PART_BOOT="${DEVICE}${BOOT_PART_NUM}"; PART_LVM="${DEVICE}${LVM_PART_NUM}"
        log_info "Sẽ tạo phân vùng boot là ${PART_BOOT} và LVM là ${PART_LVM}"
        
        # *** SỬA LỖI: Sắp xếp lại thứ tự lệnh fdisk cho ổn định ***
        # 1. Tạo tất cả phân vùng trước. 2. Sửa thuộc tính sau.
        printf "n\np\n%s\n\n+512M\nn\np\n%s\n\n\nt\n%s\n8e\na\n%s\nw\n" \
            "${BOOT_PART_NUM}" "${LVM_PART_NUM}" "${LVM_PART_NUM}" "${BOOT_PART_NUM}" | fdisk "${DEVICE}"

    else
        log_info "XÓA SẠCH và phân vùng ổ đĩa ${DEVICE} cho Legacy BIOS (MBR)..."
        wipefs -a "$DEVICE" &>/dev/null || true; sgdisk --zap-all "$DEVICE" &>/dev/null

        # *** SỬA LỖI: Sắp xếp lại thứ tự lệnh fdisk cho ổn định ***
        # 1. Tạo tất cả phân vùng trước. 2. Sửa thuộc tính sau.
        printf "o\nn\np\n1\n\n+512M\nn\np\n2\n\n\nt\n2\n8e\na\n1\nw\n" | fdisk "${DEVICE}"

        PART_BOOT="${DEVICE}1"; PART_LVM="${DEVICE}2"
    fi
    partprobe "$DEVICE" || true; sleep 2
    
    log_info "Thiết lập LVM, Định dạng, Mount..."
    timedatectl set-ntp true; pvcreate "${PART_LVM}"; vgcreate vg0 "${PART_LVM}"; local RAM_SIZE_MB; RAM_SIZE_MB=$(free -m | awk '/^Mem:/{print $2}'); lvcreate -L "${RAM_SIZE_MB}M" vg0 -n swap; lvcreate -l 100%FREE vg0 -n root
    mkfs.ext4 -F "${PART_BOOT}"; if [ "${FILESYSTEM}" = "btrfs" ]; then mkfs.btrfs -f /dev/vg0/root; else mkfs.ext4 -F /dev/vg0/root; fi
    mkswap /dev/vg0/swap; swapon /dev/vg0/swap; mount /dev/vg0/root /mnt; mkdir -p /mnt/boot; mount "${PART_BOOT}" /mnt/boot

    log_info "Cập nhật keyring của môi trường live để tránh lỗi PGP..."; pacman -Sy --noconfirm --needed archlinux-keyring
    log_info "Tối ưu mirror và pacstrap..."; pacman -Sy --noconfirm --needed reflector &>/dev/null
    reflector --country 'VN,SG,JP,HK,TW' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    local -a PACKAGES_TO_INSTALL=(base base-devel linux-lts linux-firmware rsync xorg-xinit networkmanager lvm2 grub os-prober ntfs-3g sudo git curl neovim zsh dash libnewt)
    if [ "${FILESYSTEM}" = "btrfs" ]; then PACKAGES_TO_INSTALL+=( "btrfs-progs" ); fi
    pacstrap /mnt "${PACKAGES_TO_INSTALL[@]}"
    
    log_info "Tạo fstab..."; genfstab -U /mnt >> /mnt/etc/fstab
    if [ "$DUAL_BOOT_MODE" = true ]; then
        log_info "Thêm phân vùng Windows vào fstab..."; mkdir -p /mnt/mnt/windows
        echo "/dev/${WIN_PART}  /mnt/windows  ntfs-3g  defaults,windows_names,locale=en_US.UTF-8  0 0" >> /mnt/etc/fstab
    fi
    
    cat << VAR_FILE > /mnt/root/install_vars.sh
DISK="${DISK}"; HOSTNAME="${HOSTNAME}"; USER_NAME="${USER_NAME}"; PASSWORD="${PASSWORD}"; LOCALE="${LOCALE}"; TIME_ZONE="${TIME_ZONE}"; FILESYSTEM="${FILESYSTEM}"; DUAL_BOOT_MODE="${DUAL_BOOT_MODE}"
VAR_FILE
    cat << 'CHROOT_SCRIPT' > /mnt/root/chroot_config.sh
#!/usr/bin/env bash
set -euo pipefail; source /root/install_vars.sh
ln -sf "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime; hwclock --systohc
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen; locale-gen; echo "LANG=${LOCALE}" > /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname
HOOKS_LINE="base udev autodetect keyboard keymap modconf block lvm2 filesystems fsck"
if [ "${FILESYSTEM}" = "btrfs" ]; then HOOKS_LINE="base udev autodetect keyboard keymap modconf block btrfs lvm2 filesystems fsck"; fi
sed -i "s/^HOOKS=.*/HOOKS=(${HOOKS_LINE})/" /etc/mkinitcpio.conf; mkinitcpio -P
grub-install --target=i386-pc "/dev/${DISK}"
if [ "${DUAL_BOOT_MODE}" = true ]; then sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub; fi
grub-mkconfig -o /boot/grub/grub.cfg
useradd -m -U -G wheel -s /bin/zsh "${USER_NAME}";
echo "${USER_NAME}:${PASSWORD}" | chpasswd; echo "root:${PASSWORD}" | chpasswd
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/99_install_privileges
systemctl enable NetworkManager; ln -sfT /bin/dash /bin/sh
CHROOT_SCRIPT
    chmod 644 /mnt/root/install_vars.sh; chmod 755 /mnt/root/chroot_config.sh
    arch-chroot /mnt /bin/bash /root/chroot_config.sh; rm /mnt/root/chroot_config.sh /mnt/root/install_vars.sh

    # GIAI ĐOẠN 2: CÀI ĐẶT DESKTOP
    step "Giai đoạn 2: Cài đặt môi trường desktop"
    cp ./install_packages.sh /mnt/root/; chmod +x /mnt/root/install_packages.sh
    local dotfiles_script_name=""
    if [ "${DOTFILES_MANAGER}" = "stow" ]; then DOTFILES_REPO="${STOW_DOTFILES_REPO}"; dotfiles_script_name="setup_dotfiles_stow.sh"; else DOTFILES_REPO="${RSYNC_DOTFILES_REPO}"; dotfiles_script_name="setup_dotfiles.sh"; fi
    cp "./${dotfiles_script_name}" /mnt/root/; chmod +x "/mnt/root/${dotfiles_script_name}"
    arch-chroot /mnt /root/install_packages.sh "${PROGS_LIST_URL}" "${USER_NAME}"
    arch-chroot /mnt "/root/${dotfiles_script_name}" "${DOTFILES_REPO}" "${USER_NAME}"

    # GIAI ĐOẠN 3: DỌN DẸP
    step "Giai đoạn 3: Dọn dẹp"
    arch-chroot /mnt rm /etc/sudoers.d/99_install_privileges
    arch-chroot /mnt /bin/bash -c "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel;"
    arch-chroot /mnt rm /root/install_packages.sh "/root/${dotfiles_script_name}"
    rm -f /mnt/tmp/progs.csv
    log_info "CÀI ĐẶT HOÀN TẤT!"; log_info "Bây giờ anh có thể unmount và khởi động lại."; printf "\n  umount -R /mnt\n  reboot\n\n"
}

main "$@"
