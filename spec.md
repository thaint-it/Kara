# Karaoke Hàng Chờ – Đặc tả ứng dụng

> Tài liệu này dùng để đưa vào VS Code (cho bạn hoặc trợ lý AI như Copilot / Claude Code) làm căn cứ viết code.
> Viết theo thứ tự các mốc ở mục 10, làm xong mốc nào kiểm tra mốc đó trên TV thật.

---

## 1. Vấn đề cần giải quyết

- Hát karaoke bằng YouTube trên TV + loa kẹo kéo rất phổ biến ở Việt Nam.
- Khi chọn bài bằng điện thoại qua "Kết nối với TV" của YouTube:
  - Mỗi lần chọn bài phải **chọn lại thiết bị phát là TV**, rất dễ nhầm, phát nhầm ra điện thoại.
  - Bấm vào bài là **phát ngay, cắt ngang người đang hát**; hàng đợi của YouTube khó dùng, hay mất.
  - Nhiều người cùng chọn bài thì lộn xộn, không ai kiểm soát.
- TV đời cũ không hỗ trợ (hoặc hỗ trợ kém) tìm bài bằng giọng nói.

## 2. Mục tiêu

1. **Một điện thoại chủ phòng** kết nối với TV **một lần**, sau đó không ai phải chọn thiết bị phát nữa.
2. **Nhiều điện thoại khác cùng WiFi** tìm bài và **gửi yêu cầu** chọn bài.
3. **Chủ phòng duyệt** yêu cầu trước khi bài vào hàng chờ.
4. Hết bài thì **tự phát bài tiếp theo**.
5. Hai chế độ phát:
   - **Phát trên TV**: điều khiển app YouTube có sẵn trên Smart TV qua WiFi.
   - **Phát trên điện thoại**: khi không có TV, phát ngay trên điện thoại chủ phòng (âm thanh ra loa kẹo kéo qua Bluetooth hoặc dây).
6. **Tìm bài giống trên YouTube**: gợi ý khi gõ, kết quả có ảnh, tên kênh, lượt xem, thời lượng, cuộn xuống để xem thêm.

## 3. Vai trò người dùng

| Vai trò | Thiết bị | Quyền |
|---|---|---|
| **Chủ phòng** (host) | Điện thoại cài app | Ghép nối TV, chọn chế độ phát, duyệt / từ chối yêu cầu, sắp xếp hàng chờ, điều khiển phát (dừng, qua bài, âm lượng), thêm bài trực tiếp không cần duyệt |
| **Khách** (guest) | Điện thoại bất kỳ, **không cần cài app**, chỉ quét mã QR mở trình duyệt | Tìm bài, gửi yêu cầu, xem hàng chờ, xem trạng thái yêu cầu của mình |

Tuỳ chọn trong Cài đặt của chủ phòng:
- **Tự động duyệt**: bật thì mọi yêu cầu vào thẳng hàng chờ.
- **Tin tưởng khách này**: yêu cầu của người đó tự duyệt.
- **Cho khách điều khiển**: khách được bấm Qua bài / Tạm dừng (mặc định tắt).
- **Giới hạn số bài đang chờ mỗi khách** (mặc định 3) để tránh một người chiếm hết hàng chờ.

## 4. Kiến trúc

```
                      WiFi nội bộ (cùng mạng)
┌──────────────┐   HTTP + WebSocket    ┌──────────────────────────────┐
│ Khách 1..n   │ ────────────────────> │  ĐIỆN THOẠI CHỦ PHÒNG (app)   │
│ (trình duyệt)│ <──── cập nhật ────── │  - Web server nhúng (cổng 8080)│
└──────────────┘                       │  - Hàng chờ + duyệt bài        │
                                       │  - Tìm kiếm YouTube           │
                                       │  - Bộ phát (1 trong 2):       │
                                       │     a) TV  ──Lounge API──┐    │
                                       │     b) Trình phát nhúng  │    │
                                       └──────────────────────────┼────┘
                                                                  ▼
                                               App YouTube trên Smart TV ──> Loa kẹo kéo
```

- **Chủ phòng là "máy chủ"**: giữ toàn bộ trạng thái (hàng chờ, yêu cầu, khách). Không cần máy chủ trên Internet.
- **Khách** mở `http://<IP điện thoại chủ>:8080` (hiện bằng mã QR trên app chủ phòng).
- **TV chỉ phát video**, không giữ hàng chờ. App tự gửi bài kế tiếp khi TV báo hết bài.

