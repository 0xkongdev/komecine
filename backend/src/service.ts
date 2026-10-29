import { imageURL, normalizeMovie, normalizeDetail } from './catalog.ts';
type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;
type Json = Record<string, any>;
type RankingQuery = {name:string, originName:string, year:number, type:string};
function identity(value: unknown): string { return typeof value === 'string' ? value.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu,' ').trim() : ''; }
export class UpstreamError extends Error { constructor(message = 'Nguồn phim tạm thời không khả dụng') { super(message); this.name = 'UpstreamError'; } }
export class CatalogService {
  constructor(privateFetch: Fetcher = fetch) { this.fetcher = privateFetch; }
  private fetcher: Fetcher;
  private rankingsCache?: { expires:number, value: {series:any[],movies:any[]} };
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
  async rankings() {
    if (this.rankingsCache && this.rankingsCache.expires > Date.now()) return this.rankingsCache.value;
    const find = new Map<string, any>();
    for (const page of [2,1,3,4]) {
      let response: Response;
      try { response = await this.fetcher.call(globalThis, `https://rophim1.vip/baseapi/api/v1/lists/homepageLists?page=${page}&limit=4`, {headers:{Accept:'application/json','User-Agent':'KomeCine/1.0'}}); } catch { throw new UpstreamError(); }
      if (!response.ok) throw new UpstreamError();
      let body: Json;
      try { body = await response.json() as Json; } catch { throw new UpstreamError(); }
      if (body.status !== true || !Array.isArray(body.result?.collections)) throw new UpstreamError();
      for (const collection of body.result.collections) if (['top-phim-bo-hom-nay','top-phim-le-hom-nay'].includes(collection.slug)) find.set(collection.slug,collection);
      if (find.size === 2) break;
    }
    if (find.size !== 2) throw new UpstreamError();
    const entries = (slug: string, type: string) => {
      const movies = find.get(slug)?.movies;
      if (!Array.isArray(movies)) throw new UpstreamError();
      return movies.flatMap((m:Json,index:number) => {
        if (!m || !Number.isSafeInteger(m.id) || typeof m.name !== 'string' || !m.name.trim()) return [];
        return [{rank:index+1,type,movie:{id:`rophim:${m.id}`,slug:typeof m.slug === 'string' ? m.slug : '',name:m.name,originName:typeof m.origin_name === 'string' ? m.origin_name : '',posterURL:imageURL(m.thumbnail),backdropURL:imageURL(m.poster),year:Number.isInteger(m.publish_year) ? m.publish_year : null}}];
      });
    };
    const value = {series:entries('top-phim-bo-hom-nay','series'),movies:entries('top-phim-le-hom-nay','movie')};
    this.rankingsCache = {value,expires:Date.now()+5*60*1000};
    return value;
  }
  async resolveRanking(query: RankingQuery) {
    if (!query.name || !Number.isInteger(query.year) || !['series','movie'].includes(query.type)) return null;
    const result = await this.get('/v1/api/tim-kiem',{keyword:query.originName || query.name,page:'1',limit:'24'});
    const candidates: Json[] = Array.isArray(result.data?.items) ? result.data.items : [];
    const expectedOrigin = identity(query.originName), expectedName = identity(query.name);
    const match = candidates.find(m => {
      const sameType = query.type === 'movie' ? m.type === 'single' : m.type === 'series';
      const sameTitle = (expectedOrigin && identity(m.origin_name) === expectedOrigin) || (expectedName && identity(m.name) === expectedName);
      return sameType && m.year === query.year && sameTitle && typeof m.slug === 'string' && m.slug.length > 0;
    });
    if (!match) return null;
    const detail = await this.movie(match.slug);
    return detail.sources.length ? detail : null;
  }
  async filters() {
    const [categories,countries] = await Promise.all([this.get('/the-loai'),this.get('/quoc-gia')]);
    return {categories:categories.data?.items ?? [],countries:countries.data?.items ?? []};
  }
}
