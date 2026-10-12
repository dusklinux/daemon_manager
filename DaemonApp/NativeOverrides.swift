import Foundation

// Compatible with the Python 3.9 runtime verified on the target iPhone.
// launchctl owns persistence; only the tested feature catalog supports live loading.
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

def apply(operations, announce=True):
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
    if announce:
        print("[result] " + ("Some overrides failed." if failed else
              "Overrides verified. Restart userspace to apply process changes fully."), flush=True)
    return 1 if failed else 0

def loaded(target):
    result = run(["launchctl", "print", target])
    if result.returncode == 0:
        return True
    if result.returncode == 113:
        return False
    raise RuntimeError("Cannot read job state: " + (result.stderr + result.stdout).strip())

def apply_live(operations):
    # Used only for the tested feature hosts, never core dependency batches.
    if apply([item[:3] for item in operations], announce=False):
        return 1
    failed = False
    for label, action, domain, path in operations:
        target = domain + "/" + label
        try:
            present = loaded(target)
            if action == "disable" and present:
                result = run(["launchctl", "bootout", target])
            elif action == "enable" and not present:
                result = run(["launchctl", "bootstrap", domain, path])
            else:
                result = None
            if result is not None and result.returncode:
                raise RuntimeError((result.stderr + result.stdout).strip())
            if loaded(target) != (action == "enable"):
                raise RuntimeError("Loaded job state did not match the requested feature state")
            print("[live] " + label + " " + action + " verified", flush=True)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            failed = True
            print("[error] {}: {}. Override was saved; restart userspace to retry.".format(label, error), flush=True)
    print("[result] " + ("Some feature changes failed." if failed else "Feature overrides and loaded job states verified."), flush=True)
    return 1 if failed else 0
"""#
}
