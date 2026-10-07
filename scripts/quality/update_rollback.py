"""Exercise the real updater helper with disposable app stubs, no installed apps."""
from pathlib import Path
import subprocess, tempfile
source = Path('Sources/OxyMacCleaner/AppUpdater.swift').read_text()
script = source.split('static let script = #"""',1)[1].split('"""#',1)[0]
# Keep OS application launching out of this fixture; paths and moves remain real.
script = script.replace('/usr/bin/open "$app"', ':')
for healthy in (True, False):
    with tempfile.TemporaryDirectory(prefix='OxyUpdaterQA-') as folder:
        root = Path(folder); app = root/'OxyMac Cleaner.app'; nextapp = root/'next.app'; stage = root/'stage'
        for bundle in (app,nextapp): (bundle/'Contents/MacOS').mkdir(parents=True)
        stage.mkdir(); (app/'original').write_text('old')
        executable = nextapp/'Contents/MacOS/OxyMacCleaner'
        executable.write_text('#!/bin/sh\n' + ('echo ready > "$2"\n' if healthy else 'exit 1\n'))
        executable.chmod(0o700)
        helper = root/'helper.sh'; helper.write_text(script)
        subprocess.run(['/bin/sh',str(helper),'99999999',str(app),str(nextapp),str(stage)],check=True,timeout=65)
        if healthy:
            assert (stage/'rollback/OxyMac Cleaner.app/original').read_text() == 'old'
            assert not (stage/'previous.app').exists()
        else:
            assert (app/'original').read_text() == 'old'
            assert (stage/'failed-update').is_dir()
print('PASS: named rollback copy, launch handshake and failed-launch recovery')
