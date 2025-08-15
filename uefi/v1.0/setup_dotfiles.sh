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
    log_error "Cách dùng: $0 <dotfiles_repo_url> <user_name>"
fi

DOTFILES_REPO="$1"
USER_NAME="$2"

log_info "Bắt đầu thiết lập dotfiles cho người dùng '${USER_NAME}'..."

sudo -u "${USER_NAME}" /bin/bash -c '
    set -euo pipefail
    DOTFILES_REPO="'${DOTFILES_REPO}'"
    SRC_DIR="$HOME/.local/src"
    DOTFILES_DIR="$SRC_DIR/dotfiles"

    log_info_user() { echo -e "  \e[1;32m[USER]\e[0m  $*"; }

    log_info_user "Sao chép kho lưu trữ dotfiles từ ${DOTFILES_REPO}..."
    if [ ! -d "$DOTFILES_DIR" ]; then
        git clone --depth=1 --recurse-submodules "${DOTFILES_REPO}" "${DOTFILES_DIR}"
    else
        log_info_user "Thư mục dotfiles đã tồn tại. Đang kéo các thay đổi mới nhất..."
        cd "$DOTFILES_DIR" && git pull
    fi

    log_info_user "Đồng bộ hóa dotfiles vào $HOME bằng rsync..."
    # Lệnh rsync này sao chép tất cả nội dung, bao gồm các tệp ẩn,
    # từ thư mục dotfiles vào thư mục chính của người dùng.
    rsync -a --exclude=".git" --exclude="README.md" "${DOTFILES_DIR}/" "$HOME/"

    log_info_user "Cấp quyền thực thi cho các tập lệnh trong ~/.local/bin..."
    if [ -d "$HOME/.local/bin" ]; then
        find "$HOME/.local/bin" -type f -exec chmod +x {} \;
    fi
'

log_info "Thiết lập dotfiles đã hoàn tất."
