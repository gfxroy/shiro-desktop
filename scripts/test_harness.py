#!/usr/bin/env python3
"""Native app integration fixture. Requires an already running isolated Shiro Lima VM.
Runs a separate temporary profile; never reads the user's saved chats or contacts.
This checks harness behavior with a deterministic model, not model intelligence.
"""
import argparse
import json
import os
import plistlib
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
    request = f'Make a tailored CV for the specific Helio Robotics job from my saved candidate facts. Save it as {folder}/helio-cv.pdf. Use only supplied facts. Include my supplied education.'
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
            assert 'Requirements: Python services and model evaluation.' in body['messages'][-1]['content'], 'Reviewer lost observed job requirements'
            assert 'prior employer' in system, 'Reviewer must distinguish prior employment from the target'
            self.server.reviews+=1
            accepted=self.server.reviews>1
            if not accepted:
                prompt=body['messages'][-1]['content']
                actual=prompt.split('ACTUAL READ-BACK FILES:',1)[1].split('PROPOSED FINAL ANSWER:',1)[0]
                assert 'BSc Computer Science' not in actual, 'Fixture must expose a real omitted education entry'
                assert 'BSc Computer Science' in prompt.split('ACTUAL READ-BACK FILES:',1)[0], 'Reviewer needs the omitted original fact'
            self.reply(json.dumps(dict(accepted=accepted,issues=[] if accepted else ['The user explicitly requested the supplied education, but the read-back CV omits BSc Computer Science, 2022. Add that original fact unchanged.'])))
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
            self.tool('memory_facts', {'source_id':self.server.source,'offset':0})
        elif n in ((4,5,7,9) if self.server.scenario=='multi-cv' else (4,5,8)):
            if not hasattr(self.server,'fact_sections'):
                for message in reversed(body['messages']):
                    if message.get('role')!='tool':continue
                    try:result=json.loads(message.get('content','{}'))
                    except (ValueError,TypeError):continue
                    if result.get('facts'):
                        self.server.fact_sections=[{'heading':heading,'fact_ids':[f['fact_id'] for f in result['facts'] if f.get('section')==heading and not f.get('target_context')]} for heading in ['Skills','Experience','Education']]
                        break
            if not hasattr(self.server,'fact_sections'):
                saved=json.loads((self.server.profile/'state.json').read_text())
                for chat in saved['conversations']:
                    for item in reversed(chat['entries']):
                        if item['role']=='tool' and item['text'].startswith('memory_facts: '):
                            result=json.loads(item['text'].split(': ',1)[1])
                            if not result.get('facts'):continue
                            self.server.fact_sections=[{'heading':heading,'fact_ids':[f['fact_id'] for f in result['facts'] if f.get('section')==heading and not f.get('target_context')]} for heading in ['Skills','Experience','Education']]
                            break
            sections=json.loads(json.dumps(self.server.fact_sections))
            if n==4:sections[1]['fact_ids']=['invented-PhD-claim']
            if n==5:sections=[section for section in sections if section['heading']!='Education']
            is_second=self.server.scenario=='multi-cv' and n==7
            self.tool('cv_create',{'path':self.server.folder+('/nimbus-cv.pdf' if is_second else '/helio-cv.pdf'),'candidate_name':'Alex Example','target_role':'Applied AI Engineer','target_employer':'Nimbus Systems' if is_second else 'Helio Robotics','sections':sections})
        elif n==6:
            self.tool('files_read', {'path':self.server.folder+'/helio-cv.pdf','offset':0})
        else:
            self.reply('The tailored CV is ready.')
    def reply(self, text):
        self.send({'choices':[{'message':{'role':'assistant','content':text},'finish_reason':'stop'}]})
    def tool(self, name, arguments):
        self.send({'choices':[{'message':{'role':'assistant','content':None,'tool_calls':[{'id':'call_'+str(self.server.worker),'type':'function','function':{'name':name,'arguments':json.dumps(arguments)}}]},'finish_reason':'tool_calls'}]})

def run(app, scenario, root, keep=False):
    version=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    assert version==(ROOT/'VERSION').read_text().strip(), 'Build the current app before running this source-version integration test'
    server=ThreadingHTTPServer(('127.0.0.1',0),Fixture)
    server.scenario=scenario;server.worker=0;server.reviews=0;server.requests=[];server.folder='harness-fixture-'+uuid.uuid4().hex[:10]
    profile=root/scenario
    server.source, chat_id=fixture_profile(profile,scenario,'http://127.0.0.1:'+str(server.server_port)+'/v1',server.folder)
    server.profile=profile
    if scenario=='multi-cv':
        saved=json.loads((profile/'state.json').read_text())
        chat=saved['conversations'][0]
        request=f'Make 2 separate tailored CVs, one for each job: Applied AI Engineer at Helio Robotics and at Nimbus Systems. Save them as {server.folder}/helio-cv.pdf and {server.folder}/nimbus-cv.pdf. Use only supplied candidate facts. Include my supplied education.'
        chat.update(pendingTask=request,activeObjective=request);chat['entries'][0]['text']=request
        saved['conversations'][1]['entries'][0]['text']+=' Target employer: Nimbus Systems. Target role: Applied AI Engineer.'
        (profile/'state.json').write_text(json.dumps(saved))
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
            assert (server.reviews,server.worker)==((3,10) if scenario=='multi-cv' else (2,9)), (server.reviews,server.worker)
            if scenario=='multi-cv':
                assert len(chat['session']['cvProofs'])==2
                assert len(chat['session']['artifacts'])==2
            assert chat['session']['compactions']>=2
            assert chat['session']['phase']=='Completed'
            assert chat['session']['cvProofs'], 'Completed CV needs source proof and read-back hash'
            assert any('Unknown or target-only fact_id' in e['text'] for e in chat['entries']), 'Invented fact must be rejected before file writing'
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
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,default=ROOT/'dist/Shiro.app');parser.add_argument('--output',type=Path);parser.add_argument('--scenario',choices=['summary-failure','recovery-success','multi-cv','both'],default='both');parser.add_argument('--keep-open',action='store_true');args=parser.parse_args()
    root=Path(tempfile.mkdtemp(prefix='shiro-harness-'))
    scenarios=['summary-failure','recovery-success'] if args.scenario=='both' else [args.scenario]
    reports=[run(args.app,s,root,args.keep_open and s==scenarios[-1]) for s in scenarios]
    if args.output:args.output.write_text(json.dumps(reports,indent=2)+'\n')
    print('PASS: isolated native app → local model fixture → shared memory → real VM PDF → read-back → independent review → persisted outcome',flush=True)
