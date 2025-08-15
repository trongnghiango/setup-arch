#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#==============================================================================
# HÀM TIỆN ÍCH
#==============================================================================
log_info() { echo -e "\e[1;32m[INFO]\e[0m  $*"; }
log_error() { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

#==============================================================================
# CHƯƠNG TRÌNH CHÍNH
#==============================================================================

# --- Kiểm tra đối số ---
if [ "$#" -ne 2 ]; then
    log_error "Cách dùng: $0 <progs_list_url> <user_name>"
fi

PROGS_LIST_URL="$1"
USER_NAME="$2"
AUR_HELPER="yay"
PROGS_FILE="/tmp/progs.csv"

log_info "Tải xuống danh sách các gói từ ${PROGS_LIST_URL}..."
curl -Ls "${PROGS_LIST_URL}" | sed '/^#/d' > "${PROGS_FILE}"
if [ ! -s "${PROGS_FILE}" ]; then
    log_error "Không thể tải xuống hoặc tệp danh sách chương trình trống."
fi

log_info "Bắt đầu cài đặt các gói từ kho Pacman (với quyền root)..."
while IFS=, read -r tag program comment; do
    if [[ "$tag" == "" || "$tag" == "M" ]]; then
        pacman -S --noconfirm --needed "$program"
    fi
done < "${PROGS_FILE}"

log_info "Chuyển sang người dùng '${USER_NAME}' để cài đặt các gói AUR và Git..."
sudo -u "${USER_NAME}" /bin/bash -c '
    set -euo pipefail
    # Các biến này được truyền từ tập lệnh cha
    AUR_HELPER="'${AUR_HELPER}'"
    PROGS_FILE="'${PROGS_FILE}'"
    SRC_DIR="$HOME/.local/src"
    mkdir -p "$SRC_DIR"

    log_info_user() { echo -e "  \e[1;32m[USER]\e[0m  $*"; }

    log_info_user "Cài đặt trình trợ giúp AUR (${AUR_HELPER})..."
    if ! command -v ${AUR_HELPER} &> /dev/null; then
        cd "$SRC_DIR"
        git clone --depth 1 "https://aur.archlinux.org/${AUR_HELPER}.git"
        cd "${AUR_HELPER}"
        makepkg --noconfirm -si
    fi

    log_info_user "Cài đặt các gói AUR và Git..."
    while IFS=, read -r tag program comment; do
        case "$tag" in
            "A")
                log_info_user "Cài đặt AUR: ${program}"
                "${AUR_HELPER}" -S --noconfirm --needed "$program"
                ;;
            "G")
                progname="${program##*/}"
                progname="${progname%.git}"
                log_info_user "Cài đặt Git: ${progname} từ ${program}"
                cd "$SRC_DIR"
                if [ ! -d "$progname" ]; then
                    git clone --depth 1 "${program}"
                fi
                cd "${progname}"
                make && sudo make install
                ;;
        esac
    done < "${PROGS_FILE}"
'

log_info "Cài đặt các gói đã hoàn tất."
