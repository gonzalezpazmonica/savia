from pathlib import Path
import os,subprocess,sys,unittest
CORE=Path(__file__).resolve().parents[2]/"scripts/dual-cli"
class DoctorTests(unittest.TestCase):
 def setUp(self):
  self.old=os.environ.get('SAVIA_CODEX_TEST_MODE');os.environ['SAVIA_CODEX_TEST_MODE']='1'
  self.addCleanup(lambda: os.environ.pop('SAVIA_CODEX_TEST_MODE',None) if self.old is None else os.environ.__setitem__('SAVIA_CODEX_TEST_MODE',self.old))
 def test_real_shape_and_fail_closed(self):
  p=subprocess.run([sys.executable,str(CORE/'autonomy_doctor.py'),
      '--sandbox-probe','/bin/true'],capture_output=True,text=True)
  self.assertEqual(p.returncode,2);self.assertIn('L3 blocking               NOT_VERIFIED',p.stdout)
  self.assertIn('Status                    DEGRADED_SAFE',p.stdout)
 def test_all_local_probes_pass_but_ceiling_stays_l2(self):
  p=subprocess.run([sys.executable,str(CORE/'autonomy_doctor.py'),
      '--sandbox-probe','/bin/true','--enforcement-probe','/bin/true'],capture_output=True,text=True)
  self.assertEqual(p.returncode,2);self.assertIn('Autonomy L2               NOT_VERIFIED',p.stdout)
  self.assertIn('Authority escalation      BLOCKED',p.stdout)
  self.assertIn('Max verified risk         NOT_VERIFIED',p.stdout)
if __name__=='__main__':unittest.main()
