#!/usr/bin/env python3
"""Optional real local-model smoke test with synthetic data and a disposable profile.
Requires a built native app, running isolated Lima computer, and loopback model server.
"""
import argparse, json, os, subprocess, tempfile, time
from pathlib import Path
from test_harness import fixture_profile
p=argparse.ArgumentParser();p.add_argument('--model',required=True);p.add_argument('--endpoint',default='http://127.0.0.1:9379/v1');p.add_argument('--timeout',type=int,default=240);args=p.parse_args()
root=Path(tempfile.mkdtemp(prefix='shiro-live-model-'));profile=root/'profile'
_, chat_id=fixture_profile(profile,args.model,args.endpoint,'harness-live-synthetic')
state=json.loads((profile/'state.json').read_text());chat=state['conversations'][0]
request=chat['activeObjective']+' This is a synthetic integration fixture, not a real job application. The job description and candidate facts are already supplied in the other bot’s saved user message. Retrieve them. No browsing, external verification, submissions or messages are needed. Do not invent facts. Use files_pdf with path and content. Return the actual saved path when finished, or BLOCKED: with a concrete reason.'
chat.update(pendingTask=request,activeObjective=request);chat['entries'][0]['text']=request
state['configs'][0]['localRuntime']='liteRT';chat['pendingConfig']=state['configs'][0]
(profile/'state.json').write_text(json.dumps(state));log=open(root/'app.log','w')
app=Path(__file__).resolve().parents[1]/'dist/Shiro.app/Contents/MacOS/Shiro'
process=subprocess.Popen([str(app)],env=dict(os.environ,SHIRO_PROFILE_DIRECTORY=str(profile)),stdout=log,stderr=log)
print('Live synthetic profile: '+str(profile),flush=True)
try:
    deadline=time.monotonic()+args.timeout;last=None
    while time.monotonic()<deadline:
        if process.poll() is not None:raise RuntimeError('App exited')
        try:
            saved=json.loads((profile/'state.json').read_text());chat=next(c for c in saved['conversations'] if c['id']==chat_id)
            phase=chat.get('session',{}).get('phase')
            if phase!=last:print('Phase: '+str(phase),flush=True);last=phase
            if chat.get('lastRunOutcome') in ['blocked','completed','stopped']:break
        except (ValueError,FileNotFoundError):pass
        time.sleep(.25)
    report={'outcome':chat.get('lastRunOutcome'),'phase':chat.get('session',{}).get('phase'),'compactions':chat.get('session',{}).get('compactions'),'tools':[e['text'].split(':',1)[0] for e in chat['entries'] if e['role']=='tool'],'final':[e['text'][:1100] for e in chat['entries'][-4:] if e['role'] in ['assistant','system']]}
    (root/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
    if report['outcome']!='completed':raise SystemExit(1)
finally:
    process.terminate()
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:process.kill();process.wait()
    log.close()
