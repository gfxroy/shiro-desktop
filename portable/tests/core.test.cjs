const {test}=require('node:test');const assert=require('node:assert/strict');const http=require('node:http');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');
const {endpoint,relativeFile,toolPayload,complete,execute,saveState}=require('../core.cjs');
test('model endpoints reject remote hosts, credentials, queries and non-HTTP schemes',()=>{
 for(const u of ['https://example.com/v1','http://127.0.0.1:1234/v1?x=1','file:///v1','http://user:pass@localhost/v1','http://127.0.0.1:99/admin'])assert.throws(()=>endpoint(u));
 assert.equal(endpoint('http://127.0.0.1:11434/v1/'),'http://127.0.0.1:11434/v1');assert.ok(endpoint('http://[::1]:9000/v1'));
});
test('workspace paths and tool arguments reject traversal, absolute paths and invalid operations',()=>{
 for(const p of ['../secret','a/../../b','/etc/passwd','C:/Users/me','a\\b','x\0z'])assert.throws(()=>relativeFile(p));
 assert.equal(relativeFile('attachments/uuid/file.txt'),'attachments/uuid/file.txt');
 assert.throws(()=>toolPayload('files_read',{path:'safe',offset:-1}));assert.throws(()=>toolPayload('host_shell',{command:'echo no'}));assert.throws(()=>toolPayload('browser_open',{url:'file:///etc/passwd'}));
 assert.deepEqual(toolPayload('files_write',{path:'out.txt',content:'hi'}),{tool:'files',arguments:{path:'out.txt',content:'hi',action:'write'}});
});
async function fixture(t,handler){const server=http.createServer(handler);await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>server.close(r)));return {endpoint:`http://127.0.0.1:${server.address().port}/v1`,model:'fixture'};}
test('streamed tool arguments are assembled and text stays separate',async t=>{
 const config=await fixture(t,(req,res)=>{res.writeHead(200,{'content-type':'text/event-stream'});const frames=[{choices:[{delta:{tool_calls:[{index:0,id:'c1',function:{name:'files_read',arguments:'{"pa'}}]},finish_reason:null}]},{choices:[{delta:{tool_calls:[{index:0,function:{arguments:'th":"report.txt","offset":0}'}}]},finish_reason:null}]},{choices:[{delta:{},finish_reason:'tool_calls'}]}];res.end(frames.map(f=>'data: '+JSON.stringify(f)+'\n\n').join('')+'data: [DONE]\n\n');});
 const reply=await complete(config,[{role:'user',content:'Read the report'}]);assert.equal(reply.tool_calls[0].id,'c1');assert.equal(JSON.parse(reply.tool_calls[0].function.arguments).path,'report.txt');
});
test('truncated tool calls and empty answers never produce executable replies',async t=>{
 const config=await fixture(t,(_,res)=>{res.writeHead(200,{'content-type':'text/event-stream'});res.end('data: '+JSON.stringify({choices:[{delta:{tool_calls:[{index:0,function:{name:'shell',arguments:'{"command":"incomplete'}}]}}]})+'\n\n');});
 await assert.rejects(complete(config,[]),/complete answer/);
});
test('plain JSON compatibility and HTTP failures are handled',async t=>{
 let fail=false;const config=await fixture(t,(_,res)=>{res.writeHead(fail?503:200,{'content-type':'application/json'});res.end(JSON.stringify(fail?{error:'busy'}:{choices:[{message:{role:'assistant',content:'Hello'},finish_reason:'stop'}]}));});
 assert.equal((await complete(config,[])).content,'Hello');fail=true;await assert.rejects(complete(config,[]),/503/);
});
test('cloud-routed models are rejected before sending',async()=>{await assert.rejects(complete({endpoint:'http://127.0.0.1:11434/v1',model:'gemma4:cloud'},[]),/Cloud-routed/);});
test('state saves atomically and process input travels on stdin',async t=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'shiro-portable-test-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));const file=path.join(dir,'state.json');await saveState(file,{bots:['one']});assert.deepEqual(JSON.parse(await fs.readFile(file,'utf8')),{bots:['one']});
 const result=await execute(process.execPath,['-e','process.stdin.pipe(process.stdout)'],{input:Buffer.from('exact input')});assert.equal(result,'exact input');
});
