import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeMovie, normalizeDetail, imageURL, episodeSources } from '../src/catalog.ts';

test('normalizes a movie and ignores invalid image objects', () => {
  assert.deepEqual(normalizeMovie({name:'A',slug:'a',poster_url:{},thumb_url:'a.jpg',year:2024}, 'https://images.example/'), {
    id:'kkphim:a', slug:'a', name:'A', originName:'', posterURL:null, backdropURL:'https://images.example/a.jpg', year:2024
  });
});

test('image URLs preserve absolute URLs and reject malformed values', () => {
  assert.equal(imageURL('https://cdn.example/a.jpg', 'https://images.example/'), 'https://cdn.example/a.jpg');
  assert.equal(imageURL('movie.jpg', 'https://images.example/uploads/movies/'), 'https://images.example/uploads/movies/movie.jpg');
  assert.equal(imageURL('upload/vod/movie.jpg', 'https://images.example/uploads/movies/'), 'https://images.example/upload/vod/movie.jpg');
  assert.equal(imageURL({}, 'https://images.example/'), null);
});

test('returns only valid HLS episodes and preserves source identities', () => {
  const sources = episodeSources([{server_name:'Vietsub',server_data:[{name:'1',slug:'tap-1',link_m3u8:'https://cdn.example/1.m3u8'},{name:'2',slug:'tap-2',link_embed:'https://example.com'}]}]);
  assert.deepEqual(sources,[{server:'Vietsub',name:'1',slug:'tap-1',url:'https://cdn.example/1.m3u8'}]);
});

test('movie details with no episodes remain usable', () => {
  const detail = normalizeDetail({movie:{name:'Trailer',slug:'trailer',content:'',poster_url:null},episodes:[]});
  assert.equal(detail.name,'Trailer');
  assert.deepEqual(detail.sources,[]);
});
test('does not turn malformed stream links into playable URLs',()=>{
 assert.deepEqual(episodeSources([{server_name:'S',server_data:[{name:'1',slug:'1',link_m3u8:'not-a-url'},{name:'2',slug:'2',link_m3u8:'javascript:alert(1)'}]}]),[]);
});
