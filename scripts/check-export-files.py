import os
import pathlib
import plistlib
import shutil
import stat
import subprocess
import tempfile
import time

repo = pathlib.Path(__file__).resolve().parent.parent
root = pathlib.Path(tempfile.mkdtemp(prefix="check-export-files-", dir=repo / ".build"))
notify = root / "notify"
(root / "notify.swift").write_text('''import Foundation
let a = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.moneten.debug"), object: a[1],
 userInfo: ["command": a[2], "argument": a.count > 3 ? a[3] : ""], deliverImmediately: true)
''')
subprocess.run(["swiftc", str(root / "notify.swift"), "-o", str(notify)], check=True)
app = root / "Moneten.app"
shutil.copytree(repo / "dist/Moneten.app", app, symlinks=True)
info = app / "Contents/Info.plist"
with info.open("rb") as file:
    properties = plistlib.load(file)
properties["CFBundleIdentifier"] = "io.github.moneten.check-export-files"
with info.open("wb") as file:
    plistlib.dump(properties, file)
subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(repo / "App/Moneten.entitlements"), str(app)], check=True)
data = root / "data"
debug = root / "debug"
debug.mkdir()
env = os.environ | {"MONETEN_DATA_DIR": str(data), "MONETEN_DEBUG_DIR": str(debug)}
if "MONETEN_EXPORT_SYNC_LIBRARY" in env:
    env["DYLD_INSERT_LIBRARIES"] = env.pop("MONETEN_EXPORT_SYNC_LIBRARY")


def send(command, argument=""):
    subprocess.run([str(notify), str(debug), command, argument], check=True)


def wait_for(test):
    deadline = time.monotonic() + 30
    while not test():
        assert process.poll() is None, "The app exited."
        assert time.monotonic() < deadline, "The app did not finish within 30 seconds."
        time.sleep(0.1)


def started():
    send("state")
    return (debug / "debug.log").exists()


def unlocked():
    send("state")
    log = debug / "debug.log"
    return log.exists() and "phase=unlocked" in log.read_text()


try:
    with (root / "app.log").open("w") as output:
        process = subprocess.Popen([str(app / "Contents/MacOS/Moneten"), "-lockAfterInactivity", "NO", "-ApplePersistenceIgnoreState", "YES"],
                                   env=env, stdout=output, stderr=subprocess.STDOUT)
        try:
            wait_for(started)
            send("create", "test-export-files")
            wait_for(unlocked)
            for kind in ["csv", "json"]:
                for replacing in [False, True]:
                    destination = root / f"export.{kind}"
                    if replacing:
                        destination.write_text("keep")
                        destination.chmod(0o644)
                    send("exportcsv" if kind == "csv" else "exportall", str(destination))
                    prefix = b"\xef\xbb\xbf" if kind == "csv" else b"{"
                    wait_for(lambda: destination.exists() and destination.read_bytes().startswith(prefix))
                    mode = stat.S_IMODE(destination.stat().st_mode)
                    assert mode == 0o600, f"Expected mode 0600, got {mode:04o}."
                    print(f"{kind.upper()} {'replacement' if replacing else 'new'} mode = {mode:04o}", flush=True)
                    send("alert")
        finally:
            send("quit")
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=10)
finally:
    shutil.rmtree(root)
