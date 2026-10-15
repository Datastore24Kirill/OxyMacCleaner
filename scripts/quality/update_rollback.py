"""Exercise the real updater helper with a fake Launch Services launcher, no GUI."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

source = Path('Sources/CleanerCore/UpdateInstaller.swift').read_text()
production = source.split('static let script = #"""', 1)[1].split('"""#', 1)[0]
assert 'kill -TERM' not in production
assert '"$app/Contents/MacOS/OxyMacCleaner"' not in production

for scenario in ('healthy', 'early_exit', 'launch_error', 'live_timeout', 'stale', 'invalid', 'old_alive'):
    with tempfile.TemporaryDirectory(prefix='OxyUpdaterQA-') as folder:
        root = Path(folder)
        app = root / 'App spaces $(ignored).app'
        nextapp = root / 'next.app'
        stage = root / '.OxyMacUpdate-fixture'
        for bundle in (app, nextapp):
            bundle.mkdir()
        stage.mkdir()
        (app / 'version').write_text('old')
        (nextapp / 'version').write_text('new')
        calls = root / 'calls'
        pidfile = root / 'launcher-pid'
        launcher = root / 'launcher'
        launcher.write_text('''#!/bin/sh
printf '%s\\n' "$@" >> "$OXY_TEST_CALLS"
[ "$1" = -n ] || exit 0
[ "$2" = -W ] && [ "$4" = --args ] && [ "$5" = --oxy-update-health ] || exit 9
case "$OXY_TEST_SCENARIO" in
 healthy) printf ready > "$6";;
 early_exit) exit 0;;
 launch_error) exit 17;;
 live_timeout) printf '%s' "$$" > "$OXY_TEST_PID"; exec /bin/sleep 30;;
esac
''')
        launcher.chmod(0o700)
        # Shorten only polling sleeps; all production branches remain unchanged.
        script = production.replace('/usr/bin/open', shlex.quote(str(launcher))).replace('sleep 1', 'sleep 0.01')
        helper = root / 'helper.sh'
        helper.write_text(script)
        env = dict(os.environ, OXY_TEST_CALLS=str(calls), OXY_TEST_PID=str(pidfile), OXY_TEST_SCENARIO=scenario)
        old = subprocess.Popen(['/bin/sleep', '30']) if scenario == 'old_alive' else None
        if scenario == 'stale':
            (stage / 'healthy').write_text('old marker')
        try:
            pids = ('0', '1', '-1', 'abc') if scenario == 'invalid' else (str(old.pid) if old else '99999999',)
            for pid in pids:
                result = subprocess.run(['/bin/sh', str(helper), pid, str(app), str(nextapp), str(stage)],
                                        env=env, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if scenario in ('invalid', 'stale', 'old_alive'):
                    assert result.returncode != 0 and not calls.exists(), scenario
                    assert (app / 'version').read_text() == 'old' and (nextapp / 'version').read_text() == 'new'
                    if old:
                        assert old.poll() is None
                    continue
                arguments = calls.read_text().splitlines()
                assert arguments[:6] == ['-n', '-W', str(app), '--args', '--oxy-update-health', str(stage / 'healthy')]
                if scenario == 'healthy':
                    assert result.returncode == 0
                    assert (app / 'version').read_text() == 'new'
                    assert (stage / 'rollback/OxyMac Cleaner.app/version').read_text() == 'old'
                elif scenario == 'live_timeout':
                    assert result.returncode != 0
                    os.kill(int(pidfile.read_text()), 0)
                    assert (app / 'version').read_text() == 'new'
                    assert (stage / 'rollback/OxyMac Cleaner.app/version').read_text() == 'old'
                    assert not (stage / 'failed-update').exists()
                else:
                    assert result.returncode == 0
                    assert (app / 'version').read_text() == 'old'
                    assert (stage / 'failed-update/version').read_text() == 'new'
                    assert arguments[6:] == [str(app)]
        finally:
            if old:
                old.terminate()
                old.wait(timeout=5)
            if pidfile.exists():
                # Only the disposable launcher created by this fixture is cleaned up.
                try:
                    os.kill(int(pidfile.read_text()), 15)
                except ProcessLookupError:
                    pass
print('PASS: Launch Services arguments, health, rollback, live timeout, stale health, invalid PID and old-process protection')
