# Gả Kim Thoa — tập 26 Vietsub

Kiểm tra ngày 02/11/2026 (giờ Việt Nam).

## Nguyên nhân

Worker và API KKPhim gốc cùng trả URL `https://a.kvp726.com/20261102/hZBE2xdF/index.m3u8` cho tập 26 Vietsub của `ga-kim-thoa-ga-tram-vang`. GET URL này trả HTTP 404, kể cả khi gửi User-Agent trình duyệt và Referer của player nguồn. Link embed cũng dùng đúng URL HLS này.

Tái hiện bằng `APIClient.shared.detail` và `PlaybackCoordinator` thực trên iPhone 17 simulator: AVPlayer trả `NSURLErrorDomain -1100`, lỗi bên dưới là `CoreMediaErrorDomain -12938`, `HTTP 404: File Not Found`. Video không phát và trạng thái buffering kết thúc.

Ở thời điểm kiểm tra, Vietsub có 26 tập; Thuyết Minh có 25 tập. Không có server khác cho tập 26 trong dữ liệu nhà cung cấp. Manifest tập 25 Vietsub và Thuyết Minh cũng trả 404; manifest tập 24 trả 200. Kiểm tra HTTP của tập 24 không phải bằng chứng đã phát trọn tập.

## Sửa trong app

- Giữ mã trạng thái HTTP khi tải tài nguyên HLS.
- Khi AVPlayer thất bại và manifest trả 404/410, hiển thị “Video của tập này hiện không có trên máy chủ nguồn. Vui lòng thử lại sau.”
- Thông tin chất lượng/phụ đề là tùy chọn: lỗi tải metadata không chặn video đang phát được.
- Kết quả đến muộn từ nguồn cũ không cập nhật lỗi của tập mới.

Thay đổi này giải thích đúng lỗi; việc xem tập 26 vẫn phụ thuộc nhà cung cấp khôi phục video. Không thay URL bằng tập khác.

## Kiểm chứng

Lượt chạy đạt 42/42 test: 37 test hiện có, 4 test hồi quy mới và 1 test chẩn đoán nguồn live chạy tạm thời. Test live đã được gỡ sau khi lưu kết quả để bộ test thường xuyên không phụ thuộc tình trạng CDN. Bốn test mới dùng HTTP loopback thật cho URLSession/AVPlayer, gồm manifest 404, thông báo thiếu nguồn, video hợp lệ vẫn phát khi metadata lỗi và đổi tập trong khi kết quả lỗi cũ chưa hoàn tất.

Lệnh:

```sh
xcodebuild test -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'platform=iOS Simulator,id=73FB8A5F-1CE1-4DAE-8580-DA883AC9F2DF' -parallel-testing-enabled NO -only-testing:KomeCineTests
```

Log: `/tmp/komecine-source-failure-final.log`. `git diff --check` đạt. Chưa cài bản sửa lên iPhone thật; thiết bị hiện không kết nối.
