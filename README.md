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

Player dùng AVPlayerViewController với điều khiển hệ thống, chuyển tập, thu nhỏ trong ứng dụng và hỗ trợ Picture in Picture/AirPlay. Các tính năng phát nền và Picture in Picture cần kiểm tra thêm trên thiết bị thật.

Worker infra được triển khai tại `https://komecine-api.infra-coresys.workers.dev` với D1 mới; dữ liệu từ tài khoản Cloudflare cũ chưa được chuyển sang. Đăng nhập Google và đồng bộ cần được kiểm thử đầu cuối. Để phát hành hoặc chạy trên iPhone thật, cần chọn Apple Developer team trong Xcode và kiểm tra quyền sử dụng nội dung từ nhà cung cấp.
