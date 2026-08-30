#!/usr/bin/env python3
"""Behavioral contract tests for macOS update_it140.zsh."""
from __future__ import annotations
import json, os, platform
from pathlib import Path
import stat, subprocess, sys, tempfile, unittest
from runner_mac import MANIFEST_SOURCE, UPDATE_SOURCE, ZSH_EXECUTABLE, MacUpdateHarness
HERE=Path(__file__).resolve().parent;FIXTURE=HERE/'fixtures'/'base';MOCK=HERE/'mocks'/'mock_command.py';SCENARIOS=HERE/'scenarios'
FILES=('success.json','manifest_failure.json','unsupported.json','privilege_failure.json','external_failure.json','external_after_change.json','partial_failure.json')

def supported():return sys.platform=='darwin' and platform.machine()=='arm64' and ZSH_EXECUTABLE.is_file()
@unittest.skipUnless(supported(),'macOS Update tests require an Apple-silicon macOS runner')
class MacUpdateLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.h=MacUpdateHarness(FIXTURE,MOCK)
    def early(self,arg,text):
        with tempfile.TemporaryDirectory(prefix='it140-update-mac-cli-') as t:
            home=Path(t)/'home';home.mkdir();e=os.environ.copy();e['HOME']=str(home)
            cp=subprocess.run([str(ZSH_EXECUTABLE),str(UPDATE_SOURCE),arg],cwd=home,env=e,text=True,capture_output=True,check=False,timeout=15)
            self.assertEqual(0,cp.returncode,cp.stdout+cp.stderr);self.assertIn(text,cp.stdout+cp.stderr);self.assertFalse((home/'it140'/'logs').exists())
    def test_help_returns_zero_without_creating_log(self):self.early('--help','Usage: update_it140.zsh')
    def test_version_returns_zero_without_creating_log(self):self.early('--version','1.0.2')
    def test_declared_scenarios(self):
        for f in FILES:
            s=self.h.load_scenario(SCENARIOS/f)
            with self.subTest(scenario=s['id']):self.assert_scenario(self.h.run(s),s)
    def assert_scenario(self,run,s):
        e=s['expected'];d=run.combined_output;self.assertEqual(e['exit_code'],run.returncode,d);self.assertFalse(run.protected_differences,d);self.assertIsNotNone(run.transcript,d);tr=run.transcript;assert tr
        self.assertEqual(e['result'],tr.summary.get('Result'),d);self.assertEqual(e['managed_changes'],tr.summary.get('Managed changes'),d);self.assertEqual(str(run.returncode),tr.summary.get('Exit code'),d);self.assertEqual(e.get('failures',0),int(tr.summary.get('Failures','-1')),d)
        for text in e.get('contains',[]):self.assertIn(text,tr.text,d)
        if run.log_file:self.assertEqual(0o600,stat.S_IMODE(run.log_file.stat().st_mode),d);self.assertEqual(0o700,stat.S_IMODE(run.log_dir.stat().st_mode),d)
        if run.returncode==0:
            m=json.loads(MANIFEST_SOURCE.read_text());f,c,_,v,x=self.h.requirements(m);state=json.loads(run.state_file.read_text())
            self.assertTrue(set(f)<=set(state['installed_formulas']),d);self.assertTrue(set(c)<=set(state['installed_casks']),d);self.assertTrue(set(v)<=set(state['venv_packages']),d);self.assertTrue(set(x)<=set(state['extensions']),d)
    def test_successful_configuration_is_semantically_idempotent(self):
        s=self.h.load_scenario(SCENARIOS/'success.json');seq=self.h.run_twice(s);self.assert_scenario(seq.first,s);self.assert_scenario(seq.second,s);self.assertEqual(seq.first_state,seq.second_state,seq.second.combined_output);self.assertFalse(seq.second.protected_differences,seq.second.combined_output)
if __name__=='__main__':unittest.main()
