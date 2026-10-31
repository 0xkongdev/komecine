# KomeCine

Ứng dụng iPhone SwiftUI xem phim qua KKPhim và backend Cloudflare Workers/D1.

## Chạy iOS

Mở `ios/KomeCine/KomeCine.xcodeproj` trong Xcode. Chọn simulator iPhone hoặc cấu hình Signing & Capabilities để chạy trên máy thật. App có thể duyệt danh mục và lưu lịch sử/yêu thích cục bộ ngay khi chưa có backend.

### Cấu hình tài khoản Google

1. Tạo Google OAuth client loại iOS cho bundle ID của app và client web/server trong cùng Google Cloud project.
2. Sao chép `ios/KomeCineConfig.example.plist` thành `ios/KomeCine/KomeCine/KomeCineConfig.plist`, điền `GoogleClientID`, `GoogleServerClientID` và URL HTTPS của Worker. File cấu hình bị gitignore.
3. Trong target KomeCine → Info → URL Types, thêm URL scheme là iOS client ID đảo ngược (`com.googleusercontent.apps.…`) theo hướng dẫn Google Sign-In. Cấu hình Signing & Capabilities nếu chạy máy thật.
4. Cấu hình và triển khai backend theo [`backend/README.md`](backend/README.md). Khi file config hợp lệ, app sử dụng Worker cho danh mục, đăng nhập và đồng bộ; khi chưa cấu hình, app lấy dữ liệu trực tiếp từ KKPhim.

Không lưu Google client secret trong ứng dụng iOS. Các client Google đã được tạo và URL scheme của client iOS đã được thêm. Cấu hình iOS cục bộ đã trỏ đến Worker infra; `ios/KomeCineConfig.pending.plist` chứa client ID và địa chỉ Worker, có thể sao chép thành `ios/KomeCine/KomeCine/KomeCineConfig.plist` khi thiết lập lại. Google OAuth đang ở chế độ Testing với tài khoản chủ dự án là người dùng thử; cần cấu hình và xác minh phù hợp trước khi mở cho người dùng khác. Đăng nhập và đồng bộ đầu cuối vẫn cần được kiểm thử.

## Kiểm tra

```sh
cd backend && pnpm install && pnpm test && pnpm typecheck && pnpm build
xcodebuild test -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'platform=iOS Simulator,name=iPhone 17'
```

Player dùng AVPlayer/AVPlayerLayer với điều khiển SwiftUI riêng theo bố cục WeTV: thanh tua, tốc độ 0,5×–3×, khóa, bảng chọn tập/server, chọn giới hạn chất lượng từ HLS và chọn âm thanh/phụ đề thực có trong nguồn. Chạm đúp hai bên tua ±10 giây; giữ phát tạm 2×; kéo ngang để tua; vuốt dọc điều chỉnh độ sáng hoặc âm lượng video. Có thu nhỏ trong app, Picture in Picture, AirPlay, chụp khung hình/chia sẻ và thiết lập số giây bỏ qua mở đầu theo phim.

Phụ đề song ngữ dùng hai luồng WebVTT truy cập được; phụ đề gắn sẵn vào hình không thể tắt hoặc đổi cỡ. PiP/AirPlay dùng phụ đề native một ngôn ngữ khi nguồn cung cấp. Chất lượng là giới hạn thích ứng, không giả lập các mức nguồn không có. Khi tải phụ đề rời lỗi, player báo lỗi và dùng lại phụ đề native nếu có.

Thư viện → Tải xuống quản lý tải HLS ngoại tuyến bằng AVAssetDownloadURLSession. Việc tải và phát offline phụ thuộc khả năng của nguồn; chỉ báo sẵn sàng khi hệ thống xác nhận asset dùng offline được. Bản tải thuộc tài khoản trên thiết bị; dữ liệu khách được nhập một lần khi đăng nhập; đăng xuất ẩn bản tải của tài khoản cũ. Lịch sử riêng từng tập lưu trên máy, còn cloud tiếp tục đồng bộ tiến trình gần nhất của mỗi phim.

Các khả năng PiP, AirPlay tới thiết bị đích và tải/phát offline thực tế vẫn cần được kiểm tra trên iPhone. Bộ unit test bao phủ trạng thái điều khiển, HLS/WebVTT, tiến trình và tách dữ liệu tài khoản. Có video local cho UI test/preview trong bản Debug (`KOMECINE_PLAYER_PREVIEW=1`); chế độ này dùng kho dữ liệu riêng, không xác thực cloud và không bật trong bản Release. Xem [báo cáo kiểm chứng player](docs/superpowers/2026-10-31-player-validation.md).

Worker infra được triển khai tại `https://komecine-api.infra-coresys.workers.dev` với D1 mới; dữ liệu từ tài khoản Cloudflare cũ chưa được chuyển sang. Đăng nhập Google và đồng bộ cần được kiểm thử đầu cuối. Để phát hành hoặc chạy trên iPhone thật, cần chọn Apple Developer team trong Xcode và kiểm tra quyền sử dụng nội dung từ nhà cung cấp.
