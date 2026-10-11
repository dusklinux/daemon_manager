import Foundation

// Compatible with the Python 3.9 runtime verified on the target iPhone.
// launchctl owns persistence; loaded jobs are left for a userspace restart.
enum NativeOverrides {
    static let script = #"""
import base64, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

PLIST = "/var/db/com.apple.xpc.launchd/disabled.plist"

def repair_metadata():
    if os.path.exists(PLIST):
        os.chown(PLIST, 0, 0)
        os.chmod(PLIST, 0o644)

def run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=30)

def apply(operations):
    repair_metadata()
    def change(item):
        label, action, domain = item
        try:
            result = run(["launchctl", action, domain + "/" + label])
            error = (result.stderr + result.stdout).strip() if result.returncode else None
            return item, result.returncode, error
        except subprocess.TimeoutExpired:
            return item, 124, "launchctl timed out"
    failed = False
    with ThreadPoolExecutor(max_workers=8) as pool:
        for (label, action, domain), code, error in pool.map(change, operations):
            print("[done] {} {}".format(action, label), flush=True)
            if code:
                failed = True
                print("[error] {}: exit {}: {}".format(label, code, error), flush=True)
    repair_metadata()
    states = {}
    for domain in sorted({item[2] for item in operations}):
        result = run(["launchctl", "print-disabled", domain])
        if result.returncode:
            failed = True
            print("[error] Cannot verify overrides in " + domain, flush=True)
            continue
        states[domain] = {label: state in ("disabled", "true") for label, state in
            re.findall(r'"([^\"]+)"\s*=>\s*(enabled|disabled|true|false)', result.stdout)}
    for label, action, domain in operations:
        state = states.get(domain, {}).get(label, False)
        if domain not in states or state != (action == "disable"):
            failed = True
            print("[error] Override verification failed for " + label, flush=True)
    print("[result] " + ("Some overrides failed." if failed else
          "Overrides verified. Restart userspace to apply process changes fully."), flush=True)
    return 1 if failed else 0
"""#
}
