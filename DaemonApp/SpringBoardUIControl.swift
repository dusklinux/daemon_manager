import Foundation

struct SpringBoardUIRuntime: Decodable {
    let pid: Int
    let version: Int
    let supported: [String: Bool]
    let disabled: [String: Bool]
}

struct SpringBoardUIState: Decodable {
    let installed: Bool
    let saved: [String: Bool]
    let runtime: SpringBoardUIRuntime?

    var pending: Bool {
        if let runtime { return runtime.disabled != saved }
        return installed
    }
}

enum SpringBoardUIControl {
    static let keys = ["controlCenter", "appLibrary", "dock", "statusBar"]
    static let script = #"""
import json, os, pathlib, plistlib, pwd, re, subprocess, tempfile

def ui_control(asset, action, values):
    mobile = pwd.getpwnam("mobile")
    # The rootless bootstrap's passwd home can be /var/jb/var/mobile.
    # SpringBoard uses the native iOS mobile home, outside that bootstrap.
    home = pathlib.Path("/var/mobile")
    folder = pathlib.Path("/var/jb/Library/MobileSubstrate/DynamicLibraries")
    config = home / "Library/Preferences/com.dusklinux.DaemonManagerUI.plist"
    report = home / "Library/Caches/daemon-manager-ui-runtime.json"
    binary = folder / "DaemonManagerUI.dylib"
    filter_path = folder / "DaemonManagerUI.plist"
    keys = ("controlCenter", "appLibrary", "dock", "statusBar")
    saved = {key: False for key in keys}
    if config.exists():
        existing = plistlib.loads(config.read_bytes())
        for key in keys:
            if key in existing:
                if type(existing[key]) is not bool:
                    raise ValueError("Invalid interface setting: " + key)
                saved[key] = existing[key]

    def write_atomic(path, data, uid, gid, mode):
        fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            os.chown(temporary, uid, gid)
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    if action == "set":
        if not folder.is_dir():
            raise RuntimeError("This control requires the rootless tweak loader directory")
        if not values or any(key not in keys or type(value) is not bool for key, value in values.items()):
            raise ValueError("Invalid interface changes")
        asset_data = pathlib.Path(asset).read_bytes()
        if not binary.exists() or binary.read_bytes() != asset_data:
            write_atomic(binary, asset_data, 0, 0, 0o755)
            report.unlink(missing_ok=True)
        write_atomic(filter_path, plistlib.dumps({"Filter": {"Bundles": ["com.apple.springboard"]}}), 0, 0, 0o644)
        saved.update(values)
        write_atomic(config, plistlib.dumps(saved), mobile.pw_uid, mobile.pw_gid, 0o644)
        print("[info] Interface settings saved. Respring to apply.")
    elif action == "remove":
        saved = {key: False for key in keys}
        write_atomic(config, plistlib.dumps(saved), mobile.pw_uid, mobile.pw_gid, 0o644)
        binary.unlink(missing_ok=True)
        filter_path.unlink(missing_ok=True)
        print("[info] Companion removed. Respring to restore the interfaces.")
    elif action != "read":
        raise ValueError("Unknown interface action")

    runtime = None
    try:
        candidate = json.loads(report.read_text())
        result = subprocess.run(["launchctl", "print", "system/com.apple.SpringBoard"], capture_output=True, text=True, timeout=10)
        match = re.search(r"^\s*pid = (\d+)$", result.stdout, re.M)
        if result.returncode == 0 and match and candidate.get("version") == 1 and candidate.get("pid") == int(match.group(1)):
            runtime = candidate
    except (OSError, ValueError):
        pass
    print("ui_state=" + json.dumps({"installed": binary.exists() and filter_path.exists(), "saved": saved, "runtime": runtime}))
"""#
}
