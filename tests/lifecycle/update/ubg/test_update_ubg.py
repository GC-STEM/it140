#!/usr/bin/env python3
"""Behavioral contract tests for Ubuntu GNOME update_ubg.sh."""
from __future__ import annotations
import json, os
from pathlib import Path
import shutil, stat, subprocess, sys, tempfile, unittest
from runner_ubg import BASH_EXECUTABLE, MANIFEST_SOURCE, UPDATE_SOURCE, UbgUpdateHarness
HERE=Path(__file__).resolve().parent; FIXTURE=HERE/'fixtures'/'base'; MOCK=HERE/'mocks'/'mock_command.py'; SCENARIOS=HERE/'scenarios'
FILES=('success.json','manifest_failure.json','unsupported.json','privilege_failure.json','external_failure.json','external_after_change.json','partial_failure.json','restart_required.json')

@unittest.skipUnless(sys.platform.startswith('linux') and BASH_EXECUTABLE,'Ubuntu GNOME Update tests require Linux with Bash')
class UbgUpdateLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.h=UbgUpdateHarness(FIXTURE,MOCK)
    def early(self,arg,text):
        with tempfile.TemporaryDirectory(prefix='it140-update-ubg-cli-') as t:
            home=Path(t)/'home'; home.mkdir(); e=os.environ.copy(); e['HOME']=str(home)
            cp=subprocess.run([BASH_EXECUTABLE,str(UPDATE_SOURCE),arg],env=e,cwd=home,text=True,capture_output=True,check=False)
            self.assertEqual(0,cp.returncode,cp.stderr); self.assertIn(text,cp.stdout+cp.stderr); self.assertFalse((home/'it140'/'logs').exists())
    def test_help_returns_zero_without_creating_log(self): self.early('--help','Usage: update_ubg.sh')
    def test_version_returns_zero_without_creating_log(self): self.early('--version','0.3.0')
    def test_declared_scenarios(self):
        for name in FILES:
            scenario=self.h.load_scenario(SCENARIOS/name)
            with self.subTest(scenario=scenario['id']): self.assert_scenario(self.h.run(scenario),scenario)
    def assert_scenario(self,run,scenario):
        exp=scenario['expected']; d=run.combined_output
        self.assertEqual(exp['exit_code'],run.returncode,d); self.assertFalse(run.protected_differences,d)
        self.assertIsNotNone(run.transcript,d); tr=run.transcript; assert tr
        self.assertEqual(exp['result'],tr.summary.get('Result'),d); self.assertEqual(exp['managed_changes'],tr.summary.get('Managed changes'),d); self.assertEqual(exp.get('restart_required','No'),tr.summary.get('Restart required'),d)
        self.assertEqual(str(run.returncode),tr.summary.get('Exit code'),d); self.assertEqual(exp.get('failures',0),int(tr.summary.get('Failures','-1')),d)
        if 'warnings_min' in exp: self.assertGreaterEqual(int(tr.summary.get('Warnings','-1')),exp['warnings_min'],d)
        for text in exp.get('contains',[]): self.assertIn(text,tr.text,d)
        if run.log_file:
            self.assertEqual(0o600,stat.S_IMODE(run.log_file.stat().st_mode) & 0o777,d); self.assertEqual(0o700,stat.S_IMODE(run.log_dir.stat().st_mode) & 0o777,d)
        if run.returncode==0:
            state=json.loads(run.state_file.read_text()); manifest=json.loads(MANIFEST_SOURCE.read_text()); system,venv,ext=self.h.requirements(manifest)
            self.assertTrue(set(system)<=set(state['installed_packages']),d); self.assertTrue(set(venv)<=set(state['venv_packages']),d); self.assertTrue(set(ext)<=set(state['extensions']),d)
    def test_successful_configuration_is_semantically_idempotent(self):
        scenario=self.h.load_scenario(SCENARIOS/'success.json'); seq=self.h.run_twice(scenario)
        self.assert_scenario(seq.first,scenario); self.assert_scenario(seq.second,scenario)
        for key in ('installed_packages','venv_packages','extensions','sudo_valid'):
            self.assertEqual(seq.first_state.get(key),seq.second_state.get(key),seq.second.combined_output)
        self.assertFalse(seq.second.protected_differences,seq.second.combined_output)

if __name__=='__main__': unittest.main()
