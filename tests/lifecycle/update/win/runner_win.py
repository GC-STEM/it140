#!/usr/bin/env python3
"""Black-box harness for Windows update_it140.ps1 lifecycle tests."""
from __future__ import annotations
import copy, json, os, shutil, subprocess, sys, tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

LIFECYCLE_ROOT=Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path: sys.path.insert(0,str(LIFECYCLE_ROOT))
from common.configure_log import ConfigureTranscript, parse_configure_log  # noqa:E402
from common.snapshot import snapshot_differences, snapshot_paths  # noqa:E402
REPO_ROOT=LIFECYCLE_ROOT.parents[1]
UPDATE_SOURCE=REPO_ROOT/'scripts'/'win'/'update_it140.ps1'
MANIFEST_SOURCE=REPO_ROOT/'scripts'/'.manifest'/'it140_manifest.json'
SCHEMA_SOURCE=REPO_ROOT/'scripts'/'.manifest'/'it140_manifest.schema.json'
POWERSHELL_EXECUTABLE=shutil.which('powershell.exe') or shutil.which('powershell')

@dataclass
class UpdateRun:
    scenario_id:str; root:Path; returncode:int; stdout:str; stderr:str; home:Path; log_dir:Path; log_file:Path|None; transcript:ConfigureTranscript|None; protected_differences:list[str]; state_path:Path
    @property
    def combined_output(self)->str:
        parts=[]; captured=self.stdout+self.stderr
        if captured.strip():parts.append('Captured process output:\n'+captured.rstrip())
        if self.transcript and self.transcript.text.strip():parts.append('Update transcript:\n'+self.transcript.text.rstrip())
        if self.state_path.is_file():parts.append('Update test state:\n'+self.state_path.read_text(encoding='utf-8',errors='replace').rstrip())
        return '\n\n'.join(parts)
@dataclass
class UpdateSequence:
    root:Path; first:UpdateRun; second:UpdateRun; first_state:dict[str,Any]; second_state:dict[str,Any]

