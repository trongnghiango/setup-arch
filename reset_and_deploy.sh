#!/usr/bin/env bash
set -euo pipefail

echo "--- BẮT ĐẦU QUY TRÌNH DỌN DẸP VÀ TRIỂN KHAI LẠI ---"

# --- Bước 1: Dọn dẹp môi trường cũ ---
echo "[RESET] Đang unmount /mnt..."
umount -R /mnt || true

echo "[RESET] Đang tắt swap và LVM volume group..."
swapoff /dev/vg0/swap || true
vgchange -an vg0 || true

# === THÊM CÁC LỆNH DỌN DẸP LVM Ở ĐÂY ===
echo "[RESET] Đang xóa cấu hình LVM cũ (LV, VG, PV)..."
lvremove -f /dev/vg0/root || true
lvremove -f /dev/vg0/swap || true
vgremove -f vg0 || true
pvremove -f /dev/vda2 || true
# ========================================

echo "[RESET] Dọn dẹp hoàn tất. Chuẩn bị triển khai lại..."
sleep 2

# --- Bước 2: Chạy lại script deploy chính ---
echo
echo "--- GỌI SCRIPT DEPLOY.SH ---"
# Chạy deploy.sh với sudo nếu cần, nhưng vì reset_and_deploy đã chạy với sudo,
# có thể không cần nữa. Để an toàn, cứ để sudo.
sudo ./deploy.sh
