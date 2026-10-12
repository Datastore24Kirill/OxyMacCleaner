#!/usr/bin/env python3
"""Destructive tests ONLY inside a newly created, owned APFS image and fixture directory."""
import pathlib, subprocess, tempfile, time, shutil, sys, plistlib
helper = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(tempfile.mkdtemp(prefix='OxyExternalQA-', dir=pathlib.Path.home()/'Downloads'))
image, mount = root/'fixture.dmg', root/'mount'
mount.mkdir()
def disk(*args):
    subprocess.run(['/usr/bin/hdiutil', *map(str,args)],check=True,stdout=subprocess.DEVNULL)
def attach(): disk('attach',image,'-nobrowse','-mountpoint',mount)
def owned_device():
    info = plistlib.loads(subprocess.check_output(['/usr/bin/hdiutil', 'info', '-plist']))
    for entry in info.get('images', []):
        if pathlib.Path(entry.get('image-path', '')).resolve() == image.resolve():
            return entry['system-entities'][0]['dev-entry']
    return None

def detach():
    # APFS can unmount the volume but briefly keep the image device busy.
    # Retry the exact owned image device; never target other attached disks.
    for attempt in range(10):
        device = owned_device()
        if device is None:
            return
        result = subprocess.run(['/usr/bin/hdiutil', 'detach', '-force', device],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode == 0:
            return
        time.sleep(.1 * (attempt + 1))
    raise RuntimeError('Owned fixture image still busy: ' + result.stderr.decode(errors='replace'))
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
    # Do not remove a fixture tree while its image is still attached.
    detach()
    shutil.rmtree(root)
