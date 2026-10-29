import {test} from 'node:test';
import assert from 'node:assert/strict';
import {app} from '../src/index.ts';
test('health responds even before cloud credentials are configured',async()=>{
 const response=await app.request('/health',{},{});
 assert.equal(response.status,200); assert.equal((await response.json() as any).name,'KomeCine');
});
test('authentication fails safely if OAuth credentials are not configured',async()=>{
 const response=await app.request('/api/auth/get-session',{},{});
 assert.equal(response.status,503);
});
