#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#==============================================================================
# HÀM TIỆN ÍCH
#==============================================================================
# (Không thay đổi phần này)
log_info() { echo -e "\e[1;32m[INFO]\e[0m  $*"; }
log_warn() { echo -e "\e[1;33m[WARN]\e[0m  $*"; }
log_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $*" >&2
    exit 1
}
step() { echo -e "\n\e[1;34m>>> $*\e[0m"; }

usage() {
    # (Không thay đổi phần này)
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "A fully automated Arch Linux + Desktop installer based on your dotfiles structure."
    echo
    echo "Options:"
    echo "  -u, --user <name>          Set the username (default: ka)"
    echo "  -d, --disk <device>        Set the installation disk (e.g., sda, vda) (default: vda)"
    echo "  -H, --hostname <name>      Set the hostname (default: archlinux)"
    echo "  -f, --filesystem <fs>      Set the root filesystem (ext4 or btrfs) (default: ext4)"
    echo "  -D, --dotfiles-method <m>  Set dotfiles method (rsync or stow) (default: rsync)"
    echo "  -r, --dotfiles-repo <url>  Specify dotfiles repo URL (overrides default for the chosen method)"
    echo "  -h, --help                 Display this help message"
}

#==============================================================================
# CHƯƠNG TRÌNH CHÍNH
#==============================================================================

