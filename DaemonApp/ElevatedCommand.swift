import Foundation

struct ElevatedCommand {
    let executable: String
    let arguments: [String]
    let standardInput: String

    static func build(command: String, password: String, shell: String,
                      sudo: String, python: String, hasSudo: Bool) -> ElevatedCommand {
        let input = password + "\n"
        if hasSudo {
            return ElevatedCommand(executable: sudo,
                arguments: ["-S", "-p", "", "--", shell, "-c", command], standardInput: input)
        }
        return ElevatedCommand(executable: python,
            arguments: ["-c", suScript, "/var/jb/usr/bin/su", "-", "root", "-c", command],
            standardInput: input)
    }

    // Password comes from stdin. The original command is forwarded unchanged;
    // it must not receive the escaping used for a surrounding shell string.
    static let suScript = #"""
import os, sys, pty, select
pw = sys.stdin.readline().removesuffix("\n")
cmd = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execv(cmd[0], cmd)
buf = b""
while True:
    ready, _, _ = select.select([fd], [], [], 2.0)
    if not ready:
        break
    try:
        chunk = os.read(fd, 1024)
        if not chunk:
            break
        buf = (buf + chunk)[-4096:]
        if b"assword" in buf:
            break
    except OSError:
        break
try:
    os.write(fd, (pw + "\n").encode())
    while True:
        chunk = os.read(fd, 4096)
        if not chunk:
            break
        sys.stdout.buffer.write(chunk)
        sys.stdout.flush()
except OSError:
    pass
finally:
    os.close(fd)
_, status = os.waitpid(pid, 0)
code = os.waitstatus_to_exitcode(status)
sys.exit(code if code >= 0 else 128 - code)
"""#
}
