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
    echo "A fully automated Arch Linux + Desktop installer based on your dotfiles structure."
    echo
    echo "Options:"
    echo "  -u, --user <name>      Set the username (default: ka)"
    echo "  -d, --disk <device>    Set the installation disk (e.g., sda, vda) (default: vda)"
    echo "  -H, --hostname <name>  Set the hostname (default: archlinux)"
    echo "  -f, --filesystem <fs>  Set the root filesystem (ext4 or btrfs) (default: ext4)"
    echo "  -h, --help             Display this help message"
}

#==============================================================================
# CHƯƠNG TRÌNH CHÍNH
#==============================================================================

main() {
    # --- Cấu hình Mặc định & Tham số ---
    local USER_NAME="ka" DISK="vda" HOSTNAME="archlinux" FILESYSTEM="ext4"
    local DOTFILES_REPO="https://github.com/trongnghiango/voidrice.git"
    local PROGS_LIST_URL="https://raw.githubusercontent.com/trongnghiango/programs-list/refs/heads/main/progs.csv"
    local AUR_HELPER="yay" TIME_ZONE="Asia/Ho_Chi_Minh" LOCALE="en_US.UTF-8"

    # Phân tích tham số dòng lệnh
    local TEMP; TEMP=$(getopt -o u:d:H:f:h --long user:,disk:,hostname:,filesystem:,help -n "$0" -- "$@")
    if [ $? != 0 ]; then log_error "Terminating..."; fi
    eval set -- "$TEMP"; unset TEMP
    while true; do
        case "$1" in
            -u|--user) USER_NAME="$2"; shift 2 ;; -d|--disk) DISK="$2"; shift 2 ;;
            -H|--hostname) HOSTNAME="$2"; shift 2 ;;
            -f|--filesystem)
                if [[ "$2" == "ext4" || "$2" == "btrfs" ]]; then FILESYSTEM="$2"; else log_error "Filesystem không hợp lệ: '$2'."; fi; shift 2 ;;
            -h|--help) usage; exit 0 ;; --) shift; break ;; *) log_error "Internal error!" ;;
        esac
    done

    # --- Bắt đầu ---
    clear; log_info "Bắt đầu quy trình cài đặt Arch Linux + Desktop."
    echo "-------------------------------------------------"; echo "Cấu hình sẽ được sử dụng:"; echo "  - User:           ${USER_NAME}"; echo "  - Hostname:       ${HOSTNAME}"; echo "  - Disk:           /dev/${DISK}"; echo "  - Filesystem:     ${FILESYSTEM}"; echo "-------------------------------------------------"
    read -sp "Nhập mật khẩu cho user '${USER_NAME}' và 'root': " PASSWORD; echo; echo
    if [ -z "${PASSWORD}" ]; then log_error "Mật khẩu không được để trống."; fi
    read -rp "CẢNH BÁO: TOÀN BỘ DỮ LIỆU TRÊN /dev/${DISK} SẼ BỊ XÓA. Tiếp tục? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "Đã hủy."; exit 0; fi

    # GIAI ĐOẠN 1: CÀI ĐẶT ARCH CƠ BẢN
    step "Giai đoạn 1: Cài đặt hệ thống Arch cơ bản"
    local DEVICE="/dev/${DISK}"; log_info "Phân vùng, LVM, Định dạng, Mount..."
    wipefs -a "$DEVICE" &>/dev/null || true; sgdisk --zap-all "$DEVICE" &>/dev/null
    parted -s "$DEVICE" mklabel gpt; parted -s "$DEVICE" mkpart p fat32 1MiB 513MiB; parted -s "$DEVICE" set 1 esp on; parted -s "$DEVICE" mkpart p ext4 513MiB 100%; parted -s "$DEVICE" set 2 lvm on
    local PART_BOOT="${DEVICE}1"; local PART_LVM="${DEVICE}2"; partprobe "$DEVICE" || true; sleep 2
    timedatectl set-ntp true; pvcreate "${PART_LVM}"; vgcreate vg0 "${PART_LVM}"; local RAM_SIZE_MB; RAM_SIZE_MB=$(free -m | awk '/^Mem:/{print $2}'); lvcreate -L "${RAM_SIZE_MB}M" vg0 -n swap; lvcreate -l 100%FREE vg0 -n root
    mkfs.fat -F32 "${PART_BOOT}"; if [ "${FILESYSTEM}" = "btrfs" ]; then mkfs.btrfs -f /dev/vg0/root; else mkfs.ext4 -F /dev/vg0/root; fi
    mkswap /dev/vg0/swap; swapon /dev/vg0/swap; mount /dev/vg0/root /mnt; mkdir -p /mnt/boot; mount "${PART_BOOT}" /mnt/boot
    log_info "Tối ưu mirror và pacstrap..."; pacman -Sy --noconfirm --needed reflector &>/dev/null
    reflector --country 'VN,SG,JP' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    local -a PACKAGES_TO_INSTALL=(base base-devel linux-lts linux-firmware xorg-xinit networkmanager lvm2 grub efibootmgr sudo git curl neovim zsh dash libnewt)
    if [ "${FILESYSTEM}" = "btrfs" ]; then PACKAGES_TO_INSTALL+=( "btrfs-progs" ); fi
    pacstrap /mnt "${PACKAGES_TO_INSTALL[@]}"
    log_info "Tạo fstab và cấu hình chroot..."; genfstab -U /mnt >> /mnt/etc/fstab
    
    cat << VAR_FILE > /mnt/root/install_vars.sh
