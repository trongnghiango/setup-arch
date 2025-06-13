#!/usr/bin/env bash
set -euo pipefail # Dừng script nếu có lỗi, biến chưa khai báo, lỗi trong pipe
IFS=$'\n\t'     # Phân tách từ bằng newline và tab

#==============================================================================
# CẤU HÌNH TOÀN CỤC - SỬA Ở ĐÂY
#==============================================================================

# --- Cấu hình hệ thống ---
readonly DISK="vda"             # Ổ đĩa cài đặt (vda, sda, nvme0n1...)
readonly HOSTNAME="arch-luke"   # Tên máy
readonly TIME_ZONE="Asia/Ho_Chi_Minh"
readonly LOCALE="en_US.UTF-8"

# --- Cấu hình User ---
readonly USER_NAME="ka"         # Tên user sẽ được tạo

# --- Cấu hình LARBS ---
readonly DOTFILES_REPO="https://github.com/trongnghiango/voidrice.git"
readonly PROGS_LIST_URL="https://raw.githubusercontent.com/trongnghiango/programs-list/refs/heads/main/progs.csv"
readonly AUR_HELPER="yay"

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

#==============================================================================
# CHƯƠNG TRÌNH CHÍNH
#==============================================================================

main() {
    # --- Bắt đầu ---
    clear
    log_info "Bắt đầu quy trình cài đặt Arch Linux + LARBS tự động."
    
    read -sp "Nhập mật khẩu cho user '${USER_NAME}' và 'root': " PASSWORD
    echo; echo
    if [ -z "${PASSWORD}" ]; then
        log_error "Mật khẩu không được để trống."
    fi

    echo "CẢNH BÁO: TOÀN BỘ DỮ LIỆU TRÊN /dev/${DISK} SẼ BỊ XÓA."
    read -rp "Bạn có chắc chắn muốn bắt đầu? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Đã hủy."
      exit 0
    fi

    #---------------------------------------------------------------------------
    # GIAI ĐOẠN 1: CÀI ĐẶT ARCH LINUX CƠ BẢN
    #---------------------------------------------------------------------------
    step "Giai đoạn 1: Cài đặt hệ thống Arch cơ bản"
    local DEVICE="/dev/${DISK}"

    log_info "Phân vùng ổ đĩa ${DEVICE} cho UEFI..."
    wipefs -a "$DEVICE" &>/dev/null || true
    sgdisk --zap-all "$DEVICE" &>/dev/null
    parted -s "$DEVICE" mklabel gpt
    parted -s "$DEVICE" mkpart primary fat32 1MiB 513MiB
    parted -s "$DEVICE" set 1 esp on
    parted -s "$DEVICE" mkpart primary 513MiB 100%
    local PART_BOOT="${DEVICE}1"
    local PART_LVM="${DEVICE}2"
    partprobe "$DEVICE" || true; sleep 2
    
    log_info "Đồng bộ đồng hồ hệ thống..."
    timedatectl set-ntp true

    log_info "Thiết lập LVM..."
    pvcreate "${PART_LVM}"
    vgcreate vg0 "${PART_LVM}"
    local RAM_SIZE_MB
    RAM_SIZE_MB=$(free -m | awk '/^Mem:/{print $2}')
    lvcreate -L "${RAM_SIZE_MB}M" vg0 -n swap
    lvcreate -l 100%FREE vg0 -n root

    log_info "Định dạng và mount các phân vùng..."
    mkfs.fat -F32 "${PART_BOOT}"
    mkfs.btrfs -f /dev/vg0/root
    mkswap /dev/vg0/swap
    swapon /dev/vg0/swap
    mount /dev/vg0/root /mnt
    mkdir -p /mnt/boot
    mount "${PART_BOOT}" /mnt/boot

    log_info "Tối ưu mirror và cài đặt các gói cơ bản với pacstrap..."
    pacman -Sy --noconfirm --needed reflector &>/dev/null
    reflector --country 'VN,SG,JP' --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    pacstrap /mnt base base-devel linux-lts linux-firmware btrfs-progs rsync \
        networkmanager lvm2 grub efibootmgr sudo git curl neovim zsh dash libnewt

    log_info "Tạo fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    log_info "Cấu hình hệ thống cơ bản bên trong chroot..."
    arch-chroot /mnt /bin/bash -c "
        set -euo pipefail;
        ln -sf /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime;
        hwclock --systohc;
        sed -i 's/^#${LOCALE}/${LOCALE}/' /etc/locale.gen;
        locale-gen;
        echo 'LANG=${LOCALE}' > /etc/locale.conf;
        echo '${HOSTNAME}' > /etc/hostname;
        sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block btrfs lvm2 filesystems fsck)/' /etc/mkinitcpio.conf;
        mkinitcpio -P;
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH --recheck;
        grub-mkconfig -o /boot/grub/grub.cfg;
        useradd -m -U -G wheel -s /bin/bash ${USER_NAME};
        echo '${USER_NAME}:${PASSWORD}' | chpasswd;
        echo 'root:${PASSWORD}' | chpasswd;
        echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/99_install_privileges;
        systemctl enable NetworkManager;
    "

    #---------------------------------------------------------------------------
    # GIAI ĐOẠN 2: CÀI ĐẶT DESKTOP
    #---------------------------------------------------------------------------
    step "Giai đoạn 2: Cài đặt môi trường desktop"
    
    log_info "Tạo script con 'desktop_setup.sh' để chạy trong chroot..."
    cat << 'DESKTOP_SETUP_TEMPLATE' > /mnt/root/desktop_setup.sh
#!/usr/bin/env bash
set -euo pipefail