### Công nghệ đề xuất

| Phần | Công nghệ | Ghi chú |
|---|---|---|
| App chủ phòng | **Flutter** (Android trước, iOS sau) | iOS hạn chế chạy server khi app ở nền |
| Web server nhúng | `shelf`, `shelf_router`, `shelf_web_socket`, `shelf_static` | Phục vụ trang web cho khách + API |
| Trang web khách | HTML/CSS/JS thuần (hoặc Svelte/Preact build ra file tĩnh), đóng gói trong assets của app | Không cần cài app |
| Tìm kiếm YouTube | `youtube_explode_dart` (không cần API key) | Dự phòng: YouTube Data API v3 (cần key, có giới hạn lượt/ngày) |
| Gợi ý khi gõ | `https://suggestqueries.google.com/complete/search?client=youtube&ds=yt&hl=vi&q=...` | Gọi từ app chủ, trả lại cho khách |
| Điều khiển TV | Tự viết module Dart theo **YouTube Lounge API** (xem mục 7) | Tham khảo thư viện Python `pyytlounge` v3.x |
| Phát trên điện thoại | `youtube_player_iframe` hoặc `webview_flutter` + YouTube IFrame Player API | |
| Lưu trữ | `shared_preferences` (cài đặt, token TV), `hive` hoặc file JSON (hàng chờ, lịch sử) | |
| Giữ màn hình sáng | `wakelock_plus` | Chế độ phát trên điện thoại |
| Mã QR | `qr_flutter` | |
| Lấy IP WiFi | `network_info_plus` | |
| Chạy nền (Android) | Foreground service (`flutter_foreground_task`) | Để server không bị tắt khi khoá màn hình |

## 5. Luồng chức năng

### 5.1 Mở phòng (chủ phòng)
1. Mở app → chọn **Chế độ phát**: `TV` hoặc `Điện thoại này`.
2. Nếu chọn TV và chưa ghép nối: hướng dẫn *YouTube trên TV → Cài đặt → Liên kết với TV bằng mã* → nhập mã 12 số → lưu lại để lần sau tự kết nối.
3. App bật web server, hiện **mã QR + địa chỉ** để khách quét.
4. Có thể đổi chế độ phát giữa chừng (TV ⇄ điện thoại); bài đang phát được phát tiếp ở thiết bị mới từ đầu.

### 5.2 Khách chọn bài
1. Quét QR → nhập tên (lưu trong trình duyệt, lần sau không hỏi lại).
2. Tìm bài (giống YouTube) → bấm **"Yêu cầu bài này"**.
3. Thấy trạng thái trong tab **"Bài của tôi"**: `Chờ duyệt` → `Trong hàng chờ (vị trí N)` → `Đang hát` → `Đã hát`, hoặc `Bị từ chối`.

### 5.3 Chủ phòng duyệt
- Yêu cầu mới → app **rung + hiện badge** ở tab "Chờ duyệt".
- Mỗi yêu cầu có 3 nút: **Thêm cuối hàng**, **Ưu tiên** (hát ngay sau bài hiện tại), **Từ chối**.
- Có nút **Duyệt tất cả**.
- Bài trùng (đã có trong hàng chờ) được đánh dấu để chủ phòng biết.

### 5.4 Hàng chờ & phát
- Chủ phòng: kéo thả đổi thứ tự, đưa lên đầu, xoá, xoá hết.
- Đang không có bài nào mà có bài mới được duyệt → **phát ngay**.
- Hết bài → **tự phát bài kế tiếp**; hết hàng chờ thì dừng (không để YouTube tự phát video gợi ý).
- Điều khiển: Tạm dừng / Phát, **Qua bài** (có hỏi xác nhận), Hát lại từ đầu, Âm lượng, Bỏ quảng cáo (khi TV báo có quảng cáo bỏ qua được).
- Thanh "**Tiếp theo: Anh Tuấn – Hoa nở về đêm**" hiện trên app chủ và trang khách.

### 5.5 Lịch sử & yêu thích
- Tab **Đã hát** (50 bài gần nhất), bấm để yêu cầu lại.
- (Mốc sau) Yêu thích theo từng khách.

## 6. Tìm kiếm "giống YouTube"

