import {betterAuth} from 'better-auth';
import {bearer} from 'better-auth/plugins';
import {drizzleAdapter} from '@better-auth/drizzle-adapter';
import {drizzle} from 'drizzle-orm/d1';
import * as schema from './schema.ts';
export type Env={DB:D1Database; GOOGLE_CLIENT_ID:string; GOOGLE_CLIENT_SECRET:string; BETTER_AUTH_SECRET:string; BETTER_AUTH_URL:string};
export function configured(env:Partial<Env>|undefined):env is Env {return !!(env?.DB && env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && env.BETTER_AUTH_SECRET && env.BETTER_AUTH_URL);}
export function createAuth(env:Env){return betterAuth({baseURL:env.BETTER_AUTH_URL,secret:env.BETTER_AUTH_SECRET,database:drizzleAdapter(drizzle(env.DB,{schema}),{provider:'sqlite',schema}),socialProviders:{google:{clientId:env.GOOGLE_CLIENT_ID,clientSecret:env.GOOGLE_CLIENT_SECRET}},plugins:[bearer()],user:{deleteUser:{enabled:false}}});}
