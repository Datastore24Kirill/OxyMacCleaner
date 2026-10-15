"""Exercise the production restart helper with a fake launcher and disposable paths."""
from pathlib import Path
import os, subprocess, tempfile, time
source = Path('Sources/CleanerCore/AppRestart.swift').read_text()
script = source.split('static let script = #"""', 1)[1].split('"""#', 1)[0]
with tempfile.TemporaryDirectory(prefix='OxyRestartQA-') as folder:
    root = Path(folder)
    app = root / 'App with spaces $(ignored).app'
    app.mkdir()
    output = root / 'launched'
    launcher = root / 'launcher'
    launcher.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$OXY_RESTART_RESULT"\n')
    launcher.chmod(0o700)
    fixture = script.replace('/usr/bin/open', '"' + str(launcher) + '"')
    env = dict(os.environ, OXY_RESTART_RESULT=str(output))
    old = subprocess.Popen(['/bin/sleep', '30'])
    helper = subprocess.Popen(['/bin/sh', '-c', fixture, 'test', str(old.pid), str(app)], env=env)
    try:
        time.sleep(0.2)
        assert not output.exists(), 'Must not relaunch while old process is alive'
        old.terminate(); old.wait(timeout=5)
        assert helper.wait(timeout=5) == 0
        assert output.read_text().splitlines() == ['-n', str(app)]
        output.unlink()
        for pid in ('0', '1', '-1', 'abc'):
            result = subprocess.run(['/bin/sh', '-c', fixture, 'test', pid, str(app)], env=env)
            assert result.returncode == 2 and not output.exists()
        missing = subprocess.run(['/bin/sh', '-c', fixture, 'test', str(old.pid), str(root/'missing.app')], env=env)
        assert missing.returncode == 2 and not output.exists()

        # Shorten only the wait interval, retaining the production timeout branch.
        live = subprocess.Popen(['/bin/sleep', '30'])
        try:
            timed = subprocess.run(['/bin/sh', '-c', fixture.replace('sleep 1', 'sleep 0.01'),
                                    'test', str(live.pid), str(app)], env=env,
                                   capture_output=True, text=True, timeout=5)
            assert timed.returncode == 3 and 'did not quit' in timed.stderr
            assert live.poll() is None and not output.exists(), 'Timeout must not kill or duplicate the app'
        finally:
            live.terminate(); live.wait(timeout=5)

        launcher.write_text('#!/bin/sh\nexit 17\n')
        failed = subprocess.run(['/bin/sh', '-c', fixture, 'test', str(old.pid), str(app)], env=env,
                                capture_output=True, text=True, timeout=5)
        assert failed.returncode == 4 and 'rejected' in failed.stderr and not output.exists()
    finally:
        if old.poll() is None: old.terminate(); old.wait()
        if helper.poll() is None: helper.terminate(); helper.wait()
print('PASS: waits for exit, exact path, invalid PID/missing bundle, timeout preserves live process, launcher failure')
