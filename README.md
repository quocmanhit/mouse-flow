# MouseFlow

App thanh menu cho macOS: cuộn mượt và đảo chiều cuộn riêng cho chuột có con lăn nấc, không đụng tới trackpad.

## Chạy

```bash
make run      # build, ký, cài vào ~/Applications và mở app
```

Lần đầu macOS sẽ hỏi quyền Accessibility (System Settings → Privacy & Security → Accessibility).
Sau khi bật, app tự chạy, không cần mở lại.

`open ~/Applications/MouseFlow.app --args --trial` chạy thử 60 giây rồi tự thoát, dùng khi thử bản build mới.
Không chạy cùng Mos hay app cuộn mượt khác: hai event tap giành cùng một sự kiện lăn.

Cần Command Line Tools (Swift 5.10+), macOS 14+. Mặc định ký bằng identity `Apple Development` để quyền
Accessibility không mất sau mỗi lần build; không có thì `make run SIGN_ID=-` (phải cấp lại quyền mỗi lần build).

## Cách hoạt động

- `ScrollEngine` đặt một `CGEventTap` ở tầng annotated session (lúc hệ thống đã chọn app đích). Sự kiện liên
  tục (trackpad, Magic Mouse) được để nguyên; sự kiện từng nấc của chuột bị chặn lại, cộng dồn quãng đường rồi
  phát ra dần theo nhịp màn hình (`CADisplayLink`) với đường cong ease-out.
- Mỗi frame là bản copy của sự kiện gốc gửi thẳng tới app đích bằng `postToPid`. Post lại vào session tap hoặc
  tap sớm hơn (sự kiện chưa có đích) thì app không nhận được.
- Giữ phím cuộn nhanh (mặc định ⌥ Option) để nhân quãng đường; phím này bị gỡ khỏi sự kiện gửi đi để app không
  hiểu thành Option+scroll.
- `ButtonMapper` bắt click con lăn và nút bên hông (button 2–4). Nếu app đang focus (hoặc "Mọi app") có gán phím
  tắt thì nuốt cú click và gửi phím tắt; không gán thì giữ nguyên. Cấu hình ở "Cài đặt nút chuột…" trên menu,
  lưu trong `UserDefaults`. Nút gán cho phím tắt hệ thống (vd Mission Control) phải bỏ gán trong System Settings
  trước, vì macOS xử lý chúng trước event tap.
- Khi không cuộn, display link tạm dừng nên app gần như không dùng CPU.
- Cài đặt (tốc độ, độ mượt, đảo chiều) lưu trong `UserDefaults`.
