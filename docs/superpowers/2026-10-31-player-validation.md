# Kiểm chứng player theo WeTV

## Thay đổi

Giữ AVPlayer và thay điều khiển hệ thống bằng SwiftUI/AVPlayerLayer. Có bố cục dọc/ngang, bảng tốc độ/chất lượng/phụ đề/tập/server, khóa và tự ẩn, tua/chạm đúp/giữ phát nhanh, điều chỉnh độ sáng/âm lượng video, thu nhỏ/mở lại, chụp khung hình, PiP/AirPlay và quản lý tải HLS offline. Chất lượng, track và phụ đề song ngữ dựa trên khả năng thực của nguồn.

Lịch sử riêng từng tập lưu cục bộ theo tài khoản; cloud tiếp tục lưu tiến trình gần nhất của từng phim. Tải offline tách theo tài khoản và nhận dữ liệu khách một lần. Không đổi schema backend hoặc thêm thư viện player bên thứ ba.

## Kết quả tự động

- **37 unit test đạt**, gồm kiểm tra seek, khóa/bảng, HLS, WebVTT, MPEGTS rollover, cue trùng, lỗi phụ đề, tiến trình cloud/cục bộ, quyền sở hữu dữ liệu, pause từ AVPlayer và hàng đợi mở lại khi đang thu nhỏ. Lượt cuối trên mã đã tách dữ liệu preview đạt 39/39 test (37 unit và 2 UI custom), không có test thất bại hoặc bị bỏ qua.
- **11 UI test hiện tại đã đạt qua lượt chạy đầy đủ và các lượt chạy lại có chọn lọc.** Hai test custom mới được chạy lại trên mã cuối và đều đạt, bao gồm khóa ở màn hình dọc, tốc độ 1,5×, khóa ở màn hình ngang, thu nhỏ/mở lại, xoay bằng nút khi thiết bị vẫn dọc và giữ view video.
- Lượt full suite ban đầu có 5 test cũ thất bại. Bốn trường hợp phụ thuộc giả định phim xếp hạng luôn phát được; API thực tế trả HTTP 404 `movie_unavailable` cho “Thượng Công Chúa” và “Bác Sĩ X (Phần 1)”. Các test này hiện kiểm tra đúng hai nhánh: nội dung phát được hoặc thông báo chưa có nguồn. Test hình học trang chi tiết dùng phim “Xóm Nhỏ”, có nguồn KKPhim.
- Test xoay cũ qua tìm kiếm trực tiếp đã được gộp vào test custom dùng video local, tránh lặp cùng hợp đồng xoay và phụ thuộc nội dung live. Không bỏ kiểm tra xoay hoặc trả về dọc.
- Build cho simulator, build iOS device không ký và build có ký cho iPhone thật đều đạt. Bản iOS tối thiểu vẫn là 17. Build máy thật dùng team đã có qua tham số dòng lệnh, không sửa cấu hình ký trong project.

Lệnh chính:

```sh
xcodebuild test -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'platform=iOS Simulator,id=73FB8A5F-1CE1-4DAE-8580-DA883AC9F2DF' -parallel-testing-enabled NO
xcodebuild test -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'platform=iOS Simulator,id=73FB8A5F-1CE1-4DAE-8580-DA883AC9F2DF' -parallel-testing-enabled NO -only-testing:KomeCineUITests/CustomPlayerUITests
xcodebuild test -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'platform=iOS Simulator,id=73FB8A5F-1CE1-4DAE-8580-DA883AC9F2DF' -parallel-testing-enabled NO -only-testing:KomeCineTests -only-testing:KomeCineUITests/CustomPlayerUITests
xcodebuild build -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Nhật ký phiên này: `/tmp/komecine-player-all-tests.log`, `/tmp/komecine-player-ui-live-rerun.log`, `/tmp/komecine-player-ui-remaining.log`, `/tmp/komecine-player-isolated-final.log`, `/tmp/komecine-player-device-verified.log`, `/tmp/komecine-player-signed-device.log`. Tổng hợp 11 UI case: `/tmp/komecine-player-final-ui-evidence.json`; summary lượt cuối: `/tmp/komecine-player-latest-summary.json`. Kết quả hiện tại là tổng hợp của full run và rerun; không có tuyên bố rằng lượt full run đầu tiên đã xanh.

## Rà soát và kiểm tra trực tiếp

Đã mở WeTV thực tế trên iPhone qua QuickTime/iPhone Mirroring và khảo sát bảng tốc độ, chất lượng, CC, danh sách tập, menu thêm, khóa và chuyển dọc/ngang. Đã xem bố cục KomeCine mới qua Device Hub và chỉnh vùng an toàn cho Dynamic Island, thanh tua tròn, bảng tốc độ và vùng chạm tối thiểu 44 pt.

Một lượt code review độc lập phát hiện lỗi env của thanh mini, đồng bộ sai chủ tài khoản, trạng thái pause từ PiP, lịch sử cloud mới hơn, phụ đề trùng/mất khi lỗi và MPEGTS wrap. Các lỗi này đã được sửa và thêm kiểm tra phù hợp. Thu nhỏ/mở lại được xác nhận thêm bằng UI test sau khi sửa việc đổi host của video và chờ chuyển cảnh đóng hoàn tất.

iPhone 15 Pro Max (iOS 27.0.1) kết nối lại cuối phiên. Đã cài bản Debug có ký và mở thành công bằng devicectl; đã nhìn thấy player preview local trên màn hình máy thật qua iPhone Mirroring. Công cụ Mirroring trả `noWindowsAvailable` khi gửi thao tác chạm, nên không tính bước này là kiểm chứng thao tác trên máy thật. Sau kiểm tra đã mở lại app ở chế độ thông thường. Preview dùng kho cục bộ và namespace tải riêng, không xác thực đồng bộ cloud.

## Giới hạn kiểm chứng

- Chưa xác nhận PiP thực trên máy thật, AirPlay tới TV, background download và phát trong chế độ máy bay. Nút picker hoặc build thành công không được coi là bằng chứng những đường này đã hoạt động đầu cuối.
- Hai phụ đề yêu cầu hai luồng WebVTT đọc được; phụ đề gắn trong hình không thể tắt/đổi cỡ. PiP/AirPlay dùng một track native khả dụng. Không có cam kết về DRM, phụ đề mã hóa hay phát live.
- Bộ công cụ Xcode hiện phát log `invalidDigitCount` cho SDK record và `no debugger version` ngay cả khi test đã chạy thành công. Việc đánh giá dùng exit code và xcresult, không suy từ những dòng log này. Runtime còn nhắc lời gọi audio session đồng bộ trên main thread vốn đã có trong bộ phát cũ.

## Các quyết định trong phiên

- Thực hiện trực tiếp trong checkout hiện có trên nhánh `codex/wetv-player` để giữ công việc khỏi nhánh gốc; muốn quay lại trạng thái cũ cần checkout nhánh gốc. Không merge hoặc push.
- Lời nhắn “tiếp” được dùng làm phê duyệt triển khai thiết kế đã trình. Không thêm một vòng xin duyệt kế hoạch nữa; phạm vi vẫn theo thiết kế đã thống nhất.
