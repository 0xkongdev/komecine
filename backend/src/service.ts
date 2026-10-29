import { normalizeMovie, normalizeDetail } from './catalog.ts';
type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;
type Json = Record<string, any>;
export class UpstreamError extends Error { constructor(message = 'Nguồn phim tạm thời không khả dụng') { super(message); this.name = 'UpstreamError'; } }
export class CatalogService {
  constructor(privateFetch: Fetcher = fetch) { this.fetcher = privateFetch; }
  private fetcher: Fetcher;
  private async get(path: string, params: Record<string, string> = {}): Promise<Json> {
    const url = new URL(path, 'https://phimapi.com');
    for (const [key,value] of Object.entries(params)) url.searchParams.set(key,value);
    let response: Response;
    try { response = await this.fetcher.call(globalThis, url.toString(), {headers:{Accept:'application/json','User-Agent':'KomeCine/1.0'}}); } catch (error) { console.error('KKPhim request failed:', error); throw new UpstreamError(); }
    if (!response.ok) throw new UpstreamError();
    try { const body = await response.json() as Json; if (!body || body.status === false || body.status === 'error') throw new Error(); return body; } catch { throw new UpstreamError(); }
  }
  async latest(page = 1) {
    const result = await this.get('/danh-sach/phim-moi-cap-nhat',{page:String(page)});
    return {items:(Array.isArray(result.items) ? result.items : []).map((m: unknown) => normalizeMovie(m, result.pathImage)), pagination:result.pagination ?? null};
  }
  async search(query: string, page = 1, filters: Record<string,string> = {}) {
    const params: Record<string,string> = {keyword:query,page:String(page),limit:'24'};
    for (const key of ['category','country','year']) if (filters[key]) params[key] = filters[key];
    const result = await this.get('/v1/api/tim-kiem',params);
    const data = result.data ?? {};
    return {items:(Array.isArray(data.items) ? data.items : []).map((m: unknown) => normalizeMovie(m, data.APP_DOMAIN_CDN_IMAGE ? `${data.APP_DOMAIN_CDN_IMAGE}/uploads/movies/` : undefined)),pagination:data.params?.pagination ?? null};
  }
  async browse(kind: string, page = 1, filters: Record<string,string> = {}) {
    const allowed = new Set(['phim-moi','phim-bo','phim-le','hoat-hinh']);
    if (!allowed.has(kind)) kind = 'phim-moi';
    const params: Record<string,string> = {page:String(page)};
    for (const key of ['category','country','year']) if (filters[key]) params[key] = filters[key];
    const result = await this.get(`/v1/api/danh-sach/${kind}`,params);
    const data=result.data ?? {};
    return {items:(Array.isArray(data.items) ? data.items : []).map((m:unknown)=>normalizeMovie(m, data.APP_DOMAIN_CDN_IMAGE ? `${data.APP_DOMAIN_CDN_IMAGE}/uploads/movies/` : undefined)),pagination:data.params?.pagination ?? null};
  }
  async movie(slug: string) { return normalizeDetail(await this.get(`/phim/${encodeURIComponent(slug)}`)); }
  async filters() {
    const [categories,countries] = await Promise.all([this.get('/the-loai'),this.get('/quoc-gia')]);
    return {categories:categories.data?.items ?? [],countries:countries.data?.items ?? []};
  }
}
