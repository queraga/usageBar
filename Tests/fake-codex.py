#!/usr/bin/python3
import json,sys,time,os,signal
from pathlib import Path
mode=Path(sys.argv[0]).name
state=Path(os.environ['USAGE_TEST_STATE'])
with state.open('a') as f:f.write('start '+str(os.getpid())+'\n')
def emit(o):
 data=json.dumps(o)+'\n'
 # Deliberately split records across stdout writes.
 sys.stdout.write(data[:13]);sys.stdout.flush();time.sleep(.002)
 sys.stdout.write(data[13:]);sys.stdout.flush()
ready=False
for line in sys.stdin:
 o=json.loads(line);m=o['method'];i=o.get('id')
 if m=='initialize':
  if 'init-timeout' in mode:time.sleep(30)
  emit({'id':i,'result':{}})
 elif m=='initialized':ready=True
 elif m=='account/rateLimits/read':
  assert ready
  with state.open('a') as f:f.write('read '+str(os.getpid())+'\n')
  if 'exit' in mode:sys.exit(0)
  if 'request-timeout' in mode:time.sleep(30)
  if 'malformed' in mode:print('not json',flush=True);continue
  if 'auth' in mode:emit({'id':i,'error':{'code':-32000,'message':'Authentication required'}});continue
  emit({'method':'unrelated/notification','params':{}})
  emit({'id':999999,'result':{}})
  emit({'id':i,'result':{'rateLimits':{'limitId':'codex','primary':{'usedPercent':42,'windowDurationMins':10080,'resetsAt':1789910299},'secondary':{'usedPercent':25,'windowDurationMins':300,'resetsAt':1789585715}}}})
 else:raise RuntimeError('Unexpected method')
