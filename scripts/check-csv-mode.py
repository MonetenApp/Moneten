import os,pathlib,subprocess,time,stat,tempfile,shutil
repo=pathlib.Path(__file__).resolve().parent.parent
root=pathlib.Path(tempfile.mkdtemp(prefix='check-csv-mode-',dir=repo/'.build'))
notify=root/'notify'
(root/'notify.swift').write_text('import Foundation\nlet a = CommandLine.arguments\nDistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.moneten.debug"), object: a[1], userInfo: ["command": a[2], "argument": a.count > 3 ? a[3] : ""], deliverImmediately: true)\n')
subprocess.run(['swiftc',str(root/'notify.swift'),'-o',str(notify)],check=True)
data=root/'data';debug=root/'debug';debug.mkdir(exist_ok=True)
env=os.environ|{'MONETEN_DATA_DIR':str(data),'MONETEN_DEBUG_DIR':str(debug)}
p=subprocess.Popen([str(repo/'dist/Moneten.app/Contents/MacOS/Moneten'),'-lockAfterInactivity','NO','-ApplePersistenceIgnoreState','YES'],env=env,stdout=open(root/'app.log','w'),stderr=subprocess.STDOUT)
def send(cmd,arg=''):subprocess.run([str(notify),str(debug),cmd,arg],check=True)
def wait(test):
 end=time.monotonic()+30
 while not test():
  assert p.poll() is None,'app exited'
  assert time.monotonic()<end,'timeout'
  time.sleep(.1)
try:
 time.sleep(2)
 send('create','test-csv-mode')
 time.sleep(2)
 for i in range(2):
  f=root/f'export{i}.csv'
  if i:
   f.write_text('keep')
   f.chmod(0o644)
  send('exportcsv',str(f))
  wait(lambda:f.exists() and f.read_bytes().startswith(b'\xef\xbb\xbf'))
  mode=stat.S_IMODE(f.stat().st_mode)
  print(f'CSV {"replacement" if i else "new"} mode = {mode:04o}',flush=True)
  assert mode==0o600,f'expected 0600, got {mode:04o}'
finally:
 send('quit')
 p.wait(timeout=10)
 shutil.rmtree(root)
