#!/usr/bin/env python3
# Launch a single signed Debug copy without changing the app preferences or hook configuration.
import subprocess,pathlib,json,ctypes,os,signal,time
source=pathlib.Path(os.environ.get('DIARY_DEBUG_APP', '/tmp/boring-diary-build/Build/Products/Debug/boringNotch.app'))
if not source.is_dir():
    raise SystemExit('Build and sign the Debug app first, or set DIARY_DEBUG_APP.')
app=pathlib.Path.home()/'Library/Developer/Xcode/DerivedData/boring-notch-evening-diary/Build/Products/Debug/boringNotch.app'
query='ObjC.import("AppKit"); var apps=$.NSWorkspace.sharedWorkspace.URLsForApplicationsWithBundleIdentifier("theboringteam.boringnotch"); var paths=[]; for(var i=0;i<apps.count;i++){paths.push(apps.objectAtIndex(i).path.js);} JSON.stringify(paths)'
paths=json.loads(subprocess.check_output(['/usr/bin/osascript','-l','JavaScript','-e',query],text=True))
backup=pathlib.Path('/tmp/boring-diary-previous-registrations.json')
if not backup.exists(): backup.write_text(json.dumps(paths))
proc=ctypes.CDLL('/usr/lib/libproc.dylib');proc.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]
known={str(pathlib.Path(p).resolve()/'Contents/MacOS/boringNotch') for p in paths+[str(source),str(app),'/Applications/boringNotch.app']}
for pid in subprocess.run(['pgrep','-x','boringNotch'],capture_output=True,text=True).stdout.split():
    buffer=ctypes.create_string_buffer(4096)
    if proc.proc_pidpath(int(pid),buffer,len(buffer))>0 and buffer.value.decode() in known:
        os.kill(int(pid),signal.SIGTERM)
        time.sleep(.5)
        try: os.kill(int(pid),signal.SIGKILL)
        except ProcessLookupError: pass
app.parent.mkdir(parents=True,exist_ok=True)
if source.resolve()!=app.resolve(): subprocess.run(['/usr/bin/ditto',str(source),str(app)],check=True)
ls='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
for path in paths:
    if pathlib.Path(path).resolve()!=app.resolve(): subprocess.run([ls,'-u',path],check=True)
subprocess.run([ls,'-f',str(app)],check=True)
subprocess.run(['open','-n',str(app),'--args','--preview-evening-review'],check=True)
time.sleep(2)
print(subprocess.check_output(['/usr/bin/osascript','-l','JavaScript','-e','ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier("theboringteam.boringnotch").path.js'],text=True).strip())
# Exercise the exact bundle-ID launch used by the notification hook, without its payload.
subprocess.run(['open','-g','-b','theboringteam.boringnotch'],check=True)
time.sleep(2)
pids=subprocess.run(['pgrep','-x','boringNotch'],capture_output=True,text=True).stdout.split()
print('Boring Notch process count:',len(pids))
assert len(pids)==1, 'Overlapping Boring Notch instances remain'
print('Evening review triggered; no preference writes performed.')
