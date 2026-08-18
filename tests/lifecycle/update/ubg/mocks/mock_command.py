#!/usr/bin/env python3
"""Stateful deterministic command dispatcher for Ubuntu GNOME Update tests."""
from __future__ import annotations
import json, os, pathlib, shutil, stat, sys, tempfile
from typing import Any

STATE=pathlib.Path(os.environ['IT140_MOCK_STATE'])
TRACE=pathlib.Path(os.environ['IT140_MOCK_TRACE'])
MOCK_BIN=pathlib.Path(os.environ['IT140_MOCK_BIN'])
DISPATCHER=pathlib.Path(os.environ['IT140_MOCK_DISPATCHER'])
PYTHON=os.environ['IT140_MOCK_PYTHON']
COMMAND=os.environ.get('IT140_MOCK_COMMAND', pathlib.Path(sys.argv[0]).name)
ARGS=sys.argv[1:]

def load()->dict[str,Any]: return json.loads(STATE.read_text(encoding='utf-8'))
def save(s:dict[str,Any])->None: STATE.write_text(json.dumps(s,indent=2,sort_keys=True)+'\n',encoding='utf-8')
def trace(cmd:str,args:list[str])->None:
    with TRACE.open('a',encoding='utf-8') as f: f.write(json.dumps({'command':cmd,'args':args},sort_keys=True)+'\n')
def wrapper(path:pathlib.Path,name:str)->None:
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text('#!/usr/bin/env bash\n'+f"export IT140_MOCK_COMMAND={name!r}\n"+'exec "$IT140_MOCK_PYTHON" "$IT140_MOCK_DISPATCHER" "$@"\n',encoding='utf-8')
    path.chmod(0o755)
def create_venv_python(path:pathlib.Path)->None: wrapper(path,'venv-python')
def fail(s:dict[str,Any],name:str)->bool: return bool(s.get('fail_points',{}).get(name,False))

def main()->int:
    trace(COMMAND,ARGS); s=load()
    if COMMAND=='sleep': return 0
    if COMMAND=='git':
        if ARGS[:1]==['clone']:
            s['git_clone_count']=int(s.get('git_clone_count',0))+1; save(s)
            if fail(s,'git_clone'): return 1
            target=pathlib.Path(ARGS[-1]); source=pathlib.Path(os.environ['IT140_MOCK_REPOSITORY'])
            if target.exists(): shutil.rmtree(target)
            shutil.copytree(source,target); return 0
        return 0
    if COMMAND=='sudo':
        if ARGS==['-v']: return 0 if s.get('sudo_valid',True) else 1
        args=list(ARGS)
        if args and args[0]=='env':
            args=args[1:]
            while args and '=' in args[0] and not args[0].startswith('-'): args=args[1:]
        if not args: return 0
        if pathlib.Path(args[0]).name=='apt-get':
            apt=args[1:]
            if 'update' in apt:
                s['apt_update_count']=int(s.get('apt_update_count',0))+1; save(s)
                return 1 if fail(s,'apt_update') else 0
            if 'install' in apt:
                s['apt_upgrade_count']=int(s.get('apt_upgrade_count',0))+1
                if fail(s,'apt_upgrade'): save(s); return 1
                save(s); return 0
        return 0
    if COMMAND=='dpkg-query':
        package=ARGS[-1] if ARGS else ''
        if package in set(s.get('installed_packages',[])):
            print('ii '); return 0
        return 1
    if COMMAND=='python3.12':
        if len(ARGS)>=3 and ARGS[:2]==['-m','venv']:
            venv=pathlib.Path(ARGS[2]); create_venv_python(venv/'bin'/'python'); s['venv_exists']=True; save(s); return 0
        print('Python 3.12.0'); return 0
    if COMMAND=='venv-python':
        if ARGS[:3]==['-m','pip','show'] and len(ARGS)>=4:
            return 0 if ARGS[3] in set(s.get('venv_packages',[])) else 1
        if ARGS[:3]==['-m','pip','install']:
            if fail(s,'venv_pip'): return 1
            packages=[]
            for x in ARGS[3:]:
                if x.startswith('-') or x in {'pip','setuptools','wheel'}: continue
                packages.append(x)
            existing=list(s.get('venv_packages',[])); skipped=set(s.get('skip_venv_packages',[]))
            for p in packages:
                if p not in skipped and p not in existing: existing.append(p)
            s['venv_packages']=sorted(existing); s['pip_update_count']=int(s.get('pip_update_count',0))+1; save(s); return 0
        # Script-invoked Python beyond pip is intentionally delegated.
        os.execv(PYTHON,[PYTHON,*ARGS]); return 1
    if COMMAND=='code':
        if ARGS[:1]==['--install-extension'] and len(ARGS)>=2:
            ext=ARGS[1]
            if fail(s,'extension_update') or ext in set(s.get('fail_extensions',[])): return 1
            exts=list(s.get('extensions',[])); skipped=set(s.get('skip_extensions',[]))
            if ext not in skipped and ext not in exts: exts.append(ext)
            s['extensions']=sorted(exts); s['extension_update_count']=int(s.get('extension_update_count',0))+1; save(s); return 0
        if ARGS[:1]==['--list-extensions']:
            print('\n'.join(s.get('extensions',[]))); return 0
        return 0
    return 0

if __name__=='__main__': raise SystemExit(main())
