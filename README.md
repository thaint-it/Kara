# Karaoke Hàng Chờ

App Flutter cho điện thoại **chủ phòng**: ghép với TV một lần, khách quét mã QR
để chọn bài, chủ phòng duyệt, hết bài thì tự phát bài tiếp theo.

Code viết theo [`spec.md`](spec.md). Đọc file đó trước khi sửa gì lớn.

---

## Chạy ở đâu được

| Nền tảng | Làm chủ phòng | Ghi chú |
|---|---|---|
| **Android** | ✅ Tốt nhất | Có foreground service nên khoá màn hình server vẫn chạy |
| **iPhone / iPad** | ⚠️ Được, có giới hạn | iOS không cho chạy server khi màn hình tắt — xem [phần iPhone](#làm-chủ-phòng-bằng-iphone) |
| **Khách** (mọi máy) | — | Chỉ cần trình duyệt, **không cài gì**: iPhone, Android, máy tính đều được |
| macOS / Windows / web | ❌ | `webview_flutter` không có bản desktop; web không có `dart:io` nên không chạy được server |

Máy để **viết code và build** thì Windows hoặc macOS đều được:

- **Windows**: build được Android. Đây là lựa chọn đủ cho hầu hết mọi việc.
- **macOS + Xcode**: build được cả Android và iPhone. Chỉ cần nếu bạn muốn cài lên iPhone.

---

## Dựng máy để build

### Phiên bản Flutter — bản nào cũng được

Code đã viết để **chạy trên cả Flutter 3.24.3 và các bản mới hơn**, bằng cách
tránh hẳn những API đã bị đổi giữa các bản:

| Thay vì | Code này dùng | Vì sao |
|---|---|---|
| `ThemeData.cardTheme` + `Card` | [`KaraCard`](lib/ui/widgets/kara_card.dart) | Kiểu đổi `CardTheme` → `CardThemeData` ở Flutter 3.27 |
| `Color.withOpacity` / `.withValues` | Hằng số ARGB trong `KaraColors` | Hai hàm này đổi tên qua lại giữa các bản |
| `RadioListTile(groupValue:)` | `ListTile` + icon tự vẽ | Bị `RadioGroup` thay thế ở Flutter 3.32 |

Một ngoại lệ có chủ ý: `youtube_explode_dart` **ghim đúng 3.0.0**. Bản 3.0.1+
đòi `path ^1.9.1` trong khi `flutter_test` của Flutter 3.24.3 ghim `path 1.9.0`,
nên 3.0.0 là bản duy nhất chạy được trên cả hai. Khi YouTube đổi giao diện web
làm thư viện hỏng thì nâng dòng đó lên và kiểm tra lại
[youtube_service.dart](lib/services/youtube_service.dart).

### Trên Windows

Cần khoảng **15 GB trống** (hoặc ~10 GB nếu dùng command line tools thay
Android Studio).

| Thứ | Dung lượng |
|---|---|
| Flutter SDK | ~2,8 GB |
| Android Studio (kèm JDK 17 + SDK Manager) | ~7 GB |
| Android SDK: `platform-tools`, `platforms;android-35`, `build-tools;35.0.0` | ~2 GB |
| Cache Gradle ở `%USERPROFILE%\.gradle` (sinh ra ở lần build đầu) | ~3 GB |

Ba chỗ dễ sập riêng của Windows:

- Đặt project **gần gốc ổ**, ví dụ `C:\dev\Kara`. Gradle tạo đường dẫn rất sâu,
  để trong `Documents\...` dễ vượt giới hạn 260 ký tự.
- **Loại project + `%USERPROFILE%\.gradle` + thư mục Flutter khỏi Windows
  Defender.** Không làm thì Gradle build chậm gấp 2–3 lần.
- Bật **Developer Mode** của Windows — Flutter cần để tạo symlink cho plugin.

### Mang project sang máy khác

Source chỉ **~0,9 MB**. Thư mục `build/` và `.dart_tool/` là artifact của máy cũ,
**đừng copy** — `.gitignore` sẵn có đã loại cả hai.

```bash
flutter pub get
flutter test           # 92 test, không cần thiết bị
flutter analyze
flutter run            # cắm điện thoại, bật USB debugging
```

Lần `flutter run` đầu sẽ tải Gradle 8.7 + AGP 8.6, mất khoảng 10 phút.

Điện thoại và TV **phải cùng một WiFi**. Nên dùng **điện thoại thật** — emulator
nằm trong mạng ảo nên khó thử ghép TV và khách quét QR.

---

## Dùng app

Khi app mở, nó in địa chỉ server ra log:

```
Web server khách đang chạy tại http://192.168.1.2:8080
```

Khách mở địa chỉ đó trên trình duyệt (hoặc quét QR ở tab **Phòng**) là chọn bài
được, không cần cài gì.

### Ghép TV

1. Trên TV: app YouTube → **Cài đặt** → **Liên kết với TV bằng mã**.
2. Trong app: tab **Phòng** → **Ghép TV** → nhập 12 số.
3. Token được lưu lại; lần sau mở app là tự kết nối, không phải chọn lại thiết bị phát.

Không có TV thì vào **Cài đặt → Chế độ phát → Phát trên điện thoại này**
(âm thanh ra loa kẹo kéo qua Bluetooth hoặc dây 3.5 mm).

### Một buổi hát kéo dài bao lâu

Đặc tả không nói gì về chuyện này, nên đây là phần thêm. Quy tắc nằm gọn trong
[session_policy.dart](lib/core/session_policy.dart) — logic thuần, có 11 test.

Buổi hát **sống qua việc tắt/mở app**: hàng chờ, yêu cầu chờ duyệt, danh sách
khách đều được lưu xuống file, mở lại là còn nguyên. Bài đang hát lúc tắt app
được đưa về đầu hàng chờ để hát lại từ đầu.

Buổi hát **kết thúc** khi một trong ba điều sau:

| Mốc | Mặc định | Đổi được ở |
|---|---|---|
| Không có bài nào được phát và không ai gửi yêu cầu | 6 giờ | Cài đặt → Buổi hát (3 / 6 / 12 giờ / Không) |
| TV mất kết nối liên tục **và** hàng chờ đã trống | 2 giờ | — |
| Chủ phòng bấm **"Kết thúc buổi hát"** | — | Cài đặt → Buổi hát |

Cố ý **không** kết thúc ngay khi TV mất kết nối: đặc tả mục 12 yêu cầu giữ
nguyên hàng chờ khi TV tắt hoặc đổi WiFi giữa chừng, và thực tế thì TV tắt vài
phút giữa buổi là chuyện bình thường (có người đi vệ sinh, WiFi chớp một nhịp,
ai đó bấm đổi cổng HDMI). Vì vậy TV chỉ góp phần đóng buổi hát khi nó mất kết
nối rất lâu *và* không còn bài nào chờ.

Khi buổi hát kết thúc:

- **Xoá**: hàng chờ, yêu cầu chờ duyệt, bài đang hát, khách lạ, và các mục bị
  bỏ qua / từ chối trong lịch sử.
- **Giữ**: cài đặt, token TV, lịch sử **Đã hát** (để bấm "Hát lại"), và những
  khách đã được **"tin tưởng"** — người nhà thì không nên phải tick lại mỗi buổi.
- **Sinh mã phòng 4 số mới**, nên ảnh QR ai chụp từ buổi trước không dùng được
  nữa. Khách đang mở trang sẽ thấy ngay màn hình *"Buổi hát đã kết thúc — quét
  lại mã QR"* thay vì nhận lỗi 403 không hiểu vì sao.

### Làm chủ phòng bằng iPhone

Cài và chạy được bình thường, cả hai chế độ phát. Đã xử lý riêng cho iOS:

- **WKWebView** được tạo với `allowsInlineMediaPlayback: true` và
  `mediaTypesRequiringUserAction: {}` — nếu không, iOS đẩy video sang trình phát
  toàn màn hình của hệ thống và app mất quyền điều khiển. Hai thiết lập này
  **phải đặt lúc tạo WebView**, không sửa được sau.
- `Info.plist` có `NSAllowsLocalNetworking` (server và trang phát đều chạy trên
  `http://` nội bộ) và `NSLocalNetworkUsageDescription`.
- Deployment target 13.0.

**Giới hạn thật, không phải lỗi app:** iOS không cho app chạy web server khi màn
hình đã tắt. Nên:

- App **tự giữ màn hình sáng** suốt lúc đang hát (trên Android chỉ giữ ở chế độ
  phát trên điện thoại, vì Android có foreground service).
- Tab **Cài đặt** hiện sẵn ghi chú nhắc chuyện này cho chủ phòng.
- Khoá máy hoặc chuyển app lâu thì khách mất kết nối và phải quét lại mã QR.
- Muốn ổn định cả buổi 3 tiếng thì dùng Android làm chủ phòng; iPhone vẫn làm
  khách bình thường.

**Để cài lên iPhone** cần máy Mac + Xcode. Với Apple ID miễn phí, app hết hạn sau
**7 ngày** và phải cắm máy cài lại; muốn 1 năm thì cần Apple Developer Program.

---

## Bản đồ code

```
lib/
  lounge/                     Giao thức YouTube Lounge (API không chính thức)
    browser_channel.dart        Phân tích luồng "BrowserChannel" của /bc/bind
    lounge_events.dart          nowPlaying / onStateChange / onAdStateChange…
    tv_controller.dart          Ghép mã, mở phiên, nghe sự kiện, gửi lệnh
  player/
    playback_target.dart        Giao diện chung cho hai chế độ phát
    tv_playback_target.dart     Phát qua app YouTube trên TV
    phone_playback_target.dart  Phát trong WebView bằng IFrame Player API
    auto_advance.dart           Bộ lọc sự kiện "hết bài" (mục 7.4)
  core/
    room_controller.dart        Toàn bộ trạng thái phòng: hàng chờ, duyệt, phát
    session_policy.dart         Khi nào một buổi hát được coi là đã tàn
  server/
    guest_server.dart           Web server nhúng: trang khách + REST + WebSocket
    rate_limiter.dart           10 yêu cầu / phút / khách
  services/
    youtube_service.dart        Tìm kiếm + gợi ý + cache 10 phút
    storage_service.dart        Cài đặt, token TV, hàng chờ, lịch sử
    room_service_keeper.dart    Foreground service (chỉ Android)
  models/                     Song, QueueItem, Guest, RoomSettings
  ui/                         App chủ phòng (5 tab)

assets/web/                   Trang khách (HTML/CSS/JS thuần) + trang trình phát
  index.html  styles.css  app.js
  player.html                 Trình phát nhúng, server phục vụ tại /player
```

### Ba chỗ cần biết trước khi sửa

**1. `lounge/` là phần dễ vỡ nhất.** Lounge API không chính thức, logic được port
từ thư viện Python `pyytlounge` v3.4. Khi YouTube đổi giao thức thì chỉ phải sửa
trong thư mục này — `RoomController` không biết gì về HTTP của YouTube.

Một chỗ cố ý làm khác `pyytlounge`: `browser_channel.dart` **bỏ qua con số độ dài
khối** mà YouTube gửi kèm, và quét mảng JSON cân ngoặc thay vì đếm ký tự. Con số
đó đếm theo byte hay theo ký tự là chuyện không chắc chắn, và tiêu đề tiếng Việt
có dấu làm hai cách đếm lệch nhau.

**2. `auto_advance.dart` giải quyết một vấn đề thật.** Cả TV và IFrame API đều bắn
`state == 0` khá bừa: sự kiện của bài cũ đến sau khi đã gửi bài mới, hoặc bắn
nhiều lần liền nhau. Tin ngay thì hàng chờ nhảy mất mấy bài một lúc. Ba cửa chặn
(8 giây sau khi gửi bài / chưa tới cuối bài / 5 giây chống lặp) đều có test.

**3. Trình phát nhúng cần một origin `http://` thật.** YouTube IFrame API không
chạy với `about:blank`, nên `loadHtmlString` không dùng được. Vì vậy trang phát
do chính web server nhúng phục vụ tại `/player`, và WebView nạp nó từ
`http://127.0.0.1:<port>/player` (dùng loopback chứ không dùng IP WiFi để không
chết khi mất mạng hoặc khi IP đổi).

Thêm một chỗ dễ hiểu sai: **giao diện tìm bài là UI tự vẽ**, không nhúng YouTube.
Có hai bản cài đặt riêng — Flutter cho app chủ ([search_tab.dart](lib/ui/tabs/search_tab.dart)
+ [song_tile.dart](lib/ui/widgets/song_tile.dart)) và HTML/JS cho trang khách
(`songCard()` trong [app.js](assets/web/app.js)). Đổi cách trình bày ở một bên thì
phải sửa bên kia cho khớp.

---

## Tình trạng theo các mốc ở mục 10 của đặc tả

| Mốc | Nội dung | Tình trạng |
|---|---|---|
| **M1** | Module TV: ghép mã, lưu token, phát, nghe hết bài, tắt autoplay | Code xong — **chưa thử trên TV thật** |
| **M2** | Hàng chờ chủ phòng: tìm, thêm, sắp xếp, điều khiển, lưu khi tắt app | Code xong, có test |
| **M3** | Phát trên điện thoại, xử lý video chặn nhúng, đổi chế độ giữa chừng | Code xong — chưa thử trên máy thật |
| **M4** | Web server, QR, trang khách, WebSocket, luồng yêu cầu → duyệt | Code xong, có test API |
| **M5** | Gợi ý, cuộn vô hạn, dán link, công tắc karaoke, xem trước 15 giây | Code xong |
| **M6** | Foreground service, tự kết nối lại, giới hạn bài/khách, lịch sử, giao diện tối | Code xong, **trừ "Yêu thích theo từng khách"** |

**Yêu thích theo từng khách** chưa làm — đặc tả đã ghi là "(Mốc sau)" ở mục 5.5.

### Những gì chưa được kiểm chứng

Máy viết code này **không có Android SDK và không có Xcode**, nên chưa build được
lần nào — cả `flutter build apk` lẫn `flutter build ios`. Những thứ sau chỉ đúng
trên giấy:

- Bản Gradle / AGP / Kotlin đã nâng (8.7 / 8.6.0 / 1.9.22) cho
  `flutter_foreground_task` 9.x, `compileSdk` 35, `minSdk` 23.
- Khai báo foreground service và các quyền trong `AndroidManifest.xml`.
- Cấu hình iOS: `Info.plist`, deployment target 13.0, và thiết lập WKWebView.
- Toàn bộ đường đi qua TV thật và qua WebView thật.

`flutter analyze` sạch và **92 test pass** trên Flutter 3.24.3, nhưng đó là kiểm
tra kiểu và logic thuần. Việc đầu tiên nên làm trên máy mới là
`flutter build apk --debug`.

---

## Kiểm tra theo mục 14 của đặc tả

Checklist này phải tự tay thử, test tự động không thay được:

- [ ] Ghép TV bằng mã một lần; tắt app mở lại tự kết nối.
- [ ] 3 khách cùng WiFi quét QR, gửi yêu cầu mà không cài app.
- [ ] Chủ phòng nhận rung + badge, duyệt / ưu tiên / từ chối; khách thấy đổi trạng thái trong 2 giây.
- [ ] Hết bài tự chuyển, TV không phát video gợi ý.
- [ ] Bấm chọn bài khi đang hát không cắt ngang bài đang hát.
  *(có test tự động: `test/room_controller_test.dart`)*
- [ ] Chế độ phát trên điện thoại hát liên tục khi không có TV.
- [ ] Tìm kiếm có gợi ý, cuộn thêm kết quả, dán link được.

---

## Lưu ý

- **Lounge API không chính thức.** Có thể ngừng hoạt động khi YouTube cập nhật, và
  có thể vi phạm điều khoản YouTube nếu phát hành thương mại. Phù hợp dùng cá nhân.
  Nếu cần đường chính thức thì dùng chế độ phát trên điện thoại / TV box
  (YouTube IFrame API).
- **Không tải video về máy**, chỉ phát qua YouTube.
- Nếu `flutter pub get` báo xung đột phiên bản `webview_flutter_*`, nâng hai dòng
  `webview_flutter_android` / `webview_flutter_wkwebview` theo đúng số mà pub gợi ý —
  chúng được khai báo thẳng chỉ để đặt cấu hình riêng cho từng nền tảng.