main() {
    # --- Cấu hình Mặc định & Tham số ---
    local USER_NAME="ka" DISK="vda" HOSTNAME="archlinux" FILESYSTEM="ext4" DOTFILES_METHOD="rsync"
    
    # <-- THAY ĐỔI: Khai báo 2 repo mặc định riêng biệt. VUI LÒNG THAY URL CỦA BẠN VÀO ĐÂY!
    local DOTFILES_RSYNC_REPO="https://github.com/trongnghiango/voidrice.git" # Repo cho rsync
    local DOTFILES_STOW_REPO="https://github.com/user/stow-dotfiles.git"     # Repo cho stow

    local DOTFILES_REPO="" # Sẽ được gán giá trị sau
    local PROGS_LIST_URL="https://raw.githubusercontent.com/trongnghiango/programs-list/refs/heads/main/progs.csv"
    local TIME_ZONE="Asia/Ho_Chi_Minh" LOCALE="en_US.UTF-8"

    # Phân tích tham số dòng lệnh
    local TEMP; TEMP=$(getopt -o u:d:H:f:D:r:h --long user:,disk:,hostname:,filesystem:,dotfiles-method:,dotfiles-repo:,help -n "$0" -- "$@")
    if [ $? != 0 ]; then log_error "Terminating..."; fi
    eval set -- "$TEMP"; unset TEMP
    while true; do
        case "$1" in
            -u|--user) USER_NAME="$2"; shift 2 ;;
            -d|--disk) DISK="$2"; shift 2 ;;
            -H|--hostname) HOSTNAME="$2"; shift 2 ;;
            -f|--filesystem)
                if [[ "$2" == "ext4" || "$2" == "btrfs" ]]; then FILESYSTEM="$2"; else log_error "Filesystem không hợp lệ: '$2'."; fi; shift 2 ;;
            -D|--dotfiles-method)
                if [[ "$2" == "rsync" || "$2" == "stow" ]]; then DOTFILES_METHOD="$2"; else log_error "Phương pháp dotfiles không hợp lệ: '$2'. Chỉ chấp nhận 'rsync' hoặc 'stow'."; fi; shift 2 ;;
            -r|--dotfiles-repo) DOTFILES_REPO="$2"; shift 2 ;; # <-- THAY ĐỔI: Thêm tham số mới
            -h|--help) usage; exit 0 ;;
            --) shift; break ;;
            *) log_error "Internal error!" ;;
        esac
    done
    
    # <-- THAY ĐỔI: Logic chọn URL repo dotfiles
    # Nếu người dùng không cung cấp repo tùy chỉnh, hãy chọn repo mặc định dựa trên phương pháp
    if [ -z "${DOTFILES_REPO}" ]; then
        if [ "${DOTFILES_METHOD}" == "rsync" ]; then
            DOTFILES_REPO="${DOTFILES_RSYNC_REPO}"
        else # stow
            DOTFILES_REPO="${DOTFILES_STOW_REPO}"
        fi
    fi


    # --- Bắt đầu ---
    clear; log_info "Bắt đầu quy trình cài đặt Arch Linux + Desktop."
    echo "-------------------------------------------------"; echo "Cấu hình sẽ được sử dụng:"; echo "  - User:           ${USER_NAME}"; echo "  - Hostname:       ${HOSTNAME}"; echo "  - Disk:           /dev/${DISK}"; echo "  - Filesystem:     ${FILESYSTEM}"; echo "  - Dotfiles method:${DOTFILES_METHOD}"; echo "  - Dotfiles repo:  ${DOTFILES_REPO}"; echo "-------------------------------------------------" # <-- THAY ĐỔI: Hiển thị repo sẽ dùng
    read -sp "Nhập mật khẩu cho user '${USER_NAME}', 'root' và MÃ HÓA ĐĨA: " PASSWORD; echo; echo
    if [ -z "${PASSWORD}" ]; then log_error "Mật khẩu không được để trống."; fi
    read -rp "CẢNH BÁO: TOÀN BỘ DỮ LIỆU TRÊN /dev/${DISK} SẼ BỊ XÓA. Tiếp tục? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "Đã hủy."; exit 0; fi

    # GIAI ĐOẠN 1: CÀI ĐẶT ARCH CƠ BẢN (Không thay đổi so với phiên bản trước)
    step "Giai đoạn 1: Cài đặt hệ thống Arch cơ bản"
    local DEVICE="/dev/${DISK}"; log_info "Phân vùng..."
    wipefs -a "$DEVICE" &>/dev/null || true; sgdisk --zap-all "$DEVICE" &>/dev/null
    parted -s "$DEVICE" mklabel gpt; parted -s "$DEVICE" mkpart p fat32 1MiB 513MiB; parted -s "$DEVICE" set 1 esp on; parted -s "$DEVICE" mkpart p ext4 513MiB 100%; parted -s "$DEVICE" set 2 lvm on
    local PART_BOOT="${DEVICE}1"; local PART_LVM="${DEVICE}2"; partprobe "$DEVICE" || true; sleep 2
    timedatectl set-ntp true
    log_info "Thiết lập mã hóa LUKS trên ${PART_LVM}..."
    echo -n "${PASSWORD}" | cryptsetup luksFormat --type luks2 "${PART_LVM}" -
    log_info "Mở khóa phân vùng đã mã hóa..."
    echo -n "${PASSWORD}" | cryptsetup open "${PART_LVM}" cryptlvm -
    log_info "Thiết lập LVM trên thiết bị đã giải mã, Định dạng, Mount..."
    pvcreate /dev/mapper/cryptlvm; vgcreate vg0 /dev/mapper/cryptlvm
    local RAM_SIZE_MB; RAM_SIZE_MB=$(free -m | awk '/^Mem:/{print $2}'); lvcreate -L "${RAM_SIZE_MB}M" vg0 -n swap; lvcreate -l 100%FREE vg0 -n root
    mkfs.fat -F32 "${PART_BOOT}"; if [ "${FILESYSTEM}" = "btrfs" ]; then mkfs.btrfs -f /dev/vg0/root; else mkfs.ext4 -F /dev/vg0/root; fi
    mkswap /dev/vg0/swap; swapon /dev/vg0/swap; mount /dev/vg0/root /mnt; mkdir -p /mnt/boot; mount "${PART_BOOT}" /mnt/boot
    log_info "Cập nhật keyring của môi trường live để tránh lỗi PGP..."
    pacman -Sy --noconfirm --needed archlinux-keyring
    log_info "Tối ưu mirror và pacstrap..."; pacman -Sy --noconfirm --needed reflector &>/dev/null
    reflector --country 'VN,SG,JP,HK,TW' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    local -a PACKAGES_TO_INSTALL=(base base-devel linux-lts linux-firmware rsync xorg-xinit networkmanager lvm2 grub efibootmgr sudo git curl neovim zsh dash libnewt)
    if [ "${FILESYSTEM}" = "btrfs" ]; then PACKAGES_TO_INSTALL+=( "btrfs-progs" ); fi
    if [ "${DOTFILES_METHOD}" = "stow" ]; then PACKAGES_TO_INSTALL+=( "stow" ); fi
    pacstrap /mnt "${PACKAGES_TO_INSTALL[@]}"
    log_info "Tạo fstab và cấu hình chroot..."; genfstab -U /mnt >> /mnt/etc/fstab
    local PART_LVM_UUID; PART_LVM_UUID=$(blkid -s UUID -o value "${PART_LVM}")
    cat << VAR_FILE > /mnt/root/install_vars.sh
