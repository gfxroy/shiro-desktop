#!/usr/bin/env python3
"""Native app integration fixture. Requires an already running isolated Shiro Lima VM.
Runs a separate temporary profile; never reads the user's saved chats or contacts.
This checks harness behavior with a deterministic model, not model intelligence.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]

def identifier():
    return str(uuid.uuid4()).upper()

def entry(role, text):
    return dict(id=identifier(), role=role, text=text, date=time.time()-978307200)

def fixture_profile(path, model, endpoint, folder):
    manager, researcher = identifier(), identifier()
    source = entry('user', 'Synthetic candidate Alex Example. Skills: Python, SQL, model evaluation. Experience: built Python APIs at Example Labs during 2023–2025. Education: BSc Computer Science, 2022. Target employer Helio Robotics, Applied AI Engineer. Target job supplied by user: https://example.com/careers/42. Requirements: Python services and model evaluation. No doctorate or other qualifications supplied.')
    request = f'Make a tailored CV for the specific Helio Robotics job from my saved candidate facts. Save it as {folder}/helio-cv.pdf. Use only supplied facts.'
    config = dict(provider='local', model=model, endpoint=endpoint, vision=False)
    chat = dict(id=identifier(), title='Harness fixture', botID=manager, entries=[entry('user', request)], wire=[dict(role='user', content='Older filler ' * 4000)], wireProvider='local:'+model+':'+endpoint, updated=time.time()-978307200, pendingTask=request, pendingConfig=config, activeObjective=request, lastRunOutcome='running')
    state = dict(conversations=[chat, dict(id=identifier(), title='Candidate and target supplied earlier', botID=researcher, entries=[source], wire=[], wireProvider='', updated=time.time()-978307200-3600)], bots=[dict(id=manager, name='Harness manager', instructions='', memory='', pinned=True), dict(id=researcher, name='Researcher', instructions='', memory='', pinned=False)], configs=[config], provider='local', memory='Use only confirmed candidate facts.', routines=[], vmName='shiro-local', askBeforeActions=True, maxSteps=24, projects=[], selectedChatID=chat['id'])
    path.mkdir(mode=0o700)
    (path/'state.json').write_text(json.dumps(state))
    return source['id'], chat['id']

class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def send(self, data, status=200):
        body=json.dumps(data).encode()
        self.send_response(status); self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def do_GET(self):
        self.send({'data':[{'id':self.server.scenario}]})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.requests.append(body)
        system=body['messages'][0]['content']
        if 'independent quality reviewer' in system:
            assert not body.get('tools'), 'Reviewer must have no tools'
            assert body['max_tokens']==512
            self.server.reviews+=1
            accepted=self.server.reviews>1
            self.reply(json.dumps(dict(accepted=accepted,issues=[] if accepted else ['Unsupported doctorate claim; source has only a BSc. Remove it.'])))
            return
        self.server.worker+=1
        n=self.server.worker
        if self.server.scenario=='summary-failure':
            self.reply('The Applied AI Engineer role involves Python, evaluation and deploying AI systems. This is a role summary, not a saved CV.')
            return
        assert 'Helio Robotics' in system, 'Automatic retrieval lost the employer'
        assert 'memory_search' in [t['function']['name'] for t in body['tools']]
        if n==1:
            self.send({'error':{'message':'maximum number of tokens exceeded: context window'}},400)
        elif n==2:
            self.tool('memory_search', {'query':'Alex Example Helio Robotics candidate skills education employer target job'})
        elif n==3:
            self.tool('memory_read', {'source_id':self.server.source,'offset':0})
        elif n==5:
            self.tool('files_read', {'path':self.server.folder+'/helio-cv.pdf','offset':0})
        elif n in (4,7):
            text='# Alex Example\n\nApplied AI Engineer — Helio Robotics\n\n# Skills\n\nPython, SQL, model evaluation.\n\n# Experience\n\nExample Labs, 2023–2025. Built Python APIs. Relevant to Python services and model evaluation in the target role.\n\n# Education\n\nBSc Computer Science, 2022.'
            if n==4: text+='\n\nPhD in Artificial Intelligence, 2024.'
            self.tool('files_pdf',{'path':self.server.folder+'/helio-cv.pdf','content':text})
        else:
            self.reply('The tailored CV is ready.')
    def reply(self, text):
        self.send({'choices':[{'message':{'role':'assistant','content':text},'finish_reason':'stop'}]})
    def tool(self, name, arguments):
        self.send({'choices':[{'message':{'role':'assistant','content':None,'tool_calls':[{'id':'call_'+str(self.server.worker),'type':'function','function':{'name':name,'arguments':json.dumps(arguments)}}]},'finish_reason':'tool_calls'}]})

def run(app, scenario, root, keep=False):
    server=ThreadingHTTPServer(('127.0.0.1',0),Fixture)
    server.scenario=scenario;server.worker=0;server.reviews=0;server.requests=[];server.folder='harness-fixture-'+uuid.uuid4().hex[:10]
    profile=root/scenario
    server.source, chat_id=fixture_profile(profile,scenario,'http://127.0.0.1:'+str(server.server_port)+'/v1',server.folder)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    env=dict(os.environ, SHIRO_PROFILE_DIRECTORY=str(profile))
    log=open(root/(scenario+'.log'),'w')
    process=subprocess.Popen([str(app/'Contents/MacOS/Shiro')],env=env,stdout=log,stderr=log)
    try:
        deadline=time.monotonic()+90
        chat=None
        while time.monotonic()<deadline:
            if process.poll() is not None: raise RuntimeError('Fixture app exited; see '+str(log.name))
            try:
                saved=json.loads((profile/'state.json').read_text());chat=next(c for c in saved['conversations'] if c['id']==chat_id)
                if chat.get('lastRunOutcome') in ('blocked','completed','stopped'):break
            except (ValueError,FileNotFoundError):pass
            time.sleep(.25)
        assert chat and chat.get('lastRunOutcome') in ('blocked','completed'), 'Run did not terminate within 90s'
        if scenario=='summary-failure':
            assert chat['lastRunOutcome']=='blocked', 'Summary incorrectly marked complete'
            assert server.worker==3 and server.reviews==0
            assert not chat['session']['artifacts']
        else:
            assert chat['lastRunOutcome']=='completed', str([(e['role'],e['text'][:350]) for e in chat['entries'][-4:]])
            assert server.reviews==2 and server.worker==8
            assert chat['session']['compactions']>=2
            assert chat['session']['phase']=='Completed'
            assert any('Independent review passed' in e['text'] for e in chat['entries'])
            assert any(e.get('attachments') for e in chat['entries']), 'Verified output must be openable in chat'
            workers=[r for r in server.requests if r.get('tools')]
            assert len(json.dumps(workers[1]['messages']))<len(json.dumps(workers[0]['messages'])), 'Context retry did not shrink history'
        report={'scenario':scenario,'outcome':chat['lastRunOutcome'],'worker_requests':server.worker,'review_requests':server.reviews,'compactions':chat['session']['compactions'],'profile':str(profile),'workspace_folder':server.folder}
        print(json.dumps(report),flush=True)
        return report
    finally:
        if not keep:
            process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        server.shutdown();log.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,default=ROOT/'dist/Shiro.app');parser.add_argument('--output',type=Path);parser.add_argument('--scenario',choices=['summary-failure','recovery-success','both'],default='both');parser.add_argument('--keep-open',action='store_true');args=parser.parse_args()
    root=Path(tempfile.mkdtemp(prefix='shiro-harness-'))
    scenarios=['summary-failure','recovery-success'] if args.scenario=='both' else [args.scenario]
    reports=[run(args.app,s,root,args.keep_open and s==scenarios[-1]) for s in scenarios]
    if args.output:args.output.write_text(json.dumps(reports,indent=2)+'\n')
    print('PASS: isolated native app → local model fixture → shared memory → real VM PDF → read-back → independent review → persisted outcome',flush=True)
