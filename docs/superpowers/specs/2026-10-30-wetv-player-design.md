# Player KomeCine theo giao diện WeTV

Ngày: 2026-10-30. Trạng thái: thiết kế đề xuất, chờ người dùng duyệt trước khi sửa mã sản phẩm.

## Mục tiêu và lựa chọn đã thống nhất

Người dùng muốn giao diện và chức năng player giống bản WeTV đang mở trên iPhone 15 Pro Max kết nối với Mac. Người dùng đã chọn giữ AVPlayer và tự viết toàn bộ giao diện, thao tác. Phạm vi là trải nghiệm xem phim của KomeCine ở chế độ dọc/ngang, cùng những chức năng truy cập trực tiếp từ player.

### Các cách đã cân nhắc

1. **AVPlayer với giao diện riêng — người dùng đã chọn.** Giữ bộ phát, lịch sử xem và đồng bộ hiện có; thay lớp điều khiển mặc định. Chủ động bố cục, bảng nổi và cử chỉ. Cần tự xử lý vòng đời, xoay màn hình, PiP và accessibility.
2. **Thư viện player có sẵn rồi tùy biến.** Có một phần điều khiển sẵn nhưng vẫn cần sửa đáng kể để giống WeTV; thêm phụ thuộc và cầu nối vào SwiftUI. Người dùng không chọn hướng này.

## Bằng chứng từ app tham chiếu

Đã trực tiếp xem và mở menu trên WeTV bằng iPhone Mirroring, không suy từ ảnh quảng cáo:

- Toàn màn hình: nút quay lại và tên tập ở trên trái; cast và menu thêm ở trên phải. Nút phát lớn ở giữa khi tạm dừng; khóa ở giữa cạnh trái; chụp khung hình và Send Love ở cạnh phải.
- Dưới cùng: thời gian hiện tại/tổng thời lượng, thanh tua ngang; hàng nút phát, tập tiếp theo, tốc độ, chất lượng, CC, danh sách tập, thoát toàn màn hình.
- Menu tốc độ ở cạnh phải: 0,5×, 0,75×, 1×, 1,25×, 1,5×, 2×, 3×. Mục được chọn có màu nhấn.
- Menu chất lượng: Tự động, 4K, 1080p, 720p, 480p, 360p, 144p trong tập tham chiếu. Đây là danh sách của WeTV, không chứng minh nguồn KomeCine có các mức tương ứng.
- CC mở bảng âm thanh/phụ đề: ngôn ngữ âm thanh, bật/tắt phụ đề, cỡ chữ, song ngữ, ngôn ngữ phụ đề.
- Danh sách phát là bảng ở bên phải, có ảnh xem trước và tên tập.
- Menu thêm: thêm danh sách xem, tải xuống, bỏ qua phần mở đầu, tùy chọn mạng/cast, thanh âm lượng, độ sáng.
- Khi khóa, các điều khiển chính ẩn; chạm video có thể gọi lại nút khóa. Khi mở khóa trở về điều khiển thông thường.
- Màn hình dọc: video ở trên; điều khiển phát, thời gian, thanh tua và phóng toàn màn hình gọn trong video; dưới video là tên phim, thông tin và danh sách tập.
- Đã quan sát chuyển giữa toàn màn hình ngang và dọc. Đã xác nhận chạm đúp bên phải tua +10 giây, bên trái -10 giây, có HUD mũi tên tròn. Chưa xác nhận kéo ngang, giữ để tăng tốc, vuốt độ sáng/âm lượng trong app tham chiếu; các cử chỉ chưa xác nhận bên dưới là đề xuất của Codex.

## Hiện trạng KomeCine

`PlayerScreen.swift` bọc AVPlayerViewController, dùng điều khiển hệ thống cùng lớp SwiftUI riêng cho tập/server/khóa. `PlaybackCoordinator.swift` sở hữu một AVPlayer, mở/chuyển tập, lưu tiến trình 5 giây/lần và đếm ngược 5 giây để phát tập tiếp. `ContentView.swift` có fullScreenCover và thanh thu nhỏ. PlaybackSource hiện có server, tên tập, slug và một URL HLS; chưa có mốc intro/outro, phụ đề ngoài hay ảnh từng tập. Nguồn đi qua KKPhimAdapter hoặc backend catalog.

## Thiết kế giao diện

### Toàn màn hình ngang

