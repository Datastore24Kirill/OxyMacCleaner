#!/usr/bin/env python3
"""Destructive tests ONLY inside a newly created, owned APFS image and fixture directory."""
import pathlib, subprocess, tempfile, time, shutil, sys
helper = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(tempfile.mkdtemp(prefix='OxyExternalQA-', dir=pathlib.Path.home()/'Downloads'))
image, mount = root/'fixture.dmg', root/'mount'
mount.mkdir()
def disk(*args):
    subprocess.run(['/usr/bin/hdiutil', *map(str,args)],check=True,stdout=subprocess.DEVNULL)
def attach(): disk('attach',image,'-nobrowse','-mountpoint',mount)
def detach(): disk('detach','-force',mount)
def run(mode): subprocess.run([str(helper),mode,str(root),str(mount)],check=True)
try:
    disk('create','-size','512m','-fs','APFS','-volname','OxyOwnedFixture',image)
    attach(); run('prepare')
    child = subprocess.Popen([str(helper),'relocate',str(root),str(mount)])
    deadline=time.monotonic()+30
    while child.poll() is None and time.monotonic()<deadline:
        if list(mount.glob('OxyQuarantine-*')):
            detach(); break
        time.sleep(.005)
    else:
        child.kill(); child.wait(); raise RuntimeError('Did not observe transfer boundary')
    if child.wait(timeout=30): raise RuntimeError('Interrupted transfer failed safety check')
    attach(); run('online'); detach(); run('offline'); attach()
    child = subprocess.Popen([str(helper),'restore-interrupted',str(root),str(mount)])
    deadline=time.monotonic()+30
    while child.poll() is None and time.monotonic()<deadline:
        if list(root.glob('.oxy-restore-*')):
            detach(); break
        time.sleep(.001)
    else:
        if child.poll() is None: child.kill()
        child.wait(); raise RuntimeError('Did not interrupt restore copy')
    if child.wait(timeout=30): raise RuntimeError('Interrupted restore failed safety check')
    if not (root/'source').exists(): run('offline')
    attach(); run('restore'); run('scan')
    attach()
    if len(list(mount.glob('scan-*')))!=100: raise RuntimeError('Fixture scan changed files')
    print('PASS: owned APFS disconnect/reconnect scenarios; scan files unchanged')
finally:
    subprocess.run(['/usr/bin/hdiutil','detach','-force',str(mount)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(root)
