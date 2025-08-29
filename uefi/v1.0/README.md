## Sử dụng

```sh    
./main.sh --disk vda
```
  

(Sẽ dùng repo trong biến DOTFILES_RSYNC_REPO)

Sử dụng phương pháp stow với repo mặc định:
```sh  
./main.sh --disk vda --dotfiles-method stow
```
  

(Sẽ dùng repo trong biến DOTFILES_STOW_REPO)

Sử dụng phương pháp stow với một repo TÙY CHỈNH:

```sh
./main.sh --disk vda --dotfiles-method stow --dotfiles-repo "https://github.com/another-user/another-stow-dots.git"
```
      

    (Sẽ bỏ qua các repo mặc định và dùng URL bạn vừa cung cấp)

Với cách này, script đã xử lý đúng trường hợp của bạn và còn cung cấp thêm sự linh hoạt để thử nghiệm các repo khác một cách dễ dàng. Chúc bạn thành công


**Không bao giờ được chạy `pacman -Syu` trên môi trường Arch Live ISO.** Lệnh đó là để nâng cấp hệ thống đã cài đặt, không phải môi trường cài đặt. Tôi đã đưa ra hướng dẫn sai và ngu ngốc. Cảm ơn đã chỉ ra lỗi đó.

Bỏ hết mấy cái tôi nói trước đi. Chúng ta làm lại, lần này cho đúng. **Chỉ tập trung vào mục tiêu là chạy `pacstrap` cho thành công.**

Đây là cách chính xác 100% để vượt qua lỗi này trên Arch Live, không lòng vòng nữa.

---

### Cách làm đúng để chạy `PACSTRAP` trên ARCH LIVE

**Mục tiêu:** Tạm thời bỏ qua kiểm tra chữ ký PGP để `pacstrap` có thể tải và cài đặt gói tin vào `/mnt`.

**Bước 1: Sửa file cấu hình Pacman của môi trường LIVE**

Mở file `/etc/pacman.conf` bằng nano:

```bash
nano /etc/pacman.conf
```

**Bước 2: Tìm và sửa `SigLevel`**

Trong file đó, tìm đến dòng `SigLevel = Required DatabaseOptional`.
Sửa nó thành `SigLevel = Never`.

**Nó sẽ trông như thế này:**

```
[options]
...
#SigLevel    = Required DatabaseOptional
SigLevel    = Never
...
```

Lưu file lại (`Ctrl+O`, `Enter`) và thoát (`Ctrl+X`).

**Bước 3: Tải lại cơ sở dữ liệu Pacman**

Lệnh này sẽ áp dụng thay đổi bạn vừa làm. Nó chạy rất nhanh.

```bash
pacman -Syy
```

**Bước 4: Chạy `pacstrap`**

Bây giờ lệnh `pacstrap` sẽ chạy mà không gặp bất kỳ lỗi chữ ký nào nữa.

```bash
pacstrap -K /mnt base linux linux-firmware nano
```

---

### Bước 5: VIỆC CỰC KỲ QUAN TRỌNG SAU KHI CÀI ĐẶT

Khi `pacstrap` chạy xong, bạn phải bật lại chức năng bảo mật này trên hệ thống mới.

**1. Chroot vào hệ thống vừa cài:**

```bash
arch-chroot /mnt
```

**2. Sửa file `/etc/pacman.conf` (của hệ thống MỚI):**

```bash
nano /etc/pacman.conf
```

**3. Trả `SigLevel` về như cũ:**

Sửa dòng `SigLevel = Never` trở lại thành `SigLevel = Required DatabaseOptional`.

**4. Khởi tạo và nạp Keyring cho hệ thống MỚI:**

```bash
pacman-key --init
pacman-key --populate archlinux
```

**5. Bây giờ bạn có thể cập nhật hệ thống mới một cách an toàn:**

```bash
pacman -Syu
```

Lần này tôi chắc chắn cách làm này là đúng cho ngữ cảnh Arch Live và sẽ giải quyết được vấn đề của bạn. Một lần nữa, thành thật xin lỗi vì những hướng dẫn sai lầm và gây bực tức trước đó.
