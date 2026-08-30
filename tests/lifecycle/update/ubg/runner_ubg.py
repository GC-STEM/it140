#!/usr/bin/env python3
"""Black-box harness for Ubuntu GNOME update_ubg.sh lifecycle tests."""
from __future__ import annotations
from dataclasses import dataclass
import copy, hashlib, json, os
from pathlib import Path
import shutil, stat, subprocess, sys, tempfile
from typing import Any

REPO_ROOT=Path(__file__).resolve().parents[4]
UPDATE_SOURCE=REPO_ROOT/'scripts'/'nix'/'ubg'/'update_ubg.sh'
MANIFEST_SOURCE=REPO_ROOT/'scripts'/'.manifest'/'it140_manifest.json'
SCHEMA_SOURCE=REPO_ROOT/'scripts'/'.manifest'/'it140_manifest.schema.json'
BASH_EXECUTABLE=shutil.which('bash')

@dataclass
class UpdateTranscript:
    path:Path; text:str; summary:dict[str,str]
@dataclass
class UpdateRun:
    scenario_id:str; root:Path; returncode:int; stdout:str; stderr:str; home:Path; system_root:Path; log_dir:Path; log_file:Path|None; transcript:UpdateTranscript|None; protected_differences:list[str]; state_file:Path; trace_file:Path
    @property
    def combined_output(self)->str:
        sections=[]
        if (self.stdout+self.stderr).strip(): sections.append('Captured process output:\n'+(self.stdout+self.stderr).rstrip())
        if self.transcript and self.transcript.text.strip(): sections.append('Update transcript:\n'+self.transcript.text.rstrip())
        if self.trace_file.is_file() and self.trace_file.read_text().strip(): sections.append('Mock command trace:\n'+self.trace_file.read_text().rstrip())
        if self.state_file.is_file(): sections.append('Update test state:\n'+self.state_file.read_text().rstrip())
        return '\n\n'.join(sections)
@dataclass
class UpdateSequence:
    root:Path; first:UpdateRun; second:UpdateRun; first_state:dict[str,Any]; second_state:dict[str,Any]

def digest(p:Path)->str|None:
    if not p.exists() and not p.is_symlink(): return None
    if p.is_symlink(): return 'L:'+os.readlink(p)
    if p.is_file(): return hashlib.sha256(p.read_bytes()).hexdigest()
    vals=[]
    for c in sorted(p.rglob('*')):
        r=c.relative_to(p).as_posix()
        vals.append(('L '+r+' '+os.readlink(c)) if c.is_symlink() else ('F '+r+' '+hashlib.sha256(c.read_bytes()).hexdigest()) if c.is_file() else 'D '+r)
    return hashlib.sha256('\n'.join(vals).encode()).hexdigest()
def snapshot(paths:dict[str,Path])->dict[str,str|None]: return {k:digest(v) for k,v in paths.items()}
def parse_log(path:Path)->UpdateTranscript:
    text=path.read_text(encoding='utf-8',errors='replace'); summary={}; started=False
    keys={'Conclusion','Result','Script version','Manifest release','Manifest DTG','Warnings','Failures','Restart required','Managed changes','Elapsed time','Next step','Log file','Exit code'}
    summary_headings={'UPDATE SUMMARY','UPDATE COMPLETE','UPDATE COMPLETE — RESTART REQUIRED'}
    for raw in text.splitlines():
        line=raw.strip('\ufeff\r\n')
        if line in summary_headings: started=True; continue
        if started and ':' in line:
            k,v=line.split(':',1); k=k.strip()
            if k in keys: summary[k]=v.strip()
    return UpdateTranscript(path,text,summary)

