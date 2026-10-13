"""Exercise startup behavior: persistent repositories survive unavailable peers."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/'scripts/ipfs-entrypoint.sh'


class KuboEntrypointRestartTests(unittest.TestCase):
    def run_script(self,existing,seed=False,failures=99):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);repo=root/'repo';repo.mkdir();binary=root/'bin';binary.mkdir()
            if existing:(repo/'config').write_text('{}')
            log=root/'calls';counter=root/'attempts'
            mock=binary/'ipfs'
            mock.write_text(f'''#!{sys.executable}
import os,json,sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps(args)+'\\n')
if 'id' in args:
 p=Path(os.environ['MOCK_COUNTER']);n=int(p.read_text())+1 if p.exists() else 1;p.write_text(str(n))
 if n<=int(os.environ['MOCK_FAILURES']):sys.exit(1)
 print('12D3KooWKnownPeer');sys.exit(0)
if args[:1]==['init']:Path(os.environ['IPFS_PATH'],'config').write_text('{{}}')
if args[:2]==['bootstrap','list']:sys.exit(0)
''');mock.chmod(0o700)
            sleep=binary/'sleep';sleep.write_text('#!/bin/sh\nexit 0\n');sleep.chmod(0o700)
            env=os.environ|{'PATH':str(binary)+os.pathsep+os.environ['PATH'],'IPFS_PATH':str(repo),
                'IPFS_BOOTSTRAP_ENDPOINTS':'/ip4/100.64.1.19/tcp/5001@4001',
                'CLUSTER_SEED':'true' if seed else 'false','MOCK_CALLS':str(log),
                'MOCK_COUNTER':str(counter),'MOCK_FAILURES':str(failures)}
            for key in ['IPFS_SWARM_KEY_FILE','IPFS_ANNOUNCE_MULTIADDRESSES','IPFS_ANNOUNCE_MULTIADDRESS']:
                env.pop(key,None)
            r=subprocess.run(['sh',str(SCRIPT)],env=env,capture_output=True,text=True,timeout=5)
            self.assertEqual(r.returncode,0,r.stderr)
            return [json.loads(l) for l in log.read_text().splitlines()],r.stdout

    def test_existing_repository_starts_without_live_bootstrap_and_keeps_peers(self):
        calls,output=self.run_script(True)
        self.assertTrue(any(c[:1]==['daemon'] for c in calls))
        self.assertFalse(any(c[:1]==['init'] or c[:2]==['bootstrap','rm'] for c in calls))
        lookups=[c for c in calls if 'id' in c]
        self.assertEqual(len(lookups),0)
        self.assertIn('stored peer routes',output)
        self.assertIn('persistent private repository',output)

    def test_new_nonseed_repository_waits_until_a_peer_resolves(self):
        calls,_=self.run_script(False,failures=2)
        self.assertTrue(any(c[:1]==['init'] for c in calls))
        self.assertEqual(sum(c[:2]==['bootstrap','rm'] for c in calls),1)
        self.assertEqual(sum('id' in c for c in calls),3)
        self.assertTrue(any(c[:2]==['bootstrap','add'] for c in calls))
        self.assertTrue(any(c[:1]==['daemon'] for c in calls))

    def test_new_seed_repository_can_start_without_a_peer(self):
        calls,output=self.run_script(False,seed=True)
        self.assertEqual(sum('id' in c for c in calls),6)  # initial probe plus five retries
        self.assertIn('seeding a new private swarm',output)
        self.assertTrue(any(c[:1]==['daemon'] for c in calls))

    def test_existing_repository_does_not_replace_saved_routes_from_environment(self):
        calls,_=self.run_script(True,failures=0)
        self.assertFalse(any(c[:2]==['bootstrap','rm'] for c in calls))
        self.assertFalse(any(c[:2]==['bootstrap','add'] or 'id' in c for c in calls))
