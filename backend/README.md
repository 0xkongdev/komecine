# KomeCine backend

Cloudflare Worker chuẩn hóa danh mục KKPhim và quản lý thư viện bằng D1. Video HLS phát trực tiếp từ nguồn.

## Chuẩn bị

- Node.js 24+, pnpm, Cloudflare Workers và D1.
- Google OAuth client cho iOS và client web/server cùng Google Cloud project. Client web cung cấp ID và secret cho Worker; ID iOS và server được cấu hình trong app.
- Tạo D1 database `komecine`, thay `database_id` trong `wrangler.jsonc`. Không commit bí mật.
- Sao chép `.dev.vars.example` sang `.dev.vars`, điền Google web client ID/secret, URL Worker và secret ngẫu nhiên dài tối thiểu 32 ký tự.
- `BETTER_AUTH_URL` production phải là HTTPS URL thực của Worker. Cấu hình OAuth redirect `${BETTER_AUTH_URL}/api/auth/callback/google` trong Google Cloud Console.
- `wrangler.jsonc` hiện trỏ đến tài khoản Cloudflare infra và D1 `komecine` mới. Khi triển khai lại, đăng nhập Wrangler với quyền đối với tài khoản infra; phiên Wrangler mặc định trên máy có thể đang trỏ vào tài khoản cá nhân khác.

## Cục bộ

```sh
pnpm install
pnpm exec wrangler d1 migrations apply komecine --local
pnpm dev
```

Kiểm tra: `pnpm test`, `pnpm typecheck`, `pnpm build` (đóng gói thử). Với production, áp dụng migrations trên môi trường được chọn và cấu hình secrets bằng `wrangler secret put`.

## API

- `GET /health`
- `GET /v1/home?page=1`
- `GET /v1/search?q=...&page=1`
- `GET /v1/browse?kind=phim-bo&page=1&category=hanh-dong&country=han-quoc&year=2024`
- `GET /v1/filters`, `GET /v1/movies/{slug}`
- `/api/auth/*`: Better Auth Google social sign-in và phiên Bearer.
- `GET /v1/me/favorites`, `PUT|DELETE /v1/me/favorites/{id}`, `GET|PUT /v1/me/progress`, `DELETE /v1/me/account`: cần phiên Bearer.

Bộ lọc `kind` hỗ trợ `phim-moi`, `phim-bo`, `phim-le`, `hoat-hinh`. Xem `test/` để biết định dạng dữ liệu. Auth trả 503 khi chưa cấu hình; endpoint danh mục vẫn hoạt động.

Thông tin và HLS phụ thuộc dịch vụ thứ ba. Chưa kiểm thử phát AVPlayer hoặc đăng nhập Google end-to-end trên thiết bị.
