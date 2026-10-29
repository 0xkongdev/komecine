import {test} from 'node:test';
import assert from 'node:assert/strict';
import { CatalogService, UpstreamError } from '../src/service.ts';

test('browse resolves root-relative movie poster paths without repeating the CDN directory', async () => {
  const service = new CatalogService(async () => Response.json({status:'success',data:{APP_DOMAIN_CDN_IMAGE:'https://phimimg.com',items:[{slug:'x',name:'X',poster_url:'uploads/movies/20261022/x-poster.webp',thumb_url:'uploads/movies/20261022/x-thumb.webp'}]}}));
  const result = await service.browse('phim-bo');
  assert.equal(result.items[0].posterURL,'https://phimimg.com/uploads/movies/20261022/x-poster.webp');
  assert.equal(result.items[0].backdropURL,'https://phimimg.com/uploads/movies/20261022/x-thumb.webp');
});

test('search encodes user queries and normalizes response', async () => {
  let requested = '';
  const service = new CatalogService(async (input) => { requested = String(input); return Response.json({status:'success',data:{items:[{slug:'x',name:'X'}],params:{pagination:{currentPage:1}}}}); });
  const result = await service.search('A & B', 1);
  assert.equal(new URL(requested).searchParams.get('keyword'), 'A & B');
  assert.equal(result.items[0].id,'kkphim:x');
});

test('invalid upstream response produces an actionable failure', async () => {
  const service = new CatalogService(async () => new Response('blocked',{status:403}));
  await assert.rejects(() => service.movie('x'), UpstreamError);
});

test('movie slug is escaped as one path component', async () => {
  let requested='';
  const service = new CatalogService(async input => {requested=String(input);return Response.json({status:true,movie:{slug:'x'},episodes:[]});});
  await service.movie('a/b');
  assert.equal(new URL(requested).pathname,'/phim/a%2Fb');
});
test('browse sends selected filters to KKPhim',async()=>{
 let requested='';
 const service=new CatalogService(async input=>{requested=String(input); return Response.json({status:'success',data:{items:[],params:{pagination:{currentPage:1}}}})});
 await service.browse('phim-bo',2,{category:'hanh-dong',country:'han-quoc',year:'2024'});
 const u=new URL(requested); assert.equal(u.pathname,'/v1/api/danh-sach/phim-bo'); assert.equal(u.searchParams.get('country'),'han-quoc');assert.equal(u.searchParams.get('page'),'2');
});
test('invokes fetch with the global receiver required by Workers', async()=>{
 const service=new CatalogService(async function(this:unknown){assert.equal(this,globalThis);return Response.json({status:true,items:[]})});
 await service.latest();
});
test('search forwards category, country and year filters',async()=>{
 let requested='';
 const service=new CatalogService(async input=>{requested=String(input);return Response.json({status:'success',data:{items:[]}})});
 await service.search('film',1,{category:'hanh-dong',country:'han-quoc',year:'2024'});
 const u=new URL(requested); assert.equal(u.searchParams.get('category'),'hanh-dong');assert.equal(u.searchParams.get('year'),'2024');
});

test('rankings select both RoPhim charts and preserve upstream ranking', async () => {
  const service = new CatalogService(async input => {
    assert.match(input, /homepageLists\?page=2&limit=4/);
    return Response.json({status:true,result:{collections:[
      {slug:'top-phim-bo-hom-nay',movies:[{id:41,name:'Series',origin_name:'Series',slug:'series',type:'series',publish_year:2026,thumbnail:'https://image.example/portrait.jpg',poster:'https://image.example/landscape.jpg'}]},
      {slug:'top-phim-le-hom-nay',movies:[{id:42,name:'Movie',origin_name:'Movie',slug:'movie',type:'movie',publish_year:2024}]}
    ],totalPages:4}});
  });
  const result = await service.rankings();
  assert.equal(result.series[0].rank, 1);
  assert.equal(result.series[0].movie.posterURL, 'https://image.example/portrait.jpg');
  assert.equal(result.series[0].movie.id, 'rophim:41');
  assert.equal(result.movies[0].type, 'movie');
});

test('ranking resolution checks identity and episode availability before returning a match', async () => {
  const service = new CatalogService(async input => {
    const url = new URL(input);
    if (url.pathname.includes('tim-kiem')) return Response.json({status:'success',data:{items:[
      {slug:'wrong',name:'Wrong',origin_name:'Same title',year:2020,type:'series'},
      {slug:'right',name:'Right',origin_name:'Same title',year:2026,type:'series'}]}});
    assert.equal(url.pathname, '/phim/right');
    return Response.json({status:true,movie:{slug:'right',name:'Right',origin_name:'Same title',year:2026,type:'series'},episodes:[{server_name:'S',server_data:[{slug:'tap-1',name:'1',link_m3u8:'https://example.com/a.m3u8'}]}]});
  });
  const found = await service.resolveRanking({name:'Right',originName:'Same title',year:2026,type:'series'});
  assert.equal(found?.slug,'right');
  assert.equal(found?.sources.length,1);
});

test('ranking resolution rejects an unrelated or unplayable result', async () => {
  const service = new CatalogService(async input => new URL(input).pathname.includes('tim-kiem')
    ? Response.json({status:'success',data:{items:[{slug:'wrong',name:'Different',origin_name:'Different',year:2026,type:'single'}]}})
    : Response.json({status:true,movie:{slug:'wrong'},episodes:[]}));
  assert.equal(await service.resolveRanking({name:'Wanted',originName:'Wanted',year:2026,type:'movie'}),null);
});
