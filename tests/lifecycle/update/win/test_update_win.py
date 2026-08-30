#!/usr/bin/env python3
"""Behavioral contract tests for Windows update_it140.ps1."""
from __future__ import annotations
import json, os, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path
LIFECYCLE_ROOT=Path(__file__).resolve().parents[2]
if str(LIFECYCLE_ROOT) not in sys.path:sys.path.insert(0,str(LIFECYCLE_ROOT))
from common.configure_log import consistency_errors,summary_int  # noqa:E402
from runner_win import MANIFEST_SOURCE,POWERSHELL_EXECUTABLE,UPDATE_SOURCE,WinUpdateHarness  # noqa:E402
HERE=Path(__file__).resolve().parent;FIXTURE=HERE/'fixtures'/'base';SCENARIOS=HERE/'scenarios'
FILES=('success.json','manifest_failure.json','unsupported.json','privilege_failure.json','external_failure.json','external_after_change.json','partial_failure.json')
@unittest.skipUnless(sys.platform=='win32','Windows Update tests require a Windows runner')
class WinUpdateLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.h=WinUpdateHarness(FIXTURE)
    def early(self,arg,text):
        assert POWERSHELL_EXECUTABLE
        with tempfile.TemporaryDirectory(prefix='it140-update-win-cli-') as t:
            home=Path(t)/'home';home.mkdir();env=os.environ.copy();env['HOME']=str(home);env['USERPROFILE']=str(home);env['APPDATA']=str(home/'AppData'/'Roaming')
            cp=subprocess.run([POWERSHELL_EXECUTABLE,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(UPDATE_SOURCE),arg],capture_output=True,text=True,timeout=20,check=False,env=env)
            self.assertEqual(0,cp.returncode,cp.stdout+cp.stderr);self.assertIn(text,cp.stdout+cp.stderr)
    def test_help_returns_zero_without_creating_log(self):self.early('-Help','IT 140 Windows update script')
    def test_version_returns_zero_without_creating_log(self):self.early('-Version','1.0.2')
    def test_declared_scenarios(self):
        for f in FILES:
            s=self.h.load_scenario(SCENARIOS/f)
            with self.subTest(scenario=s['id']):
                run=self.h.run(s)
                try:self.assert_scenario(run,s)
                finally:shutil.rmtree(run.root,ignore_errors=True)
    def test_successful_update_is_semantically_idempotent(self):
        s=self.h.load_scenario(SCENARIOS/'success.json');seq=self.h.run_twice(s)
        try:
            self.assert_scenario(seq.first,s);self.assert_scenario(seq.second,s)
            for key in ('winget_packages','venv_python_version','venv_packages','extensions','managed_integration','configuration_complete'):
                self.assertEqual(seq.first_state.get(key),seq.second_state.get(key),seq.second.combined_output)
            self.assertFalse(seq.second.protected_differences,seq.second.combined_output)
        finally:shutil.rmtree(seq.root,ignore_errors=True)
    def assert_scenario(self,run,s):
        e=s['expected'];d=run.combined_output or 'No Update output captured.';self.assertEqual(e['exit_code'],run.returncode,d);self.assertEqual([],run.protected_differences,d);self.assertIsNotNone(run.transcript,d);tr=run.transcript;assert tr
        self.assertEqual(e['result'],tr.summary.get('result'),d);self.assertEqual(e['managed_changes'],tr.summary.get('managed changes'),d);self.assertEqual(e['exit_code'],summary_int(tr,'exit code'),d);self.assertEqual(e.get('failures',0),summary_int(tr,'failures'),d);self.assertEqual([],consistency_errors(tr,run.returncode),d)
        for text in e.get('contains',[]):self.assertIn(text,tr.text,d)
        if e.get('configured'):
            st=json.loads(run.state_path.read_text(encoding='utf-8'));m=json.loads(MANIFEST_SOURCE.read_text(encoding='utf-8'));self.assertTrue({b['package_identifier'] for b in self.h.bindings(m)}<=set(st['winget_packages']),d);self.assertTrue(set(self.h.venv_packages(m))<=set(st['venv_packages']),d);self.assertTrue(set(self.h.extensions(m))<=set(st['extensions']),d)
if __name__=='__main__':unittest.main()