class WinUpdateHarness:
    def __init__(self,fixture_base:Path):self.fixture_base=fixture_base
    @staticmethod
    def load_scenario(path:Path)->dict[str,Any]:return json.loads(path.read_text(encoding='utf-8'))
    @staticmethod
    def merge(base:dict[str,Any],overrides:dict[str,Any])->dict[str,Any]:
        out=copy.deepcopy(base)
        for k,v in overrides.items():out[k]=WinUpdateHarness.merge(out[k],v) if isinstance(v,dict) and isinstance(out.get(k),dict) else copy.deepcopy(v)
        return out
    @staticmethod
    def bindings(manifest:dict[str,Any])->list[dict[str,Any]]:
        out=[]
        for role,b in manifest['platforms']['windows']['course_ide_bindings'].items():
            if b.get('required') and b.get('installation_scope')=='system' and b.get('installer_adapter_id')=='winget_package':
                out.append({'role':role,'package_identifier':str(b['package_identifier']),'executable_names':[str(x) for x in b.get('verification',{}).get('executable_names',[])]})
        return out
    @staticmethod
    def venv_packages(manifest:dict[str,Any])->list[str]:
        b=manifest['platforms']['windows']['course_ide_bindings']; vals=set()
        for role,x in b.items():
            if x.get('required') and x.get('installation_scope')=='user' and x.get('installer_adapter_id')=='python_venv_package': vals.add(str(x['package_identifier']))
            if role=='code_quality_tool' and x.get('required'): vals.add('ruff')
        return sorted(vals)
    @staticmethod
    def extensions(manifest:dict[str,Any])->list[str]:
        b=manifest['platforms']['windows']['course_ide_bindings']
        return sorted({str(x['package_identifier']) for x in b.values() if x.get('required') and x.get('installation_scope')=='user' and x.get('installer_adapter_id')=='vscode_extension'})
    @classmethod
    def default_state(cls,manifest:dict[str,Any])->dict[str,Any]:
        bindings=cls.bindings(manifest); cmds={'git.exe','winget.exe','gh.exe','python.exe','code.cmd'}
        for b in bindings:cmds.update(b['executable_names'])
        return {
            'is_administrator':False,
            'windows_facts':{'Caption':'Microsoft Windows 11 Pro','Architecture':'64-bit','DisplayVersion':'26H1','BuildNumber':'28000'},
            'available_commands':sorted(cmds),'free_space_bytes':20*1024**3,'configuration_complete':True,
            'winget_packages':sorted(b['package_identifier'] for b in bindings),'venv_python_version':'3.12',
            'venv_packages':cls.venv_packages(manifest),'extensions':cls.extensions(manifest),'managed_integration':True,
            'candidate_manifest_changed':False,'skip_venv_packages':[],'skip_extensions':[],'fail_points':{}
        }
    @staticmethod
    def protected(home:Path)->dict[str,Path]:
        return {'student_repos':home/'Repos','personal_desktop':home/'Desktop'/'Personal Notes.txt','unrelated_app':home/'AppData'/'Roaming'/'Other App','git_config':home/'.gitconfig'}
    @staticmethod
    def setenv(env:dict[str,str],name:str,value:str)->None:
        for key in list(env):
            if key.casefold()==name.casefold():del env[key]
        env[name]=value
    def prepare(self,temp:Path,scenario:dict[str,Any]):
        fixture=temp/'fixture';shutil.copytree(self.fixture_base,fixture);home=fixture/'home';course=home/'it140';md=course/'scripts'/'.manifest';wd=course/'scripts'/'win';md.mkdir(parents=True);wd.mkdir(parents=True)
        # Update validates all Windows lifecycle scripts after asset activation; retain the current qualified production copies.
        source_win=UPDATE_SOURCE.parent
        for name in ('install_it140.ps1','configure_it140.ps1','verify_it140.ps1','update_it140.ps1'):
            src=source_win/name
            if src.is_file():shutil.copy2(src,wd/name)
        shutil.copy2(MANIFEST_SOURCE,md/MANIFEST_SOURCE.name);shutil.copy2(SCHEMA_SOURCE,md/SCHEMA_SOURCE.name)
        if scenario.get('fixture_overrides',{}).get('manifest')=='malformed':(md/MANIFEST_SOURCE.name).write_text('{ invalid\n',encoding='utf-8')
        manifest=json.loads(MANIFEST_SOURCE.read_text(encoding='utf-8'));state=self.merge(self.default_state(manifest),scenario.get('mock_overrides',{}))
        for p in state.get('skip_venv_packages',[]):
            if p in state['venv_packages']:state['venv_packages'].remove(p)
        for e in state.get('skip_extensions',[]):
            if e in state['extensions']:state['extensions'].remove(e)
        state_path=temp/'state.json';state_path.write_text(json.dumps(state,indent=2,sort_keys=True)+'\n',encoding='utf-8')
        appdata=home/'AppData'/'Roaming';(appdata/'Code'/'User').mkdir(parents=True,exist_ok=True)
        (appdata/'Code'/'User'/'settings.json').write_text('{"it140.unmanaged":"preserve-me"}\n',encoding='utf-8')
        return home,state_path
    def execute(self,scenario:dict[str,Any],root:Path,home:Path,state_path:Path)->UpdateRun:
        if POWERSHELL_EXECUTABLE is None:raise RuntimeError('Windows PowerShell executable was not found')
        before=snapshot_paths(self.protected(home));logdir=home/'it140'/'logs';before_logs=set(logdir.glob('update_win_*.log')) if logdir.exists() else set()
        env=os.environ.copy();self.setenv(env,'IT140_UPDATE_TEST_MODE','true');self.setenv(env,'IT140_UPDATE_TEST_STATE',str(state_path));self.setenv(env,'HOME',str(home));self.setenv(env,'USERPROFILE',str(home));self.setenv(env,'APPDATA',str(home/'AppData'/'Roaming'))
        cp=subprocess.run([POWERSHELL_EXECUTABLE,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(home/'it140'/'scripts'/'win'/'update_it140.ps1'),'-NonInteractive',*scenario.get('arguments',[])],capture_output=True,text=True,timeout=60,check=False,env=env)
        logs=sorted(set(logdir.glob('update_win_*.log'))-before_logs) if logdir.exists() else [];log=logs[-1] if logs else None;tr=parse_configure_log(log) if log else None
        after=snapshot_paths(self.protected(home));diff=snapshot_differences(before,after)
        return UpdateRun(scenario['id'],root,cp.returncode,cp.stdout,cp.stderr,home,logdir,log,tr,diff,state_path)
    def run(self,scenario:dict[str,Any])->UpdateRun:
        root=Path(tempfile.mkdtemp(prefix='it140-update-win-'));home,state=self.prepare(root,scenario);return self.execute(scenario,root,home,state)
    def run_twice(self,scenario:dict[str,Any])->UpdateSequence:
        root=Path(tempfile.mkdtemp(prefix='it140-update-win-twice-'));home,state=self.prepare(root,scenario);first=self.execute(scenario,root,home,state);first_state=json.loads(state.read_text(encoding='utf-8'))
        if first.log_file:first.log_file.rename(first.log_file.with_name(first.log_file.stem+'_first.log'))
        second=self.execute(scenario,root,home,state);second_state=json.loads(state.read_text(encoding='utf-8'))
        return UpdateSequence(root,first,second,first_state,second_state)