Video phủ vùng hiển thị, giữ tỉ lệ mặc định. Gradient tối nhẹ ở trên/dưới giúp đọc điều khiển. Bố trí các nút theo vị trí của WeTV; dùng tên và màu nhấn KomeCine, biểu tượng trắng, không đặt mỗi nút trong một vòng tròn lớn như hiện tại. Vùng chạm tối thiểu 44 pt và tránh Dynamic Island/safe area.

- Trên: quay về dọc, tên phim/tập; AirPlay, menu thêm. Đóng hẳn player nằm trong menu; thu nhỏ giữ nguyên phát.
- Giữa: nút phát lớn khi dừng, trạng thái đang tải hoặc lỗi khi cần; khóa bên trái; chụp khung hình/yêu thích bên phải.
- Dưới: thời gian và thanh tua, phát/dừng, tập tiếp; tốc độ, chất lượng, CC, danh sách tập, thoát toàn màn hình.
- Chỉ mở một bảng bên phải tại một thời điểm. Bảng có nền tối trong, cuộn được; chạm bên ngoài đóng bảng. Đang mở bảng hoặc tua thì không tự ẩn điều khiển.
- Điều khiển tự ẩn sau khoảng 3 giây khi phát; tạm dừng thì tiếp tục hiện. Khóa chặn các nút/cử chỉ khác và vẫn cho gọi nút mở khóa. Khóa không thay đổi trạng thái phát/dừng.

### Màn hình dọc

Video 16:9 ở trên, có hàng điều khiển gọn giống tham chiếu. Dưới video hiển thị tên phim, tập/server, danh sách tập ngang và mô tả có sẵn. Không thay toàn bộ trang chủ hay các tab của app. Danh sách tập dùng ảnh phim làm ảnh dự phòng khi không có ảnh riêng từng tập; không tạo thumbnail giả theo nội dung tập.

Thanh thu nhỏ tiếp tục mở lại đúng AVPlayer và tiến trình; thêm phát/dừng, tên tập và đóng để người dùng điều khiển được mà không mở rộng.

## Chức năng và xử lý giới hạn nguồn

| Chức năng | Hành vi dự kiến |
| --- | --- |
| Phát/dừng, tua | Nút giữa và hàng dưới đồng bộ; thanh tua hiển thị thời gian xem trước, chỉ seek khi thả. Chặn thời gian âm/vượt cuối; không tua khi chưa có thời lượng hợp lệ. |
| Tập/server | Bảng tập cuộn đến tập hiện tại; tập tiếp theo ở cùng server; đổi server ưu tiên cùng slug. Đổi server cùng tập giữ vị trí, đổi tập dùng lịch sử của tập đích nếu có. |
| Tốc độ | Các mức như tham chiếu; nhớ lựa chọn trong phiên và giữ qua tạm dừng, đổi tập. Trạng thái phát thực tế vẫn lấy từ AVPlayer. |
| Chất lượng | Chỉ liệt kê mức đọc được từ HLS; có Tự động. Nếu API dùng giới hạn chất lượng thích ứng thì ghi rõ “Tối đa 720p”, không giả vờ khóa chính xác 720p. Không hiện 4K/1080p nếu nguồn không cung cấp. Khi chỉ có một luồng thì ghi nguồn hiện tại, không tạo các lựa chọn vô tác dụng. |
| Âm thanh/phụ đề | Đọc các media selection group thực tế của asset. Cho chọn âm thanh, bật/tắt và chọn phụ đề có thể tách riêng, chỉnh cỡ chữ nếu render hỗ trợ. Nếu phụ đề đã gắn vào hình thì giải thích không thể tắt/đổi cỡ. Song ngữ phải hoạt động khi HLS cung cấp hai luồng WebVTT truy cập được: chọn ngôn ngữ chính/phụ, đọc và đồng bộ hai track với thời gian video, tắt track native để không vẽ trùng. Với track không đọc được riêng hoặc không đủ hai ngôn ngữ, giải thích giới hạn; không hiện công tắc có thể bật nhưng không làm gì. |
| PiP/AirPlay | Giữ PiP và AirPlay qua API hệ thống; PiP khôi phục player đang xem. Nút cast của KomeCine mở AirPlay. Google Cast/Chromecast là tích hợp khác, không gán nhầm chức năng cho nút này. |
| Khóa/tự ẩn | State rõ ràng giữa khóa, hiện điều khiển, bảng đang mở, đang tương tác. VoiceOver không tự ẩn điều khiển cần thao tác. |
| Cử chỉ đề xuất | Chạm gọi/ẩn điều khiển; chạm đúp hai bên tua ±10 giây; giữ trên vùng video phát tạm 2×, thả khôi phục; kéo ngang tua có HUD; vuốt dọc bên trái chỉnh độ sáng, bên phải chỉnh âm lượng. Không tranh cử chỉ với thanh tua, bảng cuộn hoặc nút. Khóa vô hiệu hóa các cử chỉ này. |
| Âm lượng/độ sáng | Có thanh điều chỉnh trong menu thêm. Âm lượng dùng API hệ thống được hỗ trợ; độ sáng được khôi phục khi rời player. Không ghi đè nút âm lượng vật lý. |
| Chụp khung hình | Tạo ảnh từ tài nguyên video tại thời điểm hiện tại, cho xem/chia sẻ bằng sheet hệ thống. Báo rõ nếu nội dung không cho lấy ảnh. Không âm thầm lưu vào Photos. |
| Danh sách xem/chia sẻ | Dùng yêu thích hiện có của KomeCine và sheet chia sẻ hệ thống. “Send Love” của WeTV được thay bằng yêu thích KomeCine; không tạo số lượt thích hoặc dịch vụ WeTV giả. |
| Bỏ qua mở đầu | Nguồn hiện chưa cung cấp mốc. Cho người dùng đặt số giây bỏ qua theo phim, mặc định tắt; ghi rõ đây là thiết lập của họ. Khi có mốc thật sau này có thể dùng để hiện nút bỏ qua. Không tự đoán intro 90 giây cho mọi phim. |
| Tải xuống | HLS offline qua AVAssetDownloadURLSession khi nguồn hỗ trợ: tiến trình, hủy, xóa, lỗi rõ ràng, và mở bản đã tải khi offline. Thêm danh sách tải trong Thư viện. Khôi phục thông tin tải sau khi mở app; không hiển thị “đã tải” khi hệ thống chưa xác nhận tệp dùng được. Nguồn không hỗ trợ hoặc bị lỗi thì báo lỗi thực, không nút giả. |
| Hết tập/lỗi mạng | Giữ đếm ngược 5 giây và Hủy; không chuyển khi hết tập cuối. Có loading, thông báo lỗi, thử lại hoặc chọn server. Thử lại giữ vị trí và lựa chọn đang có nếu có thể. |

