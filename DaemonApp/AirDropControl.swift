import Foundation

enum AirDropControl {
    static let script = #"""
def air_drop(helper, action):
    label = "com.apple.managedconfiguration.profiled"
    target = "system/" + label
    path = "/System/Library/LaunchDaemons/" + label + ".plist"
    result = run(["launchctl", "print-disabled", "system"])
    if result.returncode:
        raise RuntimeError("Cannot read original profile service override")
    states = {key: value in ("disabled", "true") for key, value in
        re.findall(r'"([^\"]+)"\s*=>\s*(enabled|disabled|true|false)', result.stdout)}
    was_disabled = states.get(label, False)
    was_loaded = loaded(target)
    code = 1
    try:
        if was_disabled:
            if apply([[label, "enable", "system"]], announce=False):
                raise RuntimeError("Cannot enable profile service")
        if not was_loaded:
            result = run(["launchctl", "bootstrap", "system", path])
            if result.returncode:
                raise RuntimeError("Cannot load profile service: " + result.stderr.strip())
        result = run([helper, action])
        # Never publish a value from a failed helper as verified state.
        if result.returncode:
            raise RuntimeError("AirDrop policy failed: " + (result.stderr + result.stdout).strip())
        match = re.search(r'^airdrop_allowed=([01])$', result.stdout, re.M)
        if not match:
            raise RuntimeError("AirDrop helper did not return a verified state")
        print("airdrop_allowed=" + match.group(1), flush=True)
        code = 0
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print("[error] " + str(error), flush=True)
    finally:
        try:
            if was_disabled and apply([[label, "disable", "system"]], announce=False):
                raise RuntimeError("Cannot restore profile service override")
            if not was_loaded and loaded(target):
                result = run(["launchctl", "bootout", target])
                if result.returncode or loaded(target):
                    raise RuntimeError("Cannot restore unloaded profile service state")
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            print("[error] " + str(error), flush=True)
            code = 1
    return code
"""#
}
