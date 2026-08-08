# Troubleshooting macOS

Hướng dẫn xử lý các vấn đề thường gặp khi sử dụng Dấu trên macOS.

## Không gõ được tiếng Việt sau khi cài đặt hoặc update

### Triệu chứng
- App đã được cài đặt/update thành công
- Icon Dấu xuất hiện trên menu bar
- Đã bật Accessibility permissions
- Nhưng vẫn không thể gõ dấu tiếng Việt (ví dụ: `aa` không thành `â`)

### Nguyên nhân
**Event tap chưa được khởi tạo hoặc cần restart** sau khi:
- Cài đặt lần đầu qua Homebrew
- Update version mới qua `brew upgrade`
- Binary bị thay đổi (code signature, entitlements)

Event tap cần được khởi tạo lại để có thể intercept keyboard events từ hệ thống.

### Giải pháp

**Bước 1: Restart app hoàn toàn**
```bash
killall Dau
sleep 1
open -a Dau
```

**Bước 2: Kiểm tra permissions (nếu vẫn không được)**

Mở **System Settings → Privacy & Security → Accessibility**, đảm bảo:
- ✅ **Dau** có trong danh sách
- ✅ Toggle **được bật** (màu xanh)

Nếu chưa có trong danh sách:
1. Nhấn nút **+** (Add)
2. Navigate đến `/Applications/Dau.app`
3. Chọn và thêm vào
4. Bật toggle

Hoặc dùng lệnh nhanh:
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

**Bước 3: Verify app đang chạy**
```bash
ps aux | grep -i "Dau.app" | grep -v grep
```

Kết quả mong đợi:
```
nghialuutrung    92395   0.0  0.4 ... /Applications/Dau.app/Contents/MacOS/Dau
```

**Bước 4: Kiểm tra log (debug mode)**

Nếu vẫn không hoạt động, chạy app từ terminal để xem log:
```bash
killall Dau
/Applications/Dau.app/Contents/MacOS/Dau 2>&1 &
```

Log khi app hoạt động bình thường:
```
[dau] modifier-only hotkey registered globally ⇧⌘
[dau] event-tap: running placement=hid gen=1
[dau] app launched Dấu x.x.x · core x.x.x (TypingSession hot path, TG-00 fail-open)
```

Nếu thấy log trên → app đã sẵn sàng. Thử gõ `aa` trong TextEdit/Notes/Terminal.

### Test nhanh
1. Mở **TextEdit** hoặc **Notes**
2. Chuyển input source sang **ABC** (không dùng Vietnamese input method hệ thống)
3. Gõ: `a` `a` → phải ra `â`
4. Gõ: `d` `d` → phải ra `đ`
5. Gõ: `w` `w` → phải ra `ư`

## Các vấn đề khác

### App không xuất hiện icon trên menu bar
**Nguyên nhân:** App bị crash hoặc chưa chạy.

**Giải pháp:**
```bash
open -a Dau
```

### Toggle hotkey không hoạt động
**Mặc định:** `⇧⌘` (Shift + Command cùng lúc)

**Kiểm tra:**
1. Click icon Dấu trên menu bar
2. Vào **Settings...**
3. Kiểm tra **Toggle Hotkey** có được cấu hình không

### Input source bị blocked
**Triệu chứng:** Menu bar hiển thị "input source blocked"

**Nguyên nhân:** Đang dùng Vietnamese input method của hệ thống (conflict với Dấu)

**Giải pháp:**
1. Chuyển sang **ABC** hoặc **U.S.** input source
2. Tắt Vietnamese input methods trong **System Settings → Keyboard → Input Sources**

## Lấy thông tin debug

Khi báo bug, hãy cung cấp:

**1. Version info:**
```bash
defaults read /Applications/Dau.app/Contents/Info.plist CFBundleShortVersionString
```

**2. Permissions status:**
```bash
# Check Accessibility
tccutil reset Accessibility io.github.hapo-nghialuu.dau
# Sau đó mở lại app để request permission
```

**3. Full log:**
```bash
killall Dau
/Applications/Dau.app/Contents/MacOS/Dau 2>&1 | tee ~/dau-debug.log &
# Thử reproduce vấn đề
# Sau đó gửi file ~/dau-debug.log
```

**4. System info:**
```bash
sw_vers
uname -m
```

## Gỡ cài đặt hoàn toàn

Nếu cần cài đặt lại từ đầu:

```bash
# Stop app
killall Dau

# Uninstall via Homebrew
brew uninstall hapo-nghialuu/tap/dau

# Remove app data
rm -rf ~/Library/Application\ Support/io.github.hapo-nghialuu.dau
rm -rf ~/Library/Preferences/io.github.hapo-nghialuu.dau.plist

# Remove from Accessibility (manual)
# System Settings → Privacy & Security → Accessibility
# Tìm "Dau" và nhấn "-" để xóa

# Reinstall
brew install hapo-nghialuu/tap/dau
open -a Dau
```

---

**Lưu ý quan trọng:** Sau mỗi lần update version mới, **luôn restart app** bằng `killall Dau && open -a Dau` để event tap được khởi tạo lại.
