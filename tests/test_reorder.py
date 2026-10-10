import os,sys,tempfile,subprocess,time,wave,json
sys.dont_write_bytecode = True
from pathlib import Path
from gi.repository import Gio,GLib
root=Path(tempfile.mkdtemp(prefix='audacious-reorder-qa-'))
os.environ.update(XDG_CONFIG_HOME=str(root/'config'),ADB_PREFS=str(root/'dock.json'),QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='',LD_PRELOAD=str(Path(__file__).resolve().parents[1]/'runtime/native-menu.so'))
(root/'dock.json').write_text('{"docked":false}')
for name in ('one.wav','two.wav','three.wav'):
 with wave.open(str(root/name),'wb') as f:
  f.setparams((1,2,44100,0,'NONE','not compressed'));f.writeframes(b'\0\0'*44100*30)
player=subprocess.Popen(['/usr/bin/audacious'],stdout=subprocess.DEVNULL,stderr=open(root/'player.log','w'))
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'runtime'));ns={}
try:
 exec(compile((Path(__file__).resolve().parents[1]/'runtime/bridge.py').read_text().split("buffer = b''")[0],'bridge.py','exec'),ns)
 for _ in range(60):
  if ns['alive']():break
  time.sleep(.1)
 call=ns['call'];call('SetVolume','(ii)',(0,0))
 urls=[(root/name).as_uri() for name in ('one.wav','two.wav','three.wav')]
 call('OpenList','(as)',(urls,));call('Jump','(u)',(1,));call('Play')
 for _ in range(100):
  if call('Time')>300:break
  time.sleep(.05)
 assert call('Status')=='playing'
 def order():return [call('SongFilename','(u)',(i,)) for i in range(call('Length'))]
 def move(start,end):
  payload={'playlist':call('GetActivePlaylist'),'name':call('GetActivePlaylistName'),'uris':order(),'from':start,'to':end}
  ns['action']({'action':'move-entry','value':payload})
 before=call('Time');move(1,2)
 assert order()==[urls[0],urls[2],urls[1]],order()
 assert call('Position')==2 and call('Status')=='playing' and call('Time')>=before
 move(2,0)
 assert order()==[urls[1],urls[0],urls[2]],order()
 assert call('Position')==0 and call('Status')=='playing' and call('Time')>=before
 print('PASS: move both directions preserves playing entry and playback time',flush=True)
 previous=order()
 payload={'playlist':call('GetActivePlaylist'),'name':call('GetActivePlaylistName'),'uris':urls,'from':0,'to':1}
 try:ns['action']({'action':'move-entry','value':payload});raise AssertionError('stale accepted')
 except GLib.Error:pass
 assert order()==previous
 payload['uris']=previous;payload['to']=len(previous)
 try:ns['action']({'action':'move-entry','value':payload});raise AssertionError('invalid accepted')
 except GLib.Error:pass
 assert order()==previous
 print('PASS: stale requests and out-of-bounds moves leave playlist intact',flush=True)
 call('Stop');streams=['https://example.invalid/radio-a','https://example.invalid/radio-b','https://example.invalid/radio-c']
 call('OpenList','(as)',(streams,));move(0,2)
 assert order()==[streams[1],streams[2],streams[0]]
 move(2,1);assert order()==[streams[1],streams[0],streams[2]]
 print('PASS: stream URI entries reorder without changing URLs',flush=True)
finally:
 if player.poll() is None:
  try:ns['call']('Quit');player.wait(timeout=5)
  except Exception:player.terminate();player.wait(timeout=5)
 print('Test log:',root/'player.log',flush=True)
