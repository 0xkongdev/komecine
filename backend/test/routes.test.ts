import {test} from 'node:test';
import assert from 'node:assert/strict';
import { createCatalogRoutes } from '../src/routes.ts';
import { UpstreamError } from '../src/service.ts';
const stub = {
  latest: async (page: number) => ({items:[{slug:'x'}],pagination:{page}}),
  search: async (query: string, page: number) => ({items:[{name:query}],pagination:{page}}),
  movie: async (slug: string) => ({slug,sources:[]}),
  filters: async () => ({categories:[],countries:[]}),
};
test('home is public and returns paginated catalog', async () => {
  const response = await createCatalogRoutes(stub).request('/home?page=2');
  assert.equal(response.status,200); assert.equal((await response.json() as any).pagination.page,2);
});
test('blank search returns empty results without a request to source', async () => {
  const response = await createCatalogRoutes(stub).request('/search?q=%20');
  assert.deepEqual((await response.json() as any).items,[]);
});
test('source failures return a safe 502', async () => {
  const app = createCatalogRoutes({...stub,movie:async () => {throw new UpstreamError();}});
  const response = await app.request('/movies/x');
  assert.equal(response.status,502); assert.equal((await response.json() as any).error,'upstream_unavailable');
});