HOSTNAME="${HOSTNAME}"; USER_NAME="${USER_NAME}"; PASSWORD="${PASSWORD}"; LOCALE="${LOCALE}"; TIME_ZONE="${TIME_ZONE}"; FILESYSTEM="${FILESYSTEM}"; PART_LVM_UUID="${PART_LVM_UUID}"
VAR_FILE
    cat << 'CHROOT_SCRIPT' > /mnt/root/chroot_config.sh
#!/usr/bin/env bash
set -euo pipefail; source /root/install_vars.sh
ln -sf "/usr/share/zoneinfo/${TIME_ZONE}" /etc/localtime; hwclock --systohc
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen; locale-gen; echo "LANG=${LOCALE}" > /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname
HOOKS_LINE="base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck"
if [ "${FILESYSTEM}" = "btrfs" ]; then HOOKS_LINE="base udev autodetect keyboard keymap modconf block btrfs encrypt lvm2 filesystems fsck"; fi
sed -i "s/^HOOKS=.*/HOOKS=(${HOOKS_LINE})/" /etc/mkinitcpio.conf; mkinitcpio -P
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${PART_LVM_UUID}:cryptlvm root=\/dev\/vg0\/root\"/" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH --recheck
grub-mkconfig -o /boot/grub/grub.cfg
useradd -m -U -G wheel -s /bin/zsh "${USER_NAME}";
echo "${USER_NAME}:${PASSWORD}" | chpasswd; echo "root:${PASSWORD}" | chpasswd
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/99_install_privileges
systemctl enable NetworkManager
ln -sfT /bin/dash /bin/sh
CHROOT_SCRIPT
    chmod 644 /mnt/root/install_vars.sh; chmod 755 /mnt/root/chroot_config.sh
    arch-chroot /mnt /bin/bash /root/chroot_config.sh; rm /mnt/root/chroot_config.sh /mnt/root/install_vars.sh

    # GIAI ĐOẠN 2: CÀI ĐẶT DESKTOP (Không thay đổi so với phiên bản trước)
    step "Giai đoạn 2: Cài đặt môi trường desktop"
    log_info "Sao chép các tập lệnh cài đặt vào chroot..."
    cp ./install_packages.sh /mnt/root/
    chmod +x /mnt/root/install_packages.sh
    log_info "Thực thi 'install_packages.sh' bên trong chroot..."
    arch-chroot /mnt /root/install_packages.sh "${PROGS_LIST_URL}" "${USER_NAME}"
    if [ "${DOTFILES_METHOD}" == "rsync" ]; then
        log_info "Sử dụng 'rsync' để thiết lập dotfiles từ ${DOTFILES_REPO}..."
        cp ./setup_dotfiles.sh /mnt/root/
        chmod +x /mnt/root/setup_dotfiles.sh
        arch-chroot /mnt /root/setup_dotfiles.sh "${DOTFILES_REPO}" "${USER_NAME}"
    elif [ "${DOTFILES_METHOD}" == "stow" ]; then
        log_info "Sử dụng 'stow' để thiết lập dotfiles từ ${DOTFILES_REPO}..."
        cp ./setup_dotfiles_stow.sh /mnt/root/
        chmod +x /mnt/root/setup_dotfiles_stow.sh
        arch-chroot /mnt /root/setup_dotfiles_stow.sh "${DOTFILES_REPO}" "${USER_NAME}"
    fi

    # GIAI ĐOẠN 3: DỌN DẸP (Không thay đổi so với phiên bản trước)
    step "Giai đoạn 3: Dọn dẹp"
    log_info "Thiết lập lại quyền sudo chuẩn và dọn dẹp các tệp tạm thời..."
    arch-chroot /mnt rm /etc/sudoers.d/99_install_privileges
    arch-chroot /mnt /bin/bash -c "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel;"
    local dotfiles_script_to_remove="setup_dotfiles.sh"
    if [ "${DOTFILES_METHOD}" == "stow" ]; then
        dotfiles_script_to_remove="setup_dotfiles_stow.sh"
    fi
    arch-chroot /mnt rm /root/install_packages.sh "/root/${dotfiles_script_to_remove}"
    rm -f /mnt/tmp/progs.csv
    log_info "CÀI ĐẶT HOÀN TẤT!"
    log_info "Bây giờ anh có thể unmount và khởi động lại."
    printf "\n  umount -R /mnt\n  reboot\n\n"
}

main "$@"