HOSTNAME="${HOSTNAME}"; USER_NAME="${USER_NAME}"; PASSWORD="${PASSWORD}"; LOCALE="${LOCALE}"; TIME_ZONE="${TIME_ZONE}"; FILESYSTEM="${FILESYSTEM}"
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
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH --recheck
grub-mkconfig -o /boot/grub/grub.cfg
useradd -m -U -G wheel -s /bin/zsh "${USER_NAME}"; # Đặt ZSH làm shell mặc định
echo "${USER_NAME}:${PASSWORD}" | chpasswd; echo "root:${PASSWORD}" | chpasswd
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/99_install_privileges
systemctl enable NetworkManager
CHROOT_SCRIPT
    chmod 644 /mnt/root/install_vars.sh; chmod 755 /mnt/root/chroot_config.sh
    arch-chroot /mnt /bin/bash /root/chroot_config.sh; rm /mnt/root/chroot_config.sh /mnt/root/install_vars.sh

    # GIAI ĐOẠN 2: CÀI ĐẶT DESKTOP
    step "Giai đoạn 2: Cài đặt môi trường desktop"
    log_info "Tạo script con 'desktop_setup.sh' để chạy trong chroot..."

    cat << 'DESKTOP_SETUP_TEMPLATE' > /mnt/root/desktop_setup.sh
#!/usr/bin/env bash
set -euo pipefail
# Các biến placeholder sẽ được thay thế bằng sed
USER_NAME_PARAM="__USER_NAME__"
DOTFILES_REPO_PARAM="__DOTFILES_REPO__"
VOIDRICE_REPO_PARAM="__VOIDRICE_REPO__"
PROGS_LIST_URL_PARAM="__PROGS_LIST_URL__"
AUR_HELPER_PARAM="__AUR_HELPER__"

echo "--- Bắt đầu thực thi desktop_setup.sh ---"
PROGS_FILE="/tmp/progs.csv"
curl -Ls "${PROGS_LIST_URL_PARAM}" | sed '/^#/d' > "${PROGS_FILE}"

echo "--> Cài đặt các gói từ kho Pacman (bao gồm stow và git)..."
pacman -S --noconfirm --needed stow git
while IFS=, read -r tag program comment; do
    if [[ "$tag" == "" || "$tag" == "M" ]]; then pacman -S --noconfirm --needed "$program"; fi
done < "${PROGS_FILE}"