class UbgUpdateHarness:
    def __init__(self,fixture_base:Path,mock_dispatcher:Path): self.fixture_base=fixture_base; self.mock_dispatcher=mock_dispatcher.resolve()
    @staticmethod
    def load_scenario(path:Path)->dict[str,Any]: return json.loads(path.read_text(encoding='utf-8'))
    @staticmethod
    def merge(a:dict[str,Any],b:dict[str,Any])->dict[str,Any]:
        out=copy.deepcopy(a)
        for k,v in b.items(): out[k]=UbgUpdateHarness.merge(out[k],v) if isinstance(v,dict) and isinstance(out.get(k),dict) else copy.deepcopy(v)
        return out
    @staticmethod
    def requirements(m:dict[str,Any])->tuple[list[str],list[str],list[str]]:
        p=m['platforms']['ubuntu_gnome']; b=p['course_ide_bindings']
        system={x['package_identifier'] for x in p.get('os_packages',{}).values() if x.get('required') and x.get('package_identifier')}
        venv=set(); ext=set()
        for role,x in b.items():
            if not x.get('required'): continue
            if x.get('installation_scope')=='system' and x.get('installer_adapter_id')=='apt_package': system.add(x['package_identifier'])
            if x.get('installation_scope')=='user' and x.get('installer_adapter_id')=='python_venv_package': venv.add(x['package_identifier'])
            if role=='code_quality_tool': venv.add('ruff')
            if x.get('installer_adapter_id')=='vscode_extension': ext.add(x['package_identifier'])
        return sorted(system),sorted(venv),sorted(ext)
    @classmethod
    def default_state(cls,m:dict[str,Any])->dict[str,Any]:
        system,venv,ext=cls.requirements(m)
        return {'sudo_valid':True,'installed_packages':system,'venv_packages':venv,'extensions':ext,'fail_points':{},'skip_venv_packages':[],'skip_extensions':[],'git_clone_count':0,'apt_update_count':0,'apt_upgrade_count':0,'pip_update_count':0,'extension_update_count':0}
    @staticmethod
    def wrapper(path:Path,name:str)->None:
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text('#!/usr/bin/env bash\n'+f"export IT140_MOCK_COMMAND={name!r}\n"+'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n',encoding='utf-8'); path.chmod(0o755)
    def prepare(self,temp:Path,scenario:dict[str,Any]):
        fixture=temp/'fixture'; shutil.copytree(self.fixture_base,fixture); home=fixture/'home'; system=fixture/'system'; course=home/'it140'; md=course/'scripts'/'.manifest'; pd=course/'scripts'/'nix'/'ubg'; md.mkdir(parents=True); pd.mkdir(parents=True)
        shutil.copy2(UPDATE_SOURCE,pd/UPDATE_SOURCE.name); shutil.copy2(MANIFEST_SOURCE,md/MANIFEST_SOURCE.name); shutil.copy2(SCHEMA_SOURCE,md/SCHEMA_SOURCE.name)
        fo=scenario.get('fixture_overrides',{})
        if fo.get('manifest')=='malformed': (md/MANIFEST_SOURCE.name).write_text('{ invalid\n',encoding='utf-8')
        if fo.get('os_release')=='unsupported': (system/'etc'/'os-release').write_text('ID=ubuntu\nVERSION_ID="22.04"\n',encoding='utf-8')
        if fo.get('reboot_required'):
            p=system/'var'/'run'/'reboot-required'; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('restart required\n')
        m=json.loads(MANIFEST_SOURCE.read_text(encoding='utf-8')); state=self.merge(self.default_state(m),scenario.get('mock_overrides',{}))
        # partial scenarios may deliberately begin without an item the update is expected to repair.
        for p in state.get('skip_venv_packages',[]):
            if p in state['venv_packages']: state['venv_packages'].remove(p)
        for e in state.get('skip_extensions',[]):
            if e in state['extensions']: state['extensions'].remove(e)
        state_path=temp/'state.json'; state_path.write_text(json.dumps(state,indent=2,sort_keys=True)+'\n')
        trace=temp/'trace.jsonl'; mock=temp/'mock-bin'; mock.mkdir()
        for name in ('git','sudo','dpkg-query','python3.12','code','sleep'): self.wrapper(mock/name,name)
        self.wrapper(course/'.venv'/'bin'/'python','venv-python')
        candidate=temp/'candidate'; (candidate/'scripts'/'.manifest').mkdir(parents=True)
        manifest_bytes=MANIFEST_SOURCE.read_bytes(); schema_bytes=SCHEMA_SOURCE.read_bytes()
        if fo.get('candidate_manifest')=='reformatted': manifest_bytes=(json.dumps(json.loads(manifest_bytes),separators=(',',':'))+'\n').encode()
        if fo.get('candidate_manifest')=='malformed': manifest_bytes=b'{ invalid candidate\n'
        (candidate/'scripts'/'.manifest'/'it140_manifest.json').write_bytes(manifest_bytes); (candidate/'scripts'/'.manifest'/'it140_manifest.schema.json').write_bytes(schema_bytes)
        return home,system,mock,state_path,trace,candidate
    @staticmethod
    def protected(home:Path)->dict[str,Path]: return {'student_work':home/'Repos'/'student-work','personal_desktop':home/'Desktop'/'Personal Notes.txt','unrelated_config':home/'.config'/'other-app'/'prefs.txt','git_config':home/'.gitconfig','bashrc':home/'.bashrc','profile':home/'.profile'}
    def env(self,home,system,mock,state,trace,candidate,temp):
        e=os.environ.copy(); tmp=temp/'tmp'; tmp.mkdir(exist_ok=True)
        e.update({'HOME':str(home),'TMPDIR':str(tmp),'PATH':str(mock)+os.pathsep+e.get('PATH',''),'IT140_UPDATE_TEST_MODE':'true','IT140_UPDATE_TEST_ROOT':str(system),'IT140_UPDATE_TEST_EUID':'1000','IT140_MOCK_STATE':str(state),'IT140_MOCK_TRACE':str(trace),'IT140_MOCK_BIN':str(mock),'IT140_MOCK_DISPATCHER':str(self.mock_dispatcher),'IT140_MOCK_PYTHON':sys.executable,'IT140_MOCK_REPOSITORY':str(candidate)})
        return e
    def execute(self,scenario,temp,home,system,mock,state,trace,candidate)->UpdateRun:
        before=snapshot(self.protected(home)); logdir=home/'it140'/'logs'; before_logs=set(logdir.glob('update_ubg_*.log')) if logdir.exists() else set()
        cp=subprocess.run([BASH_EXECUTABLE,str(home/'it140'/'scripts'/'nix'/'ubg'/'update_ubg.sh'),*scenario.get('arguments',[])],cwd=home,env=self.env(home,system,mock,state,trace,candidate,temp),text=True,capture_output=True,timeout=45,check=False)
        after=snapshot(self.protected(home)); diffs=sorted(k for k in before if before[k]!=after[k]); logs=sorted(set(logdir.glob('update_ubg_*.log'))-before_logs) if logdir.exists() else []; log=logs[-1] if logs else None; transcript=parse_log(log) if log else None
        return UpdateRun(scenario['id'],temp,cp.returncode,cp.stdout,cp.stderr,home,system,logdir,log,transcript,diffs,state,trace)
    def run(self,scenario:dict[str,Any])->UpdateRun:
        root=Path(tempfile.mkdtemp(prefix='it140-update-ubg-')); vals=self.prepare(root,scenario); return self.execute(scenario,root,*vals)
    def run_twice(self,scenario:dict[str,Any])->UpdateSequence:
        root=Path(tempfile.mkdtemp(prefix='it140-update-ubg-twice-')); vals=self.prepare(root,scenario); first=self.execute(scenario,root,*vals); first_state=json.loads(vals[3].read_text()); first_log=first.log_file
        # Ensure the second run gets its own timestamped transcript while keeping
        # the first UpdateRun object internally consistent for later assertions.
        if first_log:
            renamed_log=first_log.with_name(first_log.stem+'_first.log')
            first_log.rename(renamed_log)
            first.log_file=renamed_log
            if first.transcript:
                first.transcript.path=renamed_log
        second=self.execute(scenario,root,*vals); second_state=json.loads(vals[3].read_text()); return UpdateSequence(root,first,second,first_state,second_state)
