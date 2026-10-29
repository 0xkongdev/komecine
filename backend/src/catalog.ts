const DEFAULT_IMAGES = 'https://phimapi.com/uploads/movies/';
type RecordData = Record<string, unknown>;
function object(value: unknown): RecordData { return value && typeof value === 'object' && !Array.isArray(value) ? value as RecordData : {}; }
function string(value: unknown): string { return typeof value === 'string' ? value : ''; }
function array(value: unknown): unknown[] { return Array.isArray(value) ? value : []; }
export function imageURL(value: unknown, base = DEFAULT_IMAGES): string | null {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const path = /^(?:uploads\/movies|upload)\//i.test(value) ? `/${value}` : value;
    const url = new URL(path, base);
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : null;
  } catch { return null; }
}
export function normalizeMovie(value: unknown, base = DEFAULT_IMAGES) {
  const m = object(value); const slug = string(m.slug);
  return { id: `kkphim:${slug}`, slug, name: string(m.name), originName: string(m.origin_name), posterURL: imageURL(m.poster_url, base), backdropURL: imageURL(m.thumb_url, base), year: typeof m.year === 'number' ? m.year : null };
}
export function episodeSources(episodes: unknown) {
  return array(episodes).flatMap(rawServer => { const server = object(rawServer); return array(server.server_data).flatMap(rawEp => {
    const ep = object(rawEp); const rawUrl = string(ep.link_m3u8); const url = /^https?:\/\//i.test(rawUrl) ? imageURL(rawUrl) : null; const slug = string(ep.slug);
    return url && slug ? [{server:string(server.server_name),name:string(ep.name),slug,url}] : [];
  }); });
}
export function normalizeDetail(value: unknown) {
  const response = object(value); const m = object(response.movie);
  return {...normalizeMovie(m), description:string(m.content), type:string(m.type), status:string(m.status), duration:string(m.time), quality:string(m.quality), language:string(m.lang), categories:array(m.category).map(item => string(object(item).name)).filter(Boolean), countries:array(m.country).map(item => string(object(item).name)).filter(Boolean), sources:episodeSources(response.episodes)};
}
