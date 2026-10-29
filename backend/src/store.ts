import type {LibraryStore} from './library.ts';
type Favorite={id:string;name:string;slug?:string;posterURL?:string|null;originName?:string;year?:number|null};
type Progress={movieId:string;episodeSlug:string;server:string;position:number;duration:number;updatedAt:number};
export class D1LibraryStore implements LibraryStore {
  private db: D1Database;
  constructor(db:D1Database){this.db=db;}
  async listFavorites(userId:string){const {results}=await this.db.prepare('SELECT data FROM favorites WHERE user_id = ? ORDER BY created_at DESC').bind(userId).all<{data:string}>();return results.map(r=>JSON.parse(r.data));}
  async putFavorite(userId:string,id:string,entry:Favorite){await this.db.prepare('INSERT INTO favorites (user_id,movie_id,data,created_at) VALUES (?,?,?,?) ON CONFLICT(user_id,movie_id) DO UPDATE SET data=excluded.data').bind(userId,id,JSON.stringify(entry),Date.now()).run();}
  async deleteFavorite(userId:string,id:string){await this.db.prepare('DELETE FROM favorites WHERE user_id = ? AND movie_id = ?').bind(userId,id).run();}
  async listProgress(userId:string){const {results}=await this.db.prepare('SELECT data FROM progress WHERE user_id = ? ORDER BY updated_at DESC').bind(userId).all<{data:string}>();return results.map(r=>JSON.parse(r.data));}
  async putProgress(userId:string,entry:Progress){await this.db.prepare('INSERT INTO progress (user_id,movie_id,data,updated_at) VALUES (?,?,?,?) ON CONFLICT(user_id,movie_id) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at WHERE excluded.updated_at > progress.updated_at').bind(userId,entry.movieId,JSON.stringify(entry),entry.updatedAt).run();}
  async deleteAccount(userId:string){await this.db.prepare('DELETE FROM user WHERE id = ?').bind(userId).run();}
}