Không mang quảng cáo, VIP, mua quà, bảng xếp hạng diễn viên hoặc dịch vụ tài khoản WeTV sang KomeCine. Đây là các hệ thống riêng của WeTV; giao diện player vẫn dùng nội dung và dữ liệu KomeCine. Các mục phụ thuộc nguồn phải có trạng thái thật, không hứa đủ chức năng chỉ bằng cách thêm biểu tượng.

## Cấu trúc kỹ thuật đề xuất của Codex

- PlaybackCoordinator tiếp tục là chủ sở hữu AVPlayer duy nhất; tách trạng thái phát, thời gian, buffer, tốc độ, track và lựa chọn chất lượng thành dữ liệu quan sát được. Observer gắn đúng item và được tháo khi thay/đóng; callback cũ không được ghi đè phiên mới.
- Thay SystemPlayer bằng một view hiển thị AVPlayerLayer, các điều khiển bằng SwiftUI. Cầu nối UIKit xử lý PiP, AirPlay, âm lượng và hướng màn hình. Không thao tác view riêng tư của AVKit.
- Không thay view/video layer khi chỉ đổi dọc/ngang hoặc mở bảng. Fullscreen là thay bố cục và yêu cầu hướng qua UIWindowScene, không tạo AVPlayer mới. Thoát fullscreen khôi phục dọc; đóng/thu nhỏ phải trả hướng phù hợp cho phần còn lại của app.
- Một enum quản lý bảng đang mở; tách model trạng thái điều khiển và logic cử chỉ khỏi bố cục. Thêm accessibility identifiers ổn định để kiểm tra được bằng UI tests.
- Tách đọc metadata HLS và quản lý download thành dịch vụ riêng; request/callback có định danh nguồn, có hủy và timeout. Không để tải manifest chặn phát video. Download được lưu dưới thư mục dữ liệu app, không đưa đường dẫn cục bộ vào đồng bộ cloud.
- Với song ngữ WebVTT, có renderer phụ đề riêng, fixture đồng bộ timestamp, tìm cue khi seek và xử lý segment/timeline HLS; không chỉ render native một track rồi ghi là song ngữ. Trong PiP/AirPlay, dùng một track native khả dụng và thông báo giới hạn song ngữ, vì overlay SwiftUI không tự đi theo cửa sổ/thiết bị đích. Khi thoát PiP/AirPlay khôi phục hai track trong app.
- Tiến trình từng tập bổ sung lưu cục bộ theo tài khoản và khóa movie/server/episode. Cloud tiếp tục dùng hợp đồng hiện có: một tiến trình xem gần nhất cho mỗi phim. Không mở rộng schema backend trong việc này; thiết bị khác vẫn resume tập gần nhất được cloud đồng bộ. Đây là lựa chọn phạm vi của Codex để giữ tương thích.
- Bản tải xuống thuộc tài khoản trên thiết bị, không chia sẻ danh sách giữa các tài khoản. Dữ liệu khách được chuyển sở hữu một lần cho tài khoản đầu tiên đăng nhập, giống cách thư viện khách được nhập hiện tại. Đăng xuất/đổi tài khoản ẩn các bản tải của tài khoản cũ nhưng giữ tệp để dùng khi đăng nhập lại, không tự xóa video của người dùng. Callback tải mang owner id cố định; không ghi nhầm sang tài khoản đang mở. Đổi tài khoản dừng phiên phát cũ trước khi đổi nơi lưu lịch sử. Những quy tắc này là đề xuất của Codex, cần nêu khi trình thiết kế.
- Không đổi schema backend chỉ để có nút trên giao diện. Thông tin HLS/track lấy từ chính nguồn phát; metadata bỏ qua intro do người dùng đặt lưu cục bộ theo movie id.
- Kiểm tra iOS tối thiểu của app và test target; hiện app target đặt iOS 17, test target có cấu hình iOS 27. Chọn simulator/runtime thực có để kiểm tra, không tăng tối thiểu của app vì tiện chạy test.