- **Gợi ý khi gõ** (debounce 250 ms) từ API gợi ý của YouTube.
- **Kết quả**: ảnh thu nhỏ 16:9, thời lượng đè góc ảnh, tiêu đề 2 dòng, tên kênh, lượt xem, thời gian đăng.
- **Cuộn vô hạn**: tải trang kế tiếp khi cuộn gần cuối (`youtube_explode_dart` hỗ trợ `nextPage`).
- **Dán link YouTube** vào ô tìm kiếm → hiện đúng video đó.
- **Công tắc "Ưu tiên bản karaoke"** (mặc định bật): tự thêm chữ `karaoke` vào từ khoá nếu người dùng chưa gõ `karaoke`/`beat`. Tắt đi thì tìm y hệt YouTube.
- Lọc bỏ: livestream, Shorts, playlist/kênh (chỉ giữ video).
- **Xem trước** (tuỳ chọn): bấm ảnh để nghe thử 15 giây ngay trên điện thoại của người đó, không ảnh hưởng bài đang hát.
- Khách không tự gọi YouTube (vướng CORS) → mọi tìm kiếm đi qua app chủ: `GET /api/search`.
- Cache kết quả tìm kiếm 10 phút để đỡ gọi lặp.

## 7. Điều khiển app YouTube trên TV (Lounge API)

> ⚠️ **API không chính thức**, do cộng đồng phân tích. YouTube có thể thay đổi bất cứ lúc nào. Viết thành một module riêng (`tv_controller.dart`) có interface rõ ràng để dễ sửa.
> **Tài liệu tham khảo chính:** mã nguồn `pyytlounge` (PyPI / GitHub), file `wrapper.py`, `events.py`, `models.py`. Port logic sang Dart.

### 7.1 Các bước chính (base URL: `https://www.youtube.com/api/lounge`)

| Bước | Endpoint | Dữ liệu |
|---|---|---|
| Ghép nối bằng mã | `POST /pairing/get_screen` | `pairing_code=<12 số>` → trả `screen.screenId`, `screen.loungeToken`, `screen.name` |
| Làm mới token (lần sau) | `POST /pairing/get_lounge_token_batch` | `screen_ids=<screenId>` |
| Kiểm tra TV online | `POST /pairing/get_screen_availability` | `lounge_token=<token>` |
| Mở phiên / nhận sự kiện / gửi lệnh | `/bc/bind` | Giao thức kiểu "BrowserChannel": lấy `SID`, `gsessionid`, giữ một request GET dài để nhận sự kiện, gửi lệnh bằng POST |

### 7.2 Lệnh cần dùng (`req0__sc`)
- `setPlaylist` với `videoId` → phát bài
- `play`, `pause`, `next`, `previous`
- `seekTo` (`newTime`)
- `setVolume` (`volume` 0–100)
- `setAutoplayMode` = `DISABLED` → **tắt tự phát video gợi ý** (gửi ngay sau khi kết nối)
- `skipAd`

### 7.3 Sự kiện cần nghe
- `nowPlaying`: `videoId`, `currentTime`, `duration`, `state`
- `onStateChange`: `currentTime`, `duration`, `state`
  - `state`: `-1` dừng, **`0` kết thúc**, `1` đang phát, `2` tạm dừng, `3` đang tải, `5` sẵn sàng, `1081` quảng cáo
- `onVolumeChanged`, `onAdStateChange`, `loungeScreenDisconnected`

### 7.4 Logic tự chuyển bài (quan trọng)
```
Khi nhận state == 0 (kết thúc):
  - Bỏ qua nếu bài mới được gửi < 8 giây trước (sự kiện cũ đến trễ)
  - Bỏ qua nếu currentTime < duration - 5 (không thật sự hết bài)
  - Bỏ qua nếu vừa chuyển bài < 5 giây trước (chống lặp)
  - Ngược lại: chuyển bài hiện tại vào Lịch sử, phát bài đầu hàng chờ
```
- Nếu `nowPlaying.videoId` khác bài app đang phát (ai đó dùng điều khiển TV / app YouTube chọn bài khác): **không giành lại**, hiện cảnh báo trên app chủ "TV đang phát bài ngoài hàng chờ" kèm nút "Quay lại hàng chờ".

