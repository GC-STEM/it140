#!/usr/bin/env python3
"""Black-box harness for macOS update_it140.zsh lifecycle tests."""
from __future__ import annotations
from dataclasses import dataclass
import copy, hashlib, json, os
from pathlib import Path
import shutil, subprocess, sys, tempfile, time, zipfile
from typing import Any

REPO_ROOT=Path(__file__).resolve().parents[4]
UPDATE_SOURCE=REPO_ROOT/'scripts'/'mac'/'update_it140.zsh'
MANIFEST_SOURCE=REPO_ROOT/'scripts'/'.manifest'/'it140_manifest.json'
SCHEMA_SOURCE=REPO_ROOT/'scripts'/'.manifest'/'it140_manifest.schema.json'
ZSH_EXECUTABLE=Path('/bin/zsh')
@dataclass
class UpdateTranscript: path:Path; text:str; summary:dict[str,str]
@dataclass
class UpdateRun:
    scenario_id:str; root:Path; returncode:int; stdout:str; stderr:str; home:Path; log_dir:Path; log_file:Path|None; transcript:UpdateTranscript|None; protected_differences:list[str]; trace_file:Path; state_file:Path; mock_dir:Path
    @property
    def combined_output(self):
        parts=[]; captured=self.stdout+self.stderr
        if captured.strip():parts.append('Captured process output:\n'+captured.rstrip())
        if self.transcript and self.transcript.text.strip():parts.append('Update transcript:\n'+self.transcript.text.rstrip())
        if self.trace_file.is_file() and self.trace_file.read_text().strip():parts.append('Mock command trace:\n'+self.trace_file.read_text().rstrip())
        if self.state_file.is_file():parts.append('Update test state:\n'+self.state_file.read_text().rstrip())
        return '\n\n'.join(parts)
@dataclass
class UpdateSequence: root:Path; first:UpdateRun; second:UpdateRun; first_state:dict[str,Any]; second_state:dict[str,Any]

def q(v:str)->str:return "'"+v.replace("'","'\"'\"'")+"'"
def digest(p:Path)->str|None:
    if not p.exists() and not p.is_symlink():return None
    if p.is_symlink():return 'L:'+os.readlink(p)
    if p.is_file():return hashlib.sha256(p.read_bytes()).hexdigest()
    rows=[]
    for c in sorted(p.rglob('*')):
        r=c.relative_to(p).as_posix(); rows.append(('L '+r+' '+os.readlink(c)) if c.is_symlink() else ('F '+r+' '+hashlib.sha256(c.read_bytes()).hexdigest()) if c.is_file() else 'D '+r)
    return hashlib.sha256('\n'.join(rows).encode()).hexdigest()
def snap(d):return {k:digest(v) for k,v in d.items()}
def parse_log(path:Path)->UpdateTranscript:
    text=path.read_text(encoding='utf-8',errors='replace'); s={}; on=False
    accepted={'Result','Artifact ID','Artifact version','Version date-time group','Development status','Manifest release','Manifest release DTG','Deployment profile','Workflow','Starting state','Operating role','Managed changes','Warnings','Failures','Elapsed time','Detail','Next step','Log file','Exit code'}
    summary_headings={'IT 140 macOS UPDATE SUMMARY','IT 140 macOS UPDATE COMPLETE'}
    for raw in text.splitlines():
        line=raw.strip('\ufeff\r\n')
        if line in summary_headings:on=True;continue
        if on and ':' in line:
            k,v=line.split(':',1);k=k.strip()
            if k in accepted:s[k]=v.strip()
    return UpdateTranscript(path,text,s)

