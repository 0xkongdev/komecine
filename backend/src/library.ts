import { Hono } from 'hono';

type Favorite = {id:string; name:string; slug?:string; posterURL?:string|null; originName?:string; year?:number|null};
type Progress = {movieId:string; episodeSlug:string; server:string; position:number; duration:number; updatedAt:number};
type Session = {user:{id:string}} | null;
type SessionReader = (request: Request) => Promise<Session>;
export interface LibraryStore {
  listFavorites(userId:string):Promise<unknown[]>;
  putFavorite(userId:string,id:string,entry:Favorite):Promise<void>;
  deleteFavorite(userId:string,id:string):Promise<void>;
  listProgress(userId:string):Promise<unknown[]>;
  putProgress(userId:string,entry:Progress):Promise<void>;
  deleteAccount(userId:string):Promise<void>;
}
function text(value: unknown, max=256): value is string { return typeof value === 'string' && value.trim().length > 0 && value.length <= max; }
async function body(c: any):Promise<any> { try { return await c.req.json(); } catch { return null; } }
export function createLibraryRoutes(sessionFor:SessionReader,store:LibraryStore,prefix = '') {
  const app=new Hono<{Variables:{userId:string}}>().basePath(prefix);
  app.use('*', async (c,next)=>{ const session=await sessionFor(c.req.raw); if (!session?.user?.id) return c.json({error:'unauthorized'},401); c.set('userId',session.user.id); c.header('Cache-Control','no-store'); await next(); });
  app.get('/favorites',async c=>c.json({items:await store.listFavorites(c.get('userId'))}));
  app.put('/favorites/:id',async c=>{const v=await body(c), id=c.req.param('id'); if(!v || v.id!==id || !text(id) || !text(v.name)) return c.json({error:'invalid_favorite'},400); const entry:Favorite={id,name:v.name,slug:typeof v.slug==='string'?v.slug:undefined,originName:typeof v.originName==='string'?v.originName:undefined,posterURL:typeof v.posterURL==='string'?v.posterURL:null,year:Number.isInteger(v.year)?v.year:null}; await store.putFavorite(c.get('userId'),id,entry); return c.json({ok:true});});
  app.delete('/favorites/:id',async c=>{await store.deleteFavorite(c.get('userId'),c.req.param('id'));return c.json({ok:true});});
  app.get('/progress',async c=>c.json({items:await store.listProgress(c.get('userId'))}));
  app.put('/progress',async c=>{const v=await body(c); if(!v || !text(v.movieId) || !text(v.episodeSlug) || !text(v.server) || !Number.isFinite(v.position) || v.position<0 || !Number.isFinite(v.duration) || v.duration<0 || !Number.isSafeInteger(v.updatedAt) || v.updatedAt<0 || v.updatedAt>Date.now()+300000) return c.json({error:'invalid_progress'},400); const entry:Progress={movieId:v.movieId,episodeSlug:v.episodeSlug,server:v.server,position:v.position,duration:v.duration,updatedAt:v.updatedAt}; await store.putProgress(c.get('userId'),entry); return c.json({ok:true});});
  app.delete('/account',async c=>{await store.deleteAccount(c.get('userId'));return c.json({ok:true});});
  return app;
}
