import { Hono } from 'hono';
import { CatalogService, UpstreamError } from './service.ts';
type Catalog = Pick<CatalogService, 'latest' | 'search' | 'movie' | 'filters' | 'browse' | 'rankings' | 'resolveRanking'>;
function page(value?: string) { const n = Number(value); return Number.isInteger(n) && n > 0 ? Math.min(n, 10000) : 1; }
export function createCatalogRoutes(catalog: Catalog = new CatalogService()) {
  const app = new Hono();
  app.onError((error,c) => error instanceof UpstreamError ? c.json({error:'upstream_unavailable',message:error.message},502) : c.json({error:'internal_error'},500));
  app.get('/home', async c => c.json(await catalog.latest(page(c.req.query('page')))));
  app.get('/search', async c => { const q = (c.req.query('q') ?? '').trim().slice(0,100); return c.json(q ? await catalog.search(q,page(c.req.query('page')),{category:c.req.query('category') ?? '',country:c.req.query('country') ?? '',year:c.req.query('year') ?? ''}) : {items:[],pagination:null}); });
  app.get('/browse', async c => c.json(await catalog.browse(c.req.query('kind') ?? 'phim-moi',page(c.req.query('page')),{category:c.req.query('category') ?? '',country:c.req.query('country') ?? '',year:c.req.query('year') ?? ''})));
  app.get('/rankings', async c => c.json(await catalog.rankings()));
  app.get('/rankings/resolve', async c => {
    const name = (c.req.query('name') ?? '').trim().slice(0,150), originName = (c.req.query('originName') ?? '').trim().slice(0,150);
    const year = Number(c.req.query('year')), type = c.req.query('type') ?? '';
    const detail = await catalog.resolveRanking({name,originName,year,type});
    return detail ? c.json(detail) : c.json({error:'movie_unavailable',message:'Phim này hiện chưa có trong kho KomeCine.'},404);
  });
  app.get('/filters', async c => c.json(await catalog.filters()));
  app.get('/movies/:slug', async c => c.json(await catalog.movie(c.req.param('slug'))));
  return app;
}