class MacUpdateHarness:
    def __init__(self,fixture:Path,mock:Path):self.fixture=fixture;self.mock=mock.resolve()
    @staticmethod
    def load_scenario(p:Path):return json.loads(p.read_text())
    @staticmethod
    def merge(a,b):
        o=copy.deepcopy(a)
        for k,v in b.items():o[k]=MacUpdateHarness.merge(o[k],v) if isinstance(v,dict) and isinstance(o.get(k),dict) else copy.deepcopy(v)
        return o
    @staticmethod
    def requirements(m):
        b=m['platforms']['macos']['course_ide_bindings']; formula=[];cask=[];cmds={};venv=set();ext=set()
        for role,x in b.items():
            if not x.get('required'):continue
            adapter=x.get('installer_adapter_id'); pkg=x.get('package_identifier'); names=list(x.get('verification',{}).get('executable_names',[]))
            if x.get('installation_scope')=='system' and adapter=='homebrew_formula':formula.append(pkg);cmds[pkg]=names
            if x.get('installation_scope')=='system' and adapter=='homebrew_cask':cask.append(pkg);cmds[pkg]=names
            if x.get('installation_scope')=='user' and adapter=='python_venv_package':venv.add(pkg)
            if role=='code_quality_tool':venv.add('ruff')
            if adapter=='vscode_extension':ext.add(pkg)
        return sorted(formula),sorted(cask),cmds,sorted(venv),sorted(ext)
    def default_state(self):
        m=json.loads(MANIFEST_SOURCE.read_text());f,c,cmd,v,e=self.requirements(m)
        return {'installed_formulas':f,'installed_casks':c,'package_commands':cmd,'outdated_formulas':[],'outdated_casks':[],'venv_packages':v,'extensions':e,'fail_points':{},'skip_venv_packages':[],'skip_extensions':[],'brew_update_count':0,'brew_upgrade_count':0,'pip_update_count':0,'extension_update_count':0}
    def wrapper(self,path:Path,name:str):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text('#!/bin/zsh\n'+f"exec {q(str(Path(sys.executable).resolve()))} {q(str(self.mock))} {q(name)} \"$@\"\n",encoding='utf-8');path.chmod(0o755)
    def build_archive(self,path:Path,mode:str):
        mb=MANIFEST_SOURCE.read_bytes();sb=SCHEMA_SOURCE.read_bytes()
        if mode=='reformatted':mb=(json.dumps(json.loads(mb),separators=(',',':'))+'\n').encode()
        elif mode=='malformed':mb=b'{ invalid candidate\n'
        with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('it140-main/scripts/.manifest/it140_manifest.json',mb);z.writestr('it140-main/scripts/.manifest/it140_manifest.schema.json',sb)
    def prepare(self,temp:Path,scenario):
        fixture=temp/'fixture';shutil.copytree(self.fixture,fixture,symlinks=True);home=fixture/'home';course=home/'it140';md=course/'scripts'/'.manifest';pd=course/'scripts'/'mac';md.mkdir(parents=True);pd.mkdir(parents=True)
        shutil.copy2(UPDATE_SOURCE,pd/UPDATE_SOURCE.name);shutil.copy2(MANIFEST_SOURCE,md/MANIFEST_SOURCE.name);shutil.copy2(SCHEMA_SOURCE,md/SCHEMA_SOURCE.name)
        fo=scenario.get('fixture_overrides',{})
        if fo.get('manifest')=='malformed':(md/MANIFEST_SOURCE.name).write_text('{ invalid\n')
        state=self.merge(self.default_state(),scenario.get('mock_overrides',{}))
        for p in state.get('skip_venv_packages',[]):
            if p in state['venv_packages']:state['venv_packages'].remove(p)
        for e in state.get('skip_extensions',[]):
            if e in state['extensions']:state['extensions'].remove(e)
        statep=temp/'state.json';statep.write_text(json.dumps(state,indent=2,sort_keys=True)+'\n');trace=temp/'trace.jsonl';mock=temp/'mock-bin';mock.mkdir()
        self.wrapper(mock/'brew','brew');self.wrapper(mock/'code','code');self.wrapper(course/'.venv'/'bin'/'python','venv-python')
        for pkg,names in state.get('package_commands',{}).items():
            for name in names:
                if name:self.wrapper(mock/name,name)
        for name in ('date','id','uname'):
            real=shutil.which(name)
            if not real:raise RuntimeError(f'missing macOS host command: {name}')
            p=mock/name
            if not p.exists():p.symlink_to(Path(real).resolve())
        archive=temp/'it140-main.zip';self.build_archive(archive,fo.get('candidate_manifest','same'))
        return home,mock,statep,trace,archive
    @staticmethod
    def protected(home):return {'student_work':home/'Repos'/'student-work','personal_desktop':home/'Desktop'/'Personal Notes.txt','unrelated_app':home/'Library'/'Application Support'/'Other App'/'prefs.txt','git_config':home/'.gitconfig'}
    def env(self,home,mock,state,trace,archive,scenario):
        e=os.environ.copy();e.update({'HOME':str(home),'PATH':str(mock),'IT140_UPDATE_TEST_MODE':'true','IT140_UPDATE_TEST_BREW_PATH':str(mock/'brew'),'IT140_UPDATE_TEST_NETWORK_RESULT':scenario.get('network_result','success'),'IT140_UPDATE_TEST_ADMIN_RESULT':scenario.get('admin_result','true'),'IT140_UPDATE_TEST_ARCHIVE_PATH':str(archive),'IT140_UPDATE_TEST_DOWNLOAD_RESULT':scenario.get('download_result','success'),'IT140_MOCK_STATE':str(state),'IT140_MOCK_TRACE':str(trace),'IT140_MOCK_BIN':str(mock),'IT140_MOCK_DISPATCHER':str(self.mock),'IT140_MOCK_PYTHON':str(Path(sys.executable).resolve())});return e
    def execute(self,scenario,temp,home,mock,state,trace,archive):
        before=snap(self.protected(home));logdir=home/'it140'/'logs';old=set(logdir.glob('update_ide_*.log')) if logdir.exists() else set(); out=temp/f'out-{time.time_ns()}';err=temp/f'err-{time.time_ns()}'
        with out.open('w') as o,err.open('w') as er:
            cp=subprocess.run([str(ZSH_EXECUTABLE),str(home/'it140'/'scripts'/'mac'/'update_it140.zsh'),*scenario.get('arguments',[])],cwd=home,env=self.env(home,mock,state,trace,archive,scenario),text=True,stdout=o,stderr=er,timeout=60,check=False)
        after=snap(self.protected(home));logs=sorted(set(logdir.glob('update_ide_*.log'))-old) if logdir.exists() else [];log=logs[-1] if logs else None
        if log:
            for _ in range(60):
                if 'Exit code' in log.read_text(encoding='utf-8',errors='replace'):break
                time.sleep(.05)
        tr=parse_log(log) if log else None
        return UpdateRun(scenario['id'],temp,cp.returncode,out.read_text(),err.read_text(),home,logdir,log,tr,sorted(k for k in before if before[k]!=after[k]),trace,state,mock)
    def run(self,scenario):
        root=Path(tempfile.mkdtemp(prefix='it140-update-mac-'));return self.execute(scenario,root,*self.prepare(root,scenario))
    @staticmethod
    def semantic(run):
        s=json.loads(run.state_file.read_text());settings=run.home/'Library'/'Application Support'/'Code'/'User'/'settings.json'
        return {'installed_formulas':s.get('installed_formulas',[]),'installed_casks':s.get('installed_casks',[]),'outdated_formulas':s.get('outdated_formulas',[]),'outdated_casks':s.get('outdated_casks',[]),'venv_packages':s.get('venv_packages',[]),'extensions':s.get('extensions',[]),'settings':json.loads(settings.read_text()) if settings.is_file() else None}
    def run_twice(self,scenario):
        root=Path(tempfile.mkdtemp(prefix='it140-update-mac-twice-'));vals=self.prepare(root,scenario);first=self.execute(scenario,root,*vals);a=self.semantic(first);time.sleep(1.05);second=self.execute(scenario,root,*vals);b=self.semantic(second);return UpdateSequence(root,first,second,a,b)
