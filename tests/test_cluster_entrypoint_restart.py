"""Persistent CRDT peers must serve their state without a live bootstrap API."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/'scripts/cluster-entrypoint.sh'


class ClusterEntrypointRestartTests(unittest.TestCase):
    def run_script(self,existing,seed=False,failures=99):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);repo=root/'repo';repo.mkdir();binary=root/'bin';binary.mkdir()
            if existing:(repo/'service.json').write_text('{}')
            secret=root/'secret';secret.write_text('a'*64)
            log=root/'calls';counter=root/'attempts'
            for tool in ['ipfs-cluster-service','ipfs-cluster-ctl']:
                mock=binary/tool
                mock.write_text(f'''#!{sys.executable}
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'],'a') as f:f.write(json.dumps([Path(sys.argv[0]).name,*args])+'\\n')
if 'id' in args:
 p=Path(os.environ['MOCK_COUNTER']);n=int(p.read_text())+1 if p.exists() else 1;p.write_text(str(n))
 if n<=int(os.environ['MOCK_FAILURES']):sys.exit(1)
 print(json.dumps({{'id':'12D3KooWKnownCluster'}},indent=2))
if args[:1]==['init']:Path(os.environ['IPFS_CLUSTER_PATH'],'service.json').write_text('{{}}')
''');mock.chmod(0o700)
            # The production script runs on Linux; macOS sed has a different -i syntax.
            sed=binary/'sed';sed.write_text('#!/bin/sh\ncase " $* " in *" -i "*) exit 0 ;; esac\nexec /usr/bin/sed "$@"\n');sed.chmod(0o700)
            sleep=binary/'sleep';sleep.write_text('#!/bin/sh\nexit 0\n');sleep.chmod(0o700)
            env=os.environ|{'PATH':str(binary)+os.pathsep+os.environ['PATH'],'CLUSTER_PATH':str(repo),
                'CLUSTER_SECRET_FILE':str(secret),'CLUSTER_BOOTSTRAP_ENDPOINTS':'/ip4/100.64.1.19/tcp/9094@9096',
                'CLUSTER_SEED':'true' if seed else 'false','MOCK_CALLS':str(log),
                'MOCK_COUNTER':str(counter),'MOCK_FAILURES':str(failures)}
            for k in ['CLUSTER_ANNOUNCE_MULTIADDRESSES','CLUSTER_ANNOUNCE_MULTIADDRESS']:env.pop(k,None)
            r=subprocess.run(['sh',str(SCRIPT)],env=env,capture_output=True,text=True,timeout=5)
            self.assertEqual(r.returncode,0,r.stderr)
            return [json.loads(l) for l in log.read_text().splitlines()],r.stdout

    def test_persistent_cluster_starts_without_bootstrap_and_keeps_state(self):
        calls,output=self.run_script(True)
        self.assertEqual(calls,[['ipfs-cluster-service','daemon']])
        self.assertIn('stored peer routes and CRDT state',output)

    def test_new_cluster_joins_only_after_a_peer_resolves(self):
        calls,_=self.run_script(False,failures=2)
        self.assertEqual(sum('id' in c for c in calls),3)
        self.assertEqual(calls[0],['ipfs-cluster-service','init'])
        self.assertEqual(calls[-1],['ipfs-cluster-service','daemon','--bootstrap',
                                  '/ip4/100.64.1.19/tcp/9096/p2p/12D3KooWKnownCluster'])

    def test_new_seed_can_start_without_an_existing_peer(self):
        calls,_=self.run_script(False,seed=True)
        self.assertEqual(sum('id' in c for c in calls),6)
        self.assertEqual(calls[-1],['ipfs-cluster-service','daemon'])
