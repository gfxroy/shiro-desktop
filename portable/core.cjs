'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFile} = require('node:child_process');

function endpoint(value) {
  const u = new URL(value);
  if (!['http:', 'https:'].includes(u.protocol) || !['localhost','127.0.0.1','[::1]'].includes(u.hostname) || u.username || u.password || u.search || u.hash || !['/v1','/v1/'].includes(u.pathname)) throw new Error('Use a loopback OpenAI-compatible endpoint ending in /v1.');
  return u.href.replace(/\/$/, '');
}
function relativeFile(value) {
  if (typeof value !== 'string' || value.length > 500 || value.includes('\\') || value.includes('\0') || value.startsWith('/') || /^[A-Za-z]:/.test(value) || value.split('/').some(x => x === '..')) throw new Error('Use a relative path inside the computer workspace.');
  return value;
}
function execute(file, args, {signal, timeout=65000, max=8*1024*1024, cwd, input}={}) {
  return new Promise((resolve,reject) => {
    const child=execFile(file,args,{signal,timeout,maxBuffer:max,windowsHide:true,cwd,env:process.env},(error,stdout,stderr) => {
    if (error) { reject(new Error(error.name === 'AbortError' ? 'Stopped.' : `${file === 'docker' ? 'Docker' : 'Command'} failed: ${String(stderr || error.message).slice(-1800)}`)); return; }
    resolve(stdout);
    });
    if(input!==undefined){child.stdin.on('error',()=>{});child.stdin.end(input);}
  });
}
const schema = (name,description,properties,required=Object.keys(properties)) => ({type:'function',function:{name,description,parameters:{type:'object',properties,required,additionalProperties:false}}});
const str = description => ({type:'string',description});
const tools = [
  schema('files_list','List workspace files.',{path:str('Workspace-relative folder; empty for root.')}),
  schema('files_read','Read a UTF-8 workspace file. Use the exact observed filename.',{path:str('Exact relative file path.'),offset:{type:'integer',minimum:0}}),
  schema('files_write','Write a UTF-8 file in the workspace. Requires user approval.',{path:str('Relative filename.'),content:str('Complete file content.')}),
  schema('search','Search the web in the container browser. Open sources before citing.',{query:str('Actual search terms.')}),
  schema('browser_open','Open an HTTP(S) source in the container Chromium.',{url:str('HTTP(S) URL.')}),
  schema('browser_read','Read actual browser page text and links.',{offset:{type:'integer',minimum:0}}),
  schema('browser_click','Click an exact selector observed in browser_read. Requires approval.',{selector:str('Exact observed selector.')}),
  schema('browser_fill','Fill an exact observed selector. Requires approval.',{selector:str('Exact observed selector.'),text:str('Text to enter.')}),
  schema('browser_key','Press a browser key. Requires approval.',{text:str('Key such as Return or Tab.')}),
  schema('shell','Run a Linux shell command only inside the container, with user approval.',{command:str('Linux command; 45 second limit.')}),
  schema('remember','Save a short durable note for the current bot. Never secrets.',{note:str('A concise preference or fact.')})
];
function toolPayload(name,args) {
  const def = tools.find(x => x.function.name === name)?.function;
  if (!def || !args || typeof args !== 'object' || Array.isArray(args)) throw new Error('Unknown tool or invalid arguments.');
  for (const k of def.parameters.required) {
    const type = def.parameters.properties[k].type;
    if ((type === 'string' && typeof args[k] !== 'string') || (type === 'integer' && (!Number.isSafeInteger(args[k]) || args[k]<0))) throw new Error(`Invalid ${k} for ${name}.`);
  }
  if (name.startsWith('files_')) { relativeFile(args.path); return {tool:'files',arguments:{...args,action:name.slice(6)}}; }
  if (name.startsWith('browser_')) {
    if (name === 'browser_open') { const u = new URL(args.url); if (!['http:','https:'].includes(u.protocol) || u.username || u.password) throw new Error('Use an HTTP(S) page URL without credentials.'); }
    return {tool:'browser',arguments:{...args,action:name === 'browser_open' ? 'navigate' : name.slice(8)}};
  }
  return {tool:name,arguments:args};
}
async function complete(config, messages, {signal,onProgress=()=>{}}={}) {
  const base = endpoint(config.endpoint);
  if (!config.model || config.model.toLowerCase().includes('cloud')) throw new Error('Select a downloaded local model. Cloud-routed models are not supported in this preview.');
  const body = {model:config.model,messages,tools,stream:true};
  body[config.runtime === 'liteRT' ? 'max_completion_tokens' : 'max_tokens'] = 1536;
  if (new URL(base).port === '11434' && config.model.toLowerCase().startsWith('qwen')) body.reasoning_effort = config.thinking ? 'medium' : 'none';
  const response = await fetch(base+'/chat/completions',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.any([...(signal?[signal]:[]),AbortSignal.timeout(180000)])});
  if (!response.ok) throw new Error(`Model HTTP ${response.status}: ${(await boundedText(response,16000)).slice(0,1200)}`);
  if (!(response.headers.get('content-type')||'').includes('text/event-stream')) {
    const data = JSON.parse(await boundedText(response)); const c=data.choices?.[0];
    if (!c || c.finish_reason === 'length' || (!c.message?.content && !c.message?.tool_calls?.length)) throw new Error('The model returned an incomplete or empty answer.');
    return c.message;
  }
  let buffer='',size=0,text='',finish=null,chunks=0; const calls=new Map(); const decoder=new TextDecoder();
  for await (const bytes of response.body) {
    size+=bytes.length; if(size>2_000_000) throw new Error('Model response too large.');
    buffer+=decoder.decode(bytes,{stream:true});
    let newline;
    while((newline=buffer.indexOf('\n'))>=0) {
      const line=buffer.slice(0,newline).trim(); buffer=buffer.slice(newline+1);
      if(!line.startsWith('data:'))continue;
      const raw=line.slice(5).trim(); if(raw==='[DONE]')continue;
      const event=JSON.parse(raw); if(event.error)throw new Error(event.error.message||String(event.error));
      const choice=event.choices?.[0]; if(!choice)continue;
      const delta=choice.delta||{}; text+=delta.content||'';
      for(const c of delta.tool_calls||[]) {
        if(!Number.isInteger(c.index)||c.index<0||c.index>127)throw new Error('Invalid tool stream index.');
        const old=calls.get(c.index)||{id:c.id||crypto.randomUUID(),type:'function',function:{name:'',arguments:''}};
        old.function.name+=c.function?.name||'';old.function.arguments+=c.function?.arguments||'';calls.set(c.index,old);
      }
      if(choice.finish_reason)finish=choice.finish_reason;
      onProgress(++chunks);
    }
    if(finish)break;
  }
  if(!['stop','tool_calls'].includes(finish)||(!text.trim()&&!calls.size))throw new Error('The model stream ended without a complete answer. No incomplete tool call was executed.');
  return {role:'assistant',content:text||null,...(calls.size?{tool_calls:[...calls.entries()].sort((a,b)=>a[0]-b[0]).map(x=>x[1])}:{})};
}
async function boundedText(response,max=2_000_000) {
  const chunks=[];let total=0;
  for await(const chunk of response.body){total+=chunk.length;if(total>max)throw new Error('Response too large.');chunks.push(Buffer.from(chunk));}
  return Buffer.concat(chunks).toString('utf8');
}
class Computer {
  constructor(directory){this.directory=directory;this.name='shiro-portable-v020';this.image='shiro-computer:0.2.0';this.password=null;}
  async inspect(){
    let items;try{items=JSON.parse(await execute('docker',['inspect',this.name],{timeout:5000}));}catch(e){return {ready:false,message:'Install and start Docker, then choose Set up computer.'};}
    const c=items[0];if(c.Config?.Labels?.['com.shirobot.portable']!=='0.2.0')throw new Error('That container name belongs to another application.');
    const binding=c.NetworkSettings?.Ports?.['6080/tcp']?.[0];
    if(c.State?.Running && binding?.HostIp==='127.0.0.1' && /^\d+$/.test(binding.HostPort)) {
      this.password=(c.Config.Env||[]).find(x=>x.startsWith('SHIRO_VNC_PASSWORD='))?.split('=')[1];
      return {ready:true,url:`http://127.0.0.1:${binding.HostPort}/vnc.html?autoconnect=1&resize=scale&view_only=0&password=${encodeURIComponent(this.password||'')}`};
    }
    return {ready:false,message:'Computer is stopped. Choose Set up computer to start it.'};
  }
  async setup(onProgress=()=>{}) {
    onProgress('Building the Linux computer. First setup downloads Debian and Chromium…');
    await execute('docker',['build','--tag',this.image,this.directory],{timeout:900000,max:32*1024*1024});
    let existing;try{existing=JSON.parse(await execute('docker',['inspect',this.name],{timeout:5000}))[0];}catch{}
    if(existing){if(existing.Config?.Labels?.['com.shirobot.portable']!=='0.2.0')throw new Error('Container name already in use.');await execute('docker',['start',this.name]);}
    else {
      this.password=crypto.randomBytes(6).toString('base64url').slice(0,8);
      await execute('docker',['run','-d','--name',this.name,'--label','com.shirobot.portable=0.2.0','--cpus','2','--memory','3g','--pids-limit','256','--shm-size','256m','--cap-drop','ALL','--security-opt','no-new-privileges:true','--mount','type=volume,src=shiro-portable-home,dst=/home/shiro-local','-p','127.0.0.1::6080','-e','SHIRO_VNC_PASSWORD='+this.password,this.image]);
    }
    return this.inspect();
  }
  async perform(name,args,{signal}={}) {
    if(!(await this.inspect()).ready)throw new Error('Set up the container computer before using tools.');
    const payload=toolPayload(name,args);
    const output=await execute('docker',['exec','--user','1000:1000','-e','DISPLAY=:88','-e','HOME=/home/shiro-local',this.name,'python3','/opt/shiro/guest.py',Buffer.from(JSON.stringify(payload)).toString('base64')],{signal});
    return JSON.parse(output.trim());
  }
  async export(file){relativeFile(file);const output=await execute('docker',['exec','--user','1000:1000',this.name,'python3','/opt/shiro/guest.py',Buffer.from(JSON.stringify({tool:'export',arguments:{path:file}})).toString('base64')]);const data=JSON.parse(output);if(data.error)throw new Error(data.error);return Buffer.from(data.data,'base64');}
}
async function saveState(file,state) {await fs.mkdir(path.dirname(file),{recursive:true,mode:0o700});const temp=file+'.tmp';await fs.writeFile(temp,JSON.stringify(state,null,2),{mode:0o600});await fs.rename(temp,file);}
module.exports={endpoint,relativeFile,execute,tools,toolPayload,complete,boundedText,Computer,saveState};