# Lấy các biến đã được truyền vào
USER_NAME_PARAM="__USER_NAME__"
DOTFILES_REPO_PARAM="__DOTFILES_REPO__"
PROGS_LIST_URL_PARAM="__PROGS_LIST_URL__"
AUR_HELPER_PARAM="__AUR_HELPER__"

echo "--- Bắt đầu thực thi desktop_setup.sh với quyền root ---"

# Tải danh sách chương trình
PROGS_FILE="/tmp/progs.csv"
curl -Ls "${PROGS_LIST_URL_PARAM}" | sed '/^#/d' > "${PROGS_FILE}"

# Cài các gói từ kho chính thức bằng pacman
echo "--> Cài đặt các gói từ kho Pacman..."
while IFS=, read -r tag program comment; do
    if [[ "$tag" == "" || "$tag" == "M" ]]; then
        echo "    - Cài đặt: ${program}"
        pacman -S --noconfirm --needed "$program"
    fi
done < "${PROGS_FILE}"

# Đổi shell mặc định của user thành zsh (BƯỚC CỰC KỲ QUAN TRỌNG)
echo "--> Đổi shell mặc định của user '${USER_NAME_PARAM}' thành zsh..."
chsh -s /bin/zsh "${USER_NAME_PARAM}"

# Chuyển sang user để cài đặt phần còn lại
echo "--> Chuyển sang user '${USER_NAME_PARAM}' để cài đặt AUR và dotfiles..."
SRC_DIR_ABS="/home/${USER_NAME_PARAM}/.local/src"
mkdir -p "$SRC_DIR_ABS"
# Gán quyền sở hữu cho TOÀN BỘ thư mục home để đảm bảo user có thể ghi
chown -R ${USER_NAME_PARAM}:${USER_NAME_PARAM} "/home/${USER_NAME_PARAM}"

sudo -u "${USER_NAME_PARAM}" /bin/bash -c '
    set -euo pipefail
    
    # Thiết lập các biến cần thiết bên trong subshell của user
    PROGS_FILE="/tmp/progs.csv"
    SRC_DIR="$HOME/.local/src"
    AUR_HELPER="__AUR_HELPER__"
    DOTFILES_REPO="__DOTFILES_REPO__"
    
    # Cài đặt AUR Helper (yay)
    echo "    - Cài đặt ${AUR_HELPER} (AUR Helper)..."
    if ! command -v ${AUR_HELPER} &> /dev/null; then
        cd "$SRC_DIR"
        git clone --depth 1 "https://aur.archlinux.org/${AUR_HELPER}-git.git"
        cd "${AUR_HELPER}-git"
        makepkg --noconfirm -si
    fi
    
    # Cài đặt các gói AUR và Git
    while IFS=, read -r tag program comment; do
        case "$tag" in
            "A")
                echo "    - Cài đặt (AUR): ${program}"
                ${AUR_HELPER} -S --noconfirm --needed "$program"
                ;;
            "G")
                echo "    - Cài đặt (Git): ${program}"
                progname="${program##*/}"
                progname="${progname%.git}"
                cd "$SRC_DIR"
                if [ ! -d "$progname" ]; then
                    git clone --depth 1 "${program}"
                fi
                cd "${progname}"
                make && sudo make install
                ;;
        esac
    done < "$PROGS_FILE"
    
    # Cài đặt dotfiles theo cách của LARBS
    echo "    - Cài đặt dotfiles..."
    DOTFILES_TMP_DIR=$(mktemp -d)
    git clone --depth=1 --recurse-submodules "${DOTFILES_REPO}" "${DOTFILES_TMP_DIR}"
    # Dùng cp -rfT để đổ tất cả nội dung vào thư mục home
    cp -rfT "${DOTFILES_TMP_DIR}" "$HOME"
    rm -rf "${DOTFILES_TMP_DIR}"
'

# Các bước cấu hình cuối cùng bắt chước LARBS
echo "--> Thực hiện các bước cấu hình cuối cùng..."
ln -sfT /bin/dash /bin/sh
sudo -u "${USER_NAME_PARAM}" mkdir -p "/home/${USER_NAME_PARAM}/.cache/zsh/"

echo "--- Hoàn thành desktop_setup.sh ---"
DESKTOP_SETUP_TEMPLATE

    # Thay thế các placeholder trong script con bằng giá trị thật
    sed -i "s|__USER_NAME__|${USER_NAME}|g" /mnt/root/desktop_setup.sh
    sed -i "s|__DOTFILES_REPO__|${DOTFILES_REPO}|g" /mnt/root/desktop_setup.sh
    sed -i "s|__PROGS_LIST_URL__|${PROGS_LIST_URL}|g" /mnt/root/desktop_setup.sh
    sed -i "s|__AUR_HELPER__|${AUR_HELPER}|g" /mnt/root/desktop_setup.sh

    log_info "Thực thi 'desktop_setup.sh' bên trong chroot..."
    arch-chroot /mnt /bin/bash /root/desktop_setup.sh

    #---------------------------------------------------------------------------
    # GIAI ĐOẠN 3: DỌN DẸP
    #---------------------------------------------------------------------------
    step "Giai đoạn 3: Dọn dẹp và hoàn thiện"

    log_info "Thiết lập lại quyền sudo chuẩn và dọn dẹp file tạm..."
    arch-chroot /mnt rm /etc/sudoers.d/99_install_privileges
    arch-chroot /mnt /bin/bash -c "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel;"
    arch-chroot /mnt rm /root/desktop_setup.sh
    rm -f /mnt/tmp/progs.csv

    # --- HOÀN THÀNH ---
    log_info "CÀI ĐẶT HOÀN TẤT!"
    log_info "Bây giờ anh có thể unmount và khởi động lại."
    printf "\n  umount -R /mnt\n  reboot\n\n"
}

# Chạy hàm main
main
