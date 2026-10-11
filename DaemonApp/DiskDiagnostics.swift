import Foundation

struct DiskHealthReport: Decodable {
    let path: String
    let sampledAt: Double
    let values: [String: UInt64]
}

enum DiskDiagnostics {
    static let script = #"""
import glob, json, os, plistlib, pty, re, select, signal, subprocess, tarfile, time

REPORT_ROOT = '/var/tmp/daemon-manager-diagnostics'
OVERRIDES_PATH = '/var/db/com.apple.xpc.launchd/disabled.plist'
ARCHIVE_ROOT = '/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs/sysdiagnose'
FIELDS = ('percentUsed', 'slcPercentUsed', 'averageTLCPECycles', 'averageSLCPECycles',
          'maxNativeEndurance', 'maxSLCEndurance', 'hostWrites', 'nandWrites',
          'smartCritWarnings', 'numGrownBad', 'numRetiredBlocks', 'ueccReads')

def parse_snapshot(data):
    # ASP logs contain NUL-padded text as well as binary payloads.
    text = data.replace(b'\0', b'').decode('utf-8', 'replace')
    values = {}
    for key in FIELDS:
        matches = re.findall(r'(?m)^\s*' + re.escape(key) + r':\s*(\d+)[ \t]*$', text)
        if matches:
            values[key] = int(matches[-1])
    if not values:
        raise RuntimeError('This report contains no recognized NAND health counters.')
    return values

def read_report(path):
    if os.path.isdir(path):
        snapshot = os.path.join(path, 'ASPSnapshots', 'asptool_snapshot.log')
        if not os.path.isfile(snapshot):
            raise RuntimeError('The diagnostic did not produce an ASP NAND health snapshot.')
        with open(snapshot, 'rb') as source:
            values = parse_snapshot(source.read())
    else:
        # Stream only as far as the snapshot; avoid indexing and decompressing twice.
        with tarfile.open(path, 'r|gz') as archive:
            for member in archive:
                if member.isfile() and member.name.endswith('/ASPSnapshots/asptool_snapshot.log'):
                    with archive.extractfile(member) as source:
                        values = parse_snapshot(source.read())
                    break
            else:
                raise RuntimeError('The diagnostic archive has no ASP NAND health snapshot.')
    return {'path': path, 'sampledAt': os.path.getmtime(path), 'values': values}

def latest_report():
    candidates = []
    for root in (REPORT_ROOT, '/var/tmp', ARCHIVE_ROOT):
        for p in glob.glob(os.path.join(root, 'sysdiagnose*')):
            if os.path.isdir(p) or p.endswith('.tar.gz'):
                candidates.append(p)
    if not candidates:
        raise RuntimeError('No completed diagnostic found. Run a diagnostic first.')
    # A missing snapshot in the newest report must not silently show older data.
    return read_report(max(candidates, key=os.path.getmtime))

def launchctl(*args):
    result = subprocess.run(['/var/jb/usr/bin/launchctl'] + list(args), stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=15)
    return result.returncode, result.stdout.decode('utf-8', 'replace')

def collect():
    labels = ('com.apple.sysdiagnose', 'com.apple.sysdiagnose_helper')
    with open(OVERRIDES_PATH, 'rb') as source:
        overrides = plistlib.load(source)
    # Re-enable only the collection jobs, then restore each originally-off job.
    restore = []
    try:
        for label in labels:
            if overrides.get(label) is True:
                restore.append(label)
                code, output = launchctl('enable', 'system/' + label)
                if code != 0:
                    raise RuntimeError('Could not temporarily enable ' + label + ': ' + output[-300:])
            code, output = launchctl('print', 'system/' + label)
            if code != 0:
                code, output = launchctl('bootstrap', 'system', '/System/Library/LaunchDaemons/' + label + '.plist')
                if code != 0:
                    raise RuntimeError('Could not load ' + label + ': ' + output[-300:])
        os.makedirs(REPORT_ROOT, exist_ok=True)
        started = time.time()
        pid, fd = pty.fork()
        if pid == 0:
            os.execv('/usr/bin/sysdiagnose', ['sysdiagnose', '-f', REPORT_ROOT, '-n'])
        output = b''
        answered = False
        status = None
        try:
            while time.time() - started < 900:
                ready, _, _ = select.select([fd], [], [], 1)
                if ready:
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        chunk = b''
                    output = (output + chunk)[-65536:]
                    if not answered and b"Press 'Enter' to continue" in output:
                        os.write(fd, b'\n')
                        answered = True
                done, child_status = os.waitpid(pid, os.WNOHANG)
                if done:
                    status = child_status
                    break
            if status is None:
                os.kill(pid, signal.SIGQUIT)
                for _ in range(10):
                    done, child_status = os.waitpid(pid, os.WNOHANG)
                    if done:
                        status = child_status
                        break
                    time.sleep(.5)
                if status is None:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                raise RuntimeError('Diagnostic exceeded 15 minutes and was cancelled.')
            if status != 0:
                raise RuntimeError('sysdiagnose failed: ' + output.decode('utf-8', 'replace')[-600:])
        finally:
            os.close(fd)
        candidates = [p for p in glob.glob(REPORT_ROOT + '/sysdiagnose*') if os.path.getmtime(p) >= started]
        if not candidates:
            raise RuntimeError('sysdiagnose finished without a new report in ' + REPORT_ROOT)
        return read_report(max(candidates, key=os.path.getmtime))
    finally:
        failures = []
        for label in reversed(restore):
            try:
                code, output = launchctl('disable', 'system/' + label)
                if code != 0:
                    failures.append(label)
                    continue
                # Drop the loaded collection job as well as restoring its off override.
                launchctl('bootout', 'system/' + label)
            except Exception:
                failures.append(label)
        if failures:
            raise RuntimeError('Could not restore disabled diagnostic jobs: ' + ', '.join(failures))

def run(generate=False):
    try:
        result = collect() if generate else latest_report()
        print('disk_report=' + json.dumps(result, separators=(',', ':')))
    except Exception as error:
        print('disk_error=' + str(error))
        raise SystemExit(1)
"""#
}