echo "--> Chuyển sang user '${USER_NAME_PARAM}' để cài đặt phần còn lại..."
sudo -u "${USER_NAME_PARAM}" /bin/bash -c '
    set -euo pipefail
    SRC_DIR="$HOME/.local/src"; mkdir -p "$SRC_DIR"
    AUR_HELPER="__AUR_HELPER__"
    DOTFILES_REPO="__DOTFILES_REPO__"
    VOIDRICE_REPO="__VOIDRICE_REPO__"

    # --- Cài đặt AUR Helper và các gói khác ---
    # ... (Giữ nguyên phần cài đặt AUR Helper và các gói)

    # --- LOGIC QUẢN LÝ VÀ TRIỂN KHAI DOTFILES ---
    echo "    - Bắt đầu quy trình triển khai dotfiles..."
    DOTFILES_DIR_FOR_STOW=""

    if git ls-remote --exit-code "${DOTFILES_REPO}" &>/dev/null; then
        echo "    --> Repo dotfiles (stow) tồn tại. Bắt đầu clone..."
        DOTFILES_DIR_FOR_STOW="$SRC_DIR/dotfiles"
        git clone --depth=1 --recurse-submodules "${DOTFILES_REPO}" "${DOTFILES_DIR_FOR_STOW}"
    else
        echo "    --> CẢNH BÁO: Repo dotfiles (stow) không tồn tại."
        echo "    --> Bắt đầu xây dựng cấu trúc stow từ repo voidrice..."
        
        VOIDRICE_DIR="$SRC_DIR/voidrice"
        git clone --depth=1 "${VOIDRICE_REPO}" "$VOIDRICE_DIR"
        
        DOTFILES_DIR_FOR_STOW="$SRC_DIR/dotfiles_built_from_voidrice"
        mkdir -p "$DOTFILES_DIR_FOR_STOW"

        echo "        - Đang tái cấu trúc các gói..."

        # Gói "bin"
        if [ -d "${VOIDRICE_DIR}/.local/bin" ]; then
            mkdir -p "${DOTFILES_DIR_FOR_STOW}/bin/.local"
            mv "${VOIDRICE_DIR}/.local/bin" "${DOTFILES_DIR_FOR_STOW}/bin/.local/"
        fi
        
        # Các gói trong .config
        CONFIG_PACKAGES=(brave dunst firefox fontconfig gtk-2.0 gtk-3.0 gtk-4.0 latexmk lf mpd mpv ncmpcpp newsboat nsxiv nvim pinentry pipewire pulse python shell wal wget x11 zathura)
        for pkg in "${CONFIG_PACKAGES[@]}"; do
            if [ -e "${VOIDRICE_DIR}/.config/${pkg}" ]; then
                mkdir -p "${DOTFILES_DIR_FOR_STOW}/${pkg}/.config"
                mv "${VOIDRICE_DIR}/.config/${pkg}" "${DOTFILES_DIR_FOR_STOW}/${pkg}/.config/"
            fi
        done
        
        # *** SỬA LỖI ZSH ***
        # 1. Xử lý gói zsh, bao gồm cả file .zshenv quan trọng
        mkdir -p "${DOTFILES_DIR_FOR_STOW}/zsh/.config"
        [ -d "${VOIDRICE_DIR}/.config/zsh" ] && mv "${VOIDRICE_DIR}/.config/zsh" "${DOTFILES_DIR_FOR_STOW}/zsh/.config/"
        [ -f "${VOIDRICE_DIR}/.zshenv" ] && mv "${VOIDRICE_DIR}/.zshenv" "${DOTFILES_DIR_FOR_STOW}/zsh/"

        # 2. Xử lý các file ở thư mục HOME, bao gồm cả .zprofile đã sửa
        [ -e "${VOIDRICE_DIR}/.gtkrc-2.0" ] && mkdir -p "${DOTFILES_DIR_FOR_STOW}/gtk" && mv "${VOIDRICE_DIR}/.gtkrc-2.0" "${DOTFILES_DIR_FOR_STOW}/gtk/"
        [ -e "${VOIDRICE_DIR}/.xprofile" ] && mkdir -p "${DOTFILES_DIR_FOR_STOW}/x11" && mv "${VOIDRICE_DIR}/.xprofile" "${DOTFILES_DIR_FOR_STOW}/x11/"
        [ -e "${VOIDRICE_DIR}/.zprofile" ] && mkdir -p "${DOTFILES_DIR_FOR_STOW}/zsh" && mv "${VOIDRICE_DIR}/.zprofile" "${DOTFILES_DIR_FOR_STOW}/zsh/" # Di chuyển .zprofile vào gói zsh
        
        # Các file độc lập gom vào gói misc-config
        mkdir -p "${DOTFILES_DIR_FOR_STOW}/misc-config/.config"
        [ -f "${VOIDRICE_DIR}/.config/mimeapps.list" ] && mv "${VOIDRICE_DIR}/.config/mimeapps.list" "${DOTFILES_DIR_FOR_STOW}/misc-config/.config/"
        [ -f "${VOIDRICE_DIR}/.config/user-dirs.dirs" ] && mv "${VOIDRICE_DIR}/.config/user-dirs.dirs" "${DOTFILES_DIR_FOR_STOW}/misc-config/.config/"
        
        echo "        - Tái cấu trúc hoàn tất."
    fi

    # --- CHẠY STOW ---
    PACKAGES_TO_STOW=(bin brave dunst firefox gtk latexmk lf misc-config mpd mpv ncmpcpp newsboat nsxiv nvim pinentry pipewire pulse python shell wal wget x11 zathura zsh)

    echo "    --> Bắt đầu tạo liên kết tượng trưng..."
    cd "${DOTFILES_DIR_FOR_STOW}"
    
    for pkg in "${PACKAGES_TO_STOW[@]}"; do
        if [ -d "$pkg" ]; then
            echo "        - Stow package: ${pkg}"
            stow --target="$HOME" --no-folding "$pkg"
        fi
    done

    
    echo "    - Cấp quyền thực thi cho các script trong ~/.local/bin..."
    if [ -d "$HOME/.local/bin" ]; then
        find "$HOME/.local/bin" -type f -exec chmod +x {} \;
    fi

    cd "$HOME"
