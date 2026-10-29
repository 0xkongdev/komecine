import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createLibraryRoutes} from '../src/library.ts';
const rows = new Map<string,unknown>();
const store = {
 listFavorites:async (u:string) => [...rows].filter(([k])=>k.startsWith(u+':')).map(([,v])=>v),
 putFavorite:async (u:string,id:string,entry:unknown)=>{rows.set(u+':'+id,entry)},
 deleteFavorite:async (u:string,id:string)=>{rows.delete(u+':'+id)},
 listProgress:async (_u:string)=>[],
 putProgress:async (_u:string,_entry:unknown)=>{},
 deleteAccount:async (_u:string)=>{},
};
test('library requires an authenticated session',async()=>{
 const app=createLibraryRoutes(async()=>null,store);
 const response=await app.request('/favorites'); assert.equal(response.status,401);
});
test('favorites are scoped to authenticated user, not a client-supplied user ID',async()=>{
 rows.clear();
 const app=createLibraryRoutes(async()=>({user:{id:'alice'}}),store);
 const response=await app.request('/favorites/kkphim%3Atest',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({id:'kkphim:test',name:'Test',userId:'bob'})});
 assert.equal(response.status,200); assert.ok(rows.has('alice:kkphim:test')); assert.equal(rows.has('bob:kkphim:test'),false);
});
test('progress rejects negative times',async()=>{
 const app=createLibraryRoutes(async()=>({user:{id:'alice'}}),store);
 const response=await app.request('/progress',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({movieId:'kkphim:test',episodeSlug:'1',server:'main',position:-2,duration:120,updatedAt:123})});
 assert.equal(response.status,400);
});
test('library routes can serve their public /v1/me prefix',async()=>{
 const app=createLibraryRoutes(async()=>({user:{id:'alice'}}),store,'/v1/me');
 const response=await app.request('/v1/me/favorites'); assert.equal(response.status,200);
});