### 7.5 Kết nối lại
- Vòng lặp: làm mới token → mở phiên → nghe sự kiện; rớt thì chờ 5 giây thử lại.
- Trạng thái hiện trên app: `Chưa ghép` / `Đang kết nối` / `Đã kết nối – <tên TV>` / `Mất kết nối`.
- Lưu `screenId`, `refreshToken`, tên TV vào bộ nhớ máy; có nút "Quên TV này / Ghép TV khác".

## 8. Phát trên điện thoại (không có TV)

- Màn hình phát toàn màn hình, xoay ngang, giữ sáng màn hình.
- Dùng YouTube IFrame Player API trong WebView; nghe sự kiện `onStateChange` (`0` = hết bài) để chuyển bài.
- Âm thanh ra loa kẹo kéo qua **Bluetooth** hoặc dây 3.5 mm.
- **Video bị chặn nhúng** (lỗi `101` / `150`): tự bỏ qua, báo cho chủ phòng và người đã chọn bài ("Bài này không phát được ngoài YouTube, đã bỏ qua"). Khi tìm kiếm ở chế độ này, đánh dấu trước những video không nhúng được nếu lấy được thông tin.
- Trong khi đang phát toàn màn hình, chủ phòng vẫn mở được bảng duyệt bài dạng nổi (overlay/bottom sheet) mà không dừng video.
- (Tuỳ chọn) Chiếu màn hình điện thoại lên TV đời cũ không có YouTube: dùng chế độ này + cáp HDMI/MHL hoặc Screen Mirroring.

## 9. API nội bộ (app chủ phục vụ cho khách)

### REST
| Method | Đường dẫn | Mô tả |
|---|---|---|
| GET | `/` | Trang web khách |
| GET | `/api/state` | Trạng thái đầy đủ (dùng khi mới vào) |
| GET | `/api/suggest?q=` | Gợi ý từ khoá |
| GET | `/api/search?q=&page=&karaoke=1` | Kết quả tìm kiếm |
| POST | `/api/request` | `{guestId, name, song}` → tạo yêu cầu |
| POST | `/api/request/cancel` | Khách huỷ yêu cầu của mình (khi còn `Chờ duyệt`) |
| POST | `/api/control` | Chỉ khi chủ phòng bật "Cho khách điều khiển" |

### WebSocket `/ws`
- Server → client: `state` (hàng chờ, bài đang phát, tiến độ, trạng thái TV), `request_update` (trạng thái yêu cầu của chính khách đó), `toast`.
- Client → server: `hello {guestId, name}`, `ping`.
- Cập nhật tiến độ bài hát mỗi 1 giây; còn lại chỉ gửi khi có thay đổi.

### Mô hình dữ liệu
```text
Song        { videoId, title, channel, durationSec, thumbUrl, viewCount?, publishedText? }
Guest       { id (uuid sinh ở trình duyệt), name, trusted: bool, lastSeen }
QueueItem   { uid, song, requestedBy: {guestId, name}, status, createdAt, approvedAt?, playedAt? }
              status: pending | queued | playing | played | rejected | skipped | cancelled
RoomState   { mode: tv|phone, tv: {status, name, volume, playerState, position, duration},
              current: QueueItem?, queue: QueueItem[], pending: QueueItem[], history: QueueItem[],
              settings: {autoApprove, guestControl, maxPendingPerGuest, preferKaraoke} }
```

### Bảo mật cơ bản
- Chỉ phục vụ trong mạng nội bộ; khi mở phòng tạo **mã phòng 4 số** gắn vào QR (`?room=1234`), thiếu mã thì không gửi yêu cầu được.
- Giới hạn tần suất: tối đa 10 yêu cầu / phút / khách.
- Escape toàn bộ tiêu đề video khi hiển thị trên trang web.

## 10. Lộ trình làm (mốc)

| Mốc | Nội dung | Xong khi |
|---|---|---|
| **M1 – Thử TV** | Module `tv_controller.dart`: ghép bằng mã, lưu token, phát 1 video, nghe sự kiện hết bài, tắt autoplay | Trên TV thật: phát bài A, hết bài tự phát bài B mà không chạm điện thoại |
| **M2 – Hàng chờ chủ phòng** | Màn hình chủ: tìm bài, thêm, sắp xếp, điều khiển, tự chuyển bài, lưu hàng chờ khi tắt app | Hát liên tục 5 bài chỉ với app chủ |
| **M3 – Phát trên điện thoại** | Chế độ phát nhúng, xử lý video chặn nhúng, đổi chế độ giữa chừng | Không có TV vẫn hát liên tục được |
| **M4 – Khách & duyệt bài** | Web server nhúng, QR, trang khách, WebSocket, luồng yêu cầu → duyệt | 3 điện thoại khách cùng gửi bài, chủ duyệt, đúng thứ tự |
| **M5 – Tìm kiếm như YouTube** | Gợi ý, cuộn vô hạn, dán link, công tắc karaoke, xem trước | Trải nghiệm tìm gần giống app YouTube |
| **M6 – Hoàn thiện** | Foreground service, tự kết nối lại, giới hạn bài/khách, lịch sử, yêu thích, giao diện tối | Dùng một buổi tối 3 tiếng không lỗi |

