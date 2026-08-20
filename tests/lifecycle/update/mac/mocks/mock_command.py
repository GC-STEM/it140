#!/usr/bin/env python3
"""Stateful deterministic command dispatcher for macOS Update tests."""
from __future__ import annotations
import json, os
from pathlib import Path
import sys

LIFECYCLE_ROOT = Path(__file__).resolve().parents[3]
if str(LIFECYCLE_ROOT) not in sys.path:
    sys.path.insert(0, str(LIFECYCLE_ROOT))
from common.mock_state import load_state as load_shared_state, save_state as save_shared_state  # noqa: E402

def sp()->Path:return Path(os.environ['IT140_MOCK_STATE'])
def load():return load_shared_state(sp())
def save(s):save_shared_state(sp(),s)
def trace(c,a):
    q=os.environ.get('IT140_MOCK_TRACE')
    if q:
        with Path(q).open('a',encoding='utf-8') as f:f.write(json.dumps({'command':c,'args':a})+'\n')
def quote(v):return "'"+v.replace("'","'\"'\"'")+"'"
def wrapper(path:Path,name:str):
    path.parent.mkdir(parents=True,exist_ok=True); path.write_text('#!/bin/zsh\n'+f"exec {quote(os.environ['IT140_MOCK_PYTHON'])} {quote(os.environ['IT140_MOCK_DISPATCHER'])} {quote(name)} \"$@\"\n",encoding='utf-8'); path.chmod(0o755)

def brew(s,args):
    if args==['shellenv']: return 0
    if args==['update']:
        s['brew_update_count']=int(s.get('brew_update_count',0))+1; save(s); return 1 if s.get('fail_points',{}).get('brew_update') else 0
    if len(args)==3 and args[0]=='list' and args[1] in {'--formula','--cask'}:
        key='installed_casks' if args[1]=='--cask' else 'installed_formulas'; return 0 if args[2] in set(s.get(key,[])) else 1
    if args and args[0]=='outdated':
        is_cask='--cask' in args; pkg=args[-1]; key='outdated_casks' if is_cask else 'outdated_formulas'
        if pkg in set(s.get(key,[])): print(pkg)
        return 0
    if args and args[0]=='upgrade':
        is_cask='--cask' in args; pkg=args[-1]
        if s.get('fail_points',{}).get('brew_upgrade') or pkg in set(s.get('fail_upgrade_packages',[])): return 1
        key='outdated_casks' if is_cask else 'outdated_formulas'; vals=[x for x in s.get(key,[]) if x!=pkg]; s[key]=vals; s['brew_upgrade_count']=int(s.get('brew_upgrade_count',0))+1; save(s); return 0
    if args and args[0]=='cleanup': return 1 if s.get('fail_points',{}).get('brew_cleanup') else 0
    return 0

def main():
    if len(sys.argv)<2:return 2
    c=sys.argv[1]; a=sys.argv[2:]; s=load(); trace(c,a)
    if c=='brew': return brew(s,a)
    if c=='venv-python':
        if a[:3]==['-m','pip','show'] and len(a)>=4:return 0 if a[3] in set(s.get('venv_packages',[])) else 1
        if a[:3]==['-m','pip','install']:
            if s.get('fail_points',{}).get('venv_pip'): return 1
            skipped=set(s.get('skip_venv_packages',[])); vals=list(s.get('venv_packages',[]))
            for x in a[3:]:
                if x.startswith('-') or x in {'pip','setuptools','wheel'}: continue
                if x not in skipped and x not in vals: vals.append(x)
            s['venv_packages']=sorted(vals); s['pip_update_count']=int(s.get('pip_update_count',0))+1; save(s); return 0
        os.execv(os.environ['IT140_MOCK_PYTHON'],[os.environ['IT140_MOCK_PYTHON'],*a]); return 1
    if c=='code':
        if a[:1]==['--install-extension'] and len(a)>=2:
            ext=a[1]
            if s.get('fail_points',{}).get('extension_update') or ext in set(s.get('fail_extensions',[])):return 1
            vals=list(s.get('extensions',[])); skipped=set(s.get('skip_extensions',[]))
            if ext not in skipped and ext not in vals:vals.append(ext)
            s['extensions']=sorted(vals); s['extension_update_count']=int(s.get('extension_update_count',0))+1; save(s); return 0
        if a[:1]==['--list-extensions']:print('\n'.join(s.get('extensions',[])));return 0
        return 0
    if c.startswith('python3'):
        if '-c' in a:print('3.12')
        return 0
    return 0
if __name__=='__main__':raise SystemExit(main())
