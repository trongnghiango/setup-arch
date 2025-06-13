#!/usr/bin/env bash
set -euo pipefail

# deploy.sh (v7 - Final User-Switching Fix)

echo "--- Bắt đầu quy trình triển khai TẤT CẢ TRONG MỘT ---"

# --- Thu thập thông tin ---
DISK="vda"
HOSTNAME="arch-final"
DOTFILES_REPO="https://github.com/trongnghiango/voidrice.git"
PROGS_LIST_URL="https://raw.githubusercontent.com/trongnghiango/programs-list/main/progs.csv"

echo "Các giá trị sau sẽ được sử dụng:"
echo "  - Ổ đĩa: $DISK"
echo "  - Hostname: $HOSTNAME"
read -rp "Nhấn Enter để tiếp tục hoặc Ctrl+C để hủy."

read -rp "Nhập URL repo dotfiles của bạn [${DOTFILES_REPO}]: " DOTFILES_REPO_OVERRIDE
DOTFILES_REPO_OVERRIDE=${DOTFILES_REPO_OVERRIDE:-$DOTFILES_REPO}

read -rp "Nhập URL file progs.csv của bạn [${PROGS_LIST_URL}]: " PROGS_LIST_URL_OVERRIDE
PROGS_LIST_URL_OVERRIDE=${PROGS_LIST_URL_OVERRIDE:-$PROGS_LIST_URL}

read -sp "Nhập mật khẩu cho user 'ka' và 'root': " SHARED_PASSWORD
echo

# --- Kiểm tra file ---
if [ ! -f ./arch_install.sh ]; then
    echo "LỖI: Cần file 'arch_install.sh' trong cùng thư mục." >&2
    exit 1
fi
chmod +x ./arch_install.sh

# --- Giai đoạn 1: Cài đặt Arch cơ bản ---
echo "--- Bắt đầu Giai đoạn 1: Cài đặt Arch Linux ---"
./arch_install.sh "$DISK" "$HOSTNAME" "$SHARED_PASSWORD"
if [ $? -ne 0 ]; then
    echo "!!!!!! LỖI trong quá trình cài đặt Arch cơ bản. Dừng lại. !!!!!!"
    exit 1
fi
echo "--- Hoàn thành Giai đoạn 1 ---"

# --- Giai đoạn 2: Cài đặt LARBS với đúng user ---
echo "--- Bắt đầu Giai đoạn 2: Cài đặt LARBS ---"

# Tạo một script wrapper sẽ chạy với quyền root
echo "[DEPLOY] Đang tạo script wrapper cho LARBS..."
cat << 'LARBS_WRAPPER_ROOT' > /mnt/root/larbs_wrapper_root.sh
#!/usr/bin/env sh
set -eu

# Script này chạy với quyền root. Nhiệm vụ của nó là chuẩn bị môi trường
# và sau đó chuyển quyền cho user 'ka' để chạy script chính.

# Tạo file thực thi cho user 'ka'
cat << 'LARBS_SCRIPT_KA' > /home/ka/run_larbs_as_ka.sh
#!/usr/bin/env sh
set -eu
LOG_FILE="/var/log/larbs_setup.log"
# Chuyển hướng output vào log file
exec > >(tee -a \${LOG_FILE}) 2>&1

echo "--- Bắt đầu chạy LARBS với user 'ka' ---"

# Lấy các biến từ file config
source /root/larbs_config.sh

# Tải về larbs.sh gốc
echo "Đang tải về larbs.sh gốc từ larbs.xyz..."
curl -Lso /home/ka/larbs.sh https://larbs.xyz/larbs.sh
if [ ! -s /home/ka/larbs.sh ]; then
    echo "LỖI: Tải về larbs.sh thất bại! File trống."
    exit 1
fi
chmod +x /home/ka/larbs.sh

# Chạy larbs.sh gốc, nó sẽ tự hỏi các thông tin cần thiết.
# Chúng ta sẽ cung cấp các thông tin đó thông qua `printf` và pipe.
# Đây là cách tự động hóa whiptail.
printf "%s\n%s\n%s\n%s\n" "ka" "${USER_PASSWORD}" "${USER_PASSWORD}" | sh /home/ka/larbs.sh

echo "--- Hoàn thành LARBS ---"
# Dọn dẹp
rm /home/ka/larbs.sh /home/ka/run_larbs_as_ka.sh /root/larbs_config.sh
LARBS_SCRIPT_KA

# Trao quyền sở hữu và thực thi cho user 'ka'
chown ka:wheel /home/ka/run_larbs_as_ka.sh
chmod +x /home/ka/run_larbs_as_ka.sh

# Chuyển sang user 'ka' và thực thi script
echo "Chuyển sang user 'ka' để thực thi..."
sudo -u ka /home/ka/run_larbs_as_ka.sh
LARBS_WRAPPER_ROOT

# Tạo file config chứa các biến mà script con sẽ cần
cat << LARBS_CONFIG > /mnt/root/larbs_config.sh
# Các biến này hiện không dùng đến trong phương pháp mới, nhưng để lại cho tương lai
DOTFILES_REPO="${DOTFILES_REPO_OVERRIDE}"
PROGS_LIST_URL="${PROGS_LIST_URL_OVERRIDE}"
USER_PASSWORD="${SHARED_PASSWORD}"
LARBS_CONFIG

# Chạy script wrapper bằng arch-chroot
echo "[DEPLOY] Đang vào chroot để thực thi script wrapper..."
arch-chroot /mnt /bin/sh /root/larbs_wrapper_root.sh
rm /mnt/root/larbs_wrapper_root.sh

echo "--- Hoàn thành Giai đoạn 2 ---"
echo
echo "✅ TRIỂN KHAI TẤT CẢ TRONG MỘT HOÀN TẤT!"
echo "Hệ thống đã sẵn sàng. Bạn có thể unmount và khởi động lại."
echo "  umount -R /mnt"
echo "  reboot"