## Kiểm chứng và tiêu chí hoàn thành

1. Unit tests cho giới hạn seek, trạng thái tốc độ/giữ 2×, khóa/bảng/tự ẩn, đổi server giữ vị trí, hủy callback của nguồn cũ, phân tích HLS có/không variant, đồng bộ hai track WebVTT khi seek, và tách owner của lịch sử/download khi đổi tài khoản.
2. UI tests với dữ liệu kiểm soát cho hiện/ẩn/khóa, mở/đóng các bảng, chọn tập/tốc độ, xoay bằng nút khi thiết bị vẫn dọc, thu nhỏ/mở lại không mất trạng thái. Giữ kiểm tra lịch sử và luồng xem hiện có; tránh mọi test phải dựa hoàn toàn vào phim live có thể biến mất.
3. Chạy build và test phù hợp trên simulator có sẵn, kiểm tra ảnh màn hình dọc/ngang để so bố cục với tham chiếu đã quan sát.
4. Kiểm tra trên iPhone đang cắm: AVPlayer giữ phiên khi xoay, cử chỉ không tranh nút, PiP, AirPlay picker, âm lượng/độ sáng, chụp khung hình và một nguồn HLS tải/offline được. Không tuyên bố AirPlay tới TV thành công nếu chỉ mới mở picker; không tuyên bố phụ đề song ngữ có nếu nguồn không cung cấp.
5. Báo riêng những gì đã kiểm tra thật, những giới hạn từ nguồn, và các kiểm tra cần thiết bị đích khác. Giữ thương hiệu KomeCine và không thay giao diện ngoài phạm vi xem phim, ngoại trừ mục tải xuống trong Thư viện.

## Phần để người triển khai quyết định

Tên file/component, chi tiết animation 0,2–0,3 giây, spacing/font trong giới hạn bố cục tham chiếu, kỹ thuật chống xung đột gesture, cấu trúc lưu download/thiết lập cục bộ và cách tạo fixture test. Các quyết định này không được làm mất hành vi đã nêu hoặc che tính năng chưa có bằng nút giả.

## Tài liệu nền tảng đã đối chiếu

- Apple: [AVAssetDownloadURLSession](https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession) — tải HLS offline bằng background session, nối lại session sau khi app mở lại và xử lý delegate trong vòng đời app.
- Apple: [preferredMaximumResolution](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution) — đây là độ phân giải tối đa ưu tiên của HLS, không phải lời hứa khóa chính xác một mức chất lượng.
- Apple: [AVPictureInPictureController](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller) — custom player cần controller riêng, kiểm tra supported/possible và cấu hình background audio.
- Apple: [AVPlayerItem](https://developer.apple.com/documentation/avfoundation/avplayeritem) — media selection và textStyleRules cho phụ đề WebVTT.