## 11. Giao diện

### App chủ phòng (tab dưới)
1. **Phòng**: thẻ "Đang hát" (ảnh, tên bài, người hát, thanh tiến độ), nút điều khiển to, dòng "Tiếp theo", mã QR thu gọn (bấm để phóng to cho khách quét), trạng thái TV.
2. **Chờ duyệt** (có badge số lượng): danh sách yêu cầu + 3 nút.
3. **Hàng chờ**: kéo thả, vuốt để xoá.
4. **Tìm bài**: như mục 6, nút "Thêm" / "Ưu tiên".
5. **Cài đặt**: chế độ phát, TV đã ghép, các tuỳ chọn ở mục 3.

### Trang web khách (tab dưới)
1. **Tìm bài** – nút "Yêu cầu".
2. **Bài của tôi** – trạng thái từng yêu cầu, vị trí trong hàng.
3. **Hàng chờ** – chỉ xem.

Yêu cầu chung: tiếng Việt, giao diện tối (phòng hát thường tắt đèn), nút to dễ bấm khi cầm mic, chữ tối thiểu 15px, hoạt động tốt trên màn hình 360px.

## 12. Tình huống cần xử lý

- TV tắt / đổi WiFi giữa chừng → giữ nguyên hàng chờ, tự kết nối lại, phát tiếp bài đang dở khi TV online.
- Điện thoại chủ khoá màn hình → server vẫn chạy (foreground service, có thông báo thường trực).
- IP điện thoại chủ thay đổi → cập nhật QR; khách bị mất kết nối thấy thông báo "Quét lại mã QR".
- Quảng cáo trên TV → hiện nút "Bỏ quảng cáo" khi có thể; không tính quảng cáo là hết bài.
- Người khác dùng remote TV đổi bài → mục 7.4.
- Khách đóng trình duyệt → yêu cầu vẫn giữ, mở lại thấy (dựa vào `guestId` lưu trong trình duyệt).
- Mất Internet → báo "Không có Internet" ở ô tìm kiếm; hàng chờ vẫn hiển thị.

## 13. Rủi ro & lưu ý

- **Lounge API không chính thức**: có thể ngừng hoạt động khi YouTube cập nhật; có thể vi phạm điều khoản YouTube nếu phát hành thương mại. Phù hợp dùng cá nhân; nếu phát hành, cân nhắc kỹ và chuẩn bị phương án dùng YouTube IFrame API chính thức (chế độ phát trên điện thoại / TV box).
- `youtube_explode_dart` dựa trên dữ liệu web YouTube, thỉnh thoảng hỏng khi YouTube đổi giao diện → cập nhật thư viện; có YouTube Data API làm dự phòng.
- **Không tải video về máy**, chỉ phát qua YouTube.
- iOS: không chạy được server khi app ở nền lâu → Android là nền tảng chính cho máy chủ phòng; iPhone vẫn làm khách bình thường.

## 14. Tiêu chí nghiệm thu bản đầu tiên

- [ ] Ghép TV bằng mã một lần; tắt app mở lại tự kết nối, không phải chọn thiết bị phát.
- [ ] 3 khách cùng WiFi quét QR, gửi yêu cầu mà không cài app.
- [ ] Chủ phòng nhận thông báo, duyệt / ưu tiên / từ chối; khách thấy trạng thái thay đổi trong vòng 2 giây.
- [ ] Hết bài tự chuyển, không phát video gợi ý của YouTube.
- [ ] Bấm chọn bài khi đang hát **không bao giờ** cắt ngang bài đang hát.
- [ ] Chế độ phát trên điện thoại hát liên tục được khi không có TV.
- [ ] Tìm kiếm có gợi ý, cuộn thêm kết quả, dán link được.