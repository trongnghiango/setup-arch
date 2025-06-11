#!/usr/bin/env bash
set -euo pipefail

# deploy.sh (v5 - All-in-One LiveISO execution)

echo "--- Bắt đầu quy trình triển khai TẤT CẢ TRONG MỘT ---"

# --- Thu thập thông tin ---
DISK="vda"
HOSTNAME="arch-live"
DOTFILES_REPO="https://github.com/lukesmithxyz/voidrice.git"
PROGS_LIST_URL="https://raw.githubusercontent.com/LukeSmithxyz/LARBS/master/static/progs.csv"

echo "Các giá trị sau sẽ được sử dụng:"
echo "  - Ổ đĩa: $DISK"
echo "  - Hostname: $HOSTNAME"
read -rp "Nhấn Enter để tiếp tục hoặc Ctrl+C để hủy."

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

# --- Giai đoạn 2: Cài đặt LARBS ngay lập tức ---
echo "--- Bắt đầu Giai đoạn 2: Cài đặt LARBS ---"

# Tạo một script nhỏ để thực thi bên trong chroot.
# Cách này đáng tin cậy hơn là dùng heredoc phức tạp.
echo "[DEPLOY] Đang tạo script tạm thời để chạy LARBS..."
cat << 'LARBS_RUNNER' > /mnt/root/run_larbs_now.sh
#!/usr/bin/env bash
set -eu
LOG_FILE="/var/log/larbs_setup.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "--- Bắt đầu chạy LARBS từ bên trong chroot ---"

# Lấy các biến từ file config
source /root/larbs_config.sh

# Tải về larbs.sh
echo "Đang tải về larbs.sh từ larbs.xyz..."
curl -Lso /root/larbs.sh https://larbs.xyz/larbs.sh
if [ ! -s /root/larbs.sh ]; then
    echo "LỖI: Tải về larbs.sh thất bại! File trống."
    exit 1
fi

# 'Vá' lại larbs.sh
echo "Đang tùy biến larbs.sh..."
sed -i "s#dotfilesrepo=.*#dotfilesrepo=\"${DOTFILES_REPO}\"#" /root/larbs.sh
sed -i "s#progsfile=.*#progsfile=\"${PROGS_LIST_URL}\"#" /root/larbs.sh
sed -i "s/getuserandpass/name='ka'; pass1='unused'/" /root/larbs.sh
sed -i 's/usercheck || error \"User exited.\"//' /root/larbs.sh
sed -i 's/adduserandpass/usermod -s \/bin\/zsh ka; export repodir=\\\"\/home\/ka\/\.local\/src\\\"; mkdir -p \${repodir}; chown -R ka:wheel \$(dirname \${repodir})/' /root/larbs.sh

# Chạy LARBS
echo "Đang thực thi larbs.sh. Quá trình này sẽ mất nhiều thời gian..."
sh /root/larbs.sh

echo "--- Hoàn thành LARBS ---"
# Dọn dẹp
rm /root/larbs_config.sh /root/run_larbs_now.sh /root/larbs.sh
LARBS_RUNNER

# Tạo file config chứa các biến tùy chỉnh cho script trên
cat << LARBS_CONFIG > /mnt/root/larbs_config.sh
DOTFILES_REPO="${DOTFILES_REPO}"
PROGS_LIST_URL="${PROGS_LIST_URL}"
LARBS_CONFIG

# Chạy script đó bằng arch-chroot
echo "[DEPLOY] Đang vào chroot để thực thi script cài đặt LARBS..."
arch-chroot /mnt /bin/bash /root/run_larbs_now.sh

echo "--- Hoàn thành Giai đoạn 2 ---"
echo
echo "✅ TRIỂN KHAI TẤT CẢ TRONG MỘT HOÀN TẤT!"
echo "Hệ thống đã sẵn sàng. Bạn có thể unmount và khởi động lại."
echo "  umount -R /mnt"
echo "  reboot"