'
# Các bước cấu hình cuối cùng với quyền root
ln -sfT /bin/dash /bin/sh
DESKTOP_SETUP_TEMPLATE

    # Thay thế các placeholder bằng giá trị thật
    sed -i "s|__USER_NAME__|${USER_NAME}|g" /mnt/root/desktop_setup.sh
    sed -i "s|__DOTFILES_REPO__|${DOTFILES_REPO}|g" /mnt/root/desktop_setup.sh
    sed -i "s|__PROGS_LIST_URL__|${PROGS_LIST_URL}|g" /mnt/root/desktop_setup.sh
    sed -i "s|__AUR_HELPER__|${AUR_HELPER}|g" /mnt/root/desktop_setup.sh
    # Cấp quyền
    chmod 755 /mnt/root/desktop_setup.sh

    log_info "Thực thi 'desktop_setup.sh' bên trong chroot..."
    arch-chroot /mnt /bin/bash /root/desktop_setup.sh

    # GIAI ĐOẠN 3: DỌN DẸP
    step "Giai đoạn 3: Dọn dẹp"
    log_info "Thiết lập lại quyền sudo chuẩn và dọn dẹp..."
    arch-chroot /mnt rm /etc/sudoers.d/99_install_privileges
    arch-chroot /mnt /bin/bash -c "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel;"
    arch-chroot /mnt rm /root/desktop_setup.sh
    rm -f /mnt/tmp/progs.csv

    log_info "CÀI ĐẶT HOÀN TẤT!"
    log_info "Bây giờ anh có thể unmount và khởi động lại."
    printf "\n  umount -R /mnt\n  reboot\n\n"
}

main "$@"
