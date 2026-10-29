import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {D1LibraryStore} from '../src/store.ts';
import {readFileSync} from 'node:fs';
function setup(){
 const db=new DatabaseSync(':memory:'); db.exec(readFileSync(new URL('../migrations/0001_initial.sql',import.meta.url),'utf8'));
 db.exec("INSERT INTO user (id,name,email,email_verified,created_at,updated_at) VALUES ('alice','Alice','a@example.com',1,1,1),('bob','Bob','b@example.com',1,1,1)");
 const d1={prepare:(sql:string)=>({bind:(...v:unknown[])=>({run:async()=>db.prepare(sql).run(...v as any[]),all:async()=>({results:db.prepare(sql).all(...v as any[])})})})};
 return {store:new D1LibraryStore(d1 as any),db};
}
test('progress respects last update even when seeking backward',async()=>{
 const {store}=setup();
 await store.putProgress('alice',{movieId:'kkphim:x',episodeSlug:'one',server:'s',position:90,duration:120,updatedAt:100});
 await store.putProgress('alice',{movieId:'kkphim:x',episodeSlug:'one',server:'s',position:30,duration:120,updatedAt:200});
 await store.putProgress('alice',{movieId:'kkphim:x',episodeSlug:'one',server:'s',position:100,duration:120,updatedAt:150});
 assert.equal((await store.listProgress('alice') as any[])[0].position,30);
 assert.deepEqual(await store.listProgress('bob'),[]);
});
test('deleting a user cascades to their favorites',async()=>{
 const {store,db}=setup(); await store.putFavorite('alice','kkphim:x',{id:'kkphim:x',name:'X'});
 await store.deleteAccount('alice'); assert.deepEqual(await store.listFavorites('alice'),[]);
 assert.equal((db.prepare('SELECT count(*) AS n FROM user').get() as any).n,1);
});
