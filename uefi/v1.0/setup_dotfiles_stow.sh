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

# MỚI: Cài đặt stow vì nó không phải là gói mặc định
log_info "Cài đặt 'stow', công cụ quản lý dotfiles..."
pacman -S --noconfirm --needed stow

log_info "Bắt đầu thiết lập dotfiles cho người dùng '${USER_NAME}' với Stow..."

sudo -u "${USER_NAME}" /bin/bash -c '
    set -euo pipefail
    DOTFILES_REPO="'${DOTFILES_REPO}'"
    # Sử dụng tên thư mục rõ ràng hơn cho kho dotfiles-stow
    DOTFILES_DIR="$HOME/dotfiles" 

    log_info_user() { echo -e "  \e[1;32m[USER]\e[0m  $*"; }

    log_info_user "Sao chép kho lưu trữ dotfiles-stow từ ${DOTFILES_REPO}..."
    if [ ! -d "$DOTFILES_DIR" ]; then
        # Clone trực tiếp vào ~/dotfiles, đây là cách dùng stow phổ biến
        git clone --depth=1 "${DOTFILES_REPO}" "${DOTFILES_DIR}"
    else
        log_info_user "Thư mục dotfiles đã tồn tại. Đang kéo các thay đổi mới nhất..."
        cd "$DOTFILES_DIR" && git pull
    fi

    log_info_user "Thực thi stow để tạo các liên kết tượng trưng (symlinks)..."
    cd "$DOTFILES_DIR"
    
    # Lặp qua tất cả các thư mục con (mỗi thư mục là một "gói" stow) và thực thi stow
    # Ví dụ: nvim, zsh, git...
    for pkg in */; do
        # Loại bỏ dấu / ở cuối
        pkg_name="${pkg%/}"
        log_info_user "Stowing package: ${pkg_name}"
        # --restow sẽ xóa các link cũ và tạo lại, đảm bảo mọi thứ luôn đúng
        # --target="$HOME" chỉ định thư mục cha của dotfiles là nơi tạo symlink
        stow --restow --target="$HOME" "${pkg_name}"
    done

    log_info_user "Cấp quyền thực thi cho các tập lệnh trong ~/.local/bin (nếu có)..."
    if [ -d "$HOME/.local/bin" ]; then
        find "$HOME/.local/bin" -type f -exec chmod +x {} \;
    fi
'

log_info "Thiết lập dotfiles với Stow đã hoàn tất."
