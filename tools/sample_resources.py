#!/usr/bin/env python3
"""Read-only, finite iOS resource sample. Run as root using Python 3.9+.

No launchctl changes, app eviction, induced pressure, or resident polling.
CPU uses PROC_PIDTASKINFO with mach_timebase_info conversion; RSS is not
summed or presented as reclaimable RAM. Footprint uses RUSAGE_INFO_V2.
"""
import argparse
import ctypes as c
import json
import subprocess
import sys
import time


class TaskInfo(c.Structure):
    _fields_ = [(name, c.c_uint64) for name in
                ('virtual', 'resident', 'user', 'system', 'threads_user', 'threads_system')]
    _fields_ += [('counter' + str(i), c.c_int32) for i in range(12)]


class Usage(c.Structure):
    _fields_ = [('uuid', c.c_uint8 * 16)]
    _fields_ += [(name, c.c_uint64) for name in
                ('user', 'system', 'idle_wakeups', 'interrupt_wakeups', 'pageins',
                 'wired', 'resident', 'footprint', 'started', 'exited', 'child_user',
                 'child_system', 'child_idle', 'child_interrupt', 'child_pageins',
                 'child_elapsed', 'disk_read', 'disk_write')]


class Timebase(c.Structure):
    _fields_ = [('numer', c.c_uint32), ('denom', c.c_uint32)]


def sample(lib):
    pids = subprocess.run(['/bin/ps', '-A', '-o', 'pid='], check=True,
                          capture_output=True, text=True).stdout.split()
    processes = {}
    for value in pids:
        pid = int(value)
        task, usage = TaskInfo(), Usage()
        if lib.proc_pidinfo(pid, 4, 0, c.byref(task), c.sizeof(task)) != c.sizeof(task):
            continue
        if lib.proc_pid_rusage(pid, 2, c.byref(usage)) != 0:
            continue
        name = c.create_string_buffer(1024)
        lib.proc_name(pid, name, len(name))
        processes[pid] = {'name': name.value.decode('utf-8', 'replace'),
                          'started': usage.started, 'ticks': task.user + task.system,
                          'footprint_bytes': usage.footprint}
    pressure, size = c.c_int32(), c.c_size_t(4)
    rc = lib.sysctlbyname(b'kern.memorystatus_vm_pressure_level', c.byref(pressure),
                         c.byref(size), None, 0)
    memory = subprocess.run(['/usr/bin/vm_stat'], check=True,
                            capture_output=True, text=True).stdout
    return {'monotonic': time.monotonic(), 'processes': processes,
            'pressure_flags': pressure.value if rc == 0 else None, 'vm_stat': memory}


def deltas(before, after, numer, denom):
    elapsed = after['monotonic'] - before['monotonic']
    rows = []
    for pid, process in after['processes'].items():
        old = before['processes'].get(pid)
        if old is None or old['started'] != process['started']:
            continue
        ticks = process['ticks'] - old['ticks']
        if ticks < 0:
            continue
        seconds = ticks * numer / denom / 1e9
        rows.append({'pid': pid, 'name': process['name'], 'cpu_seconds': seconds,
                     'one_core_percent': 100 * seconds / elapsed,
                     'footprint_bytes': process['footprint_bytes']})
    return sorted(rows, key=lambda row: row['cpu_seconds'], reverse=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interval', type=float, default=10)
    parser.add_argument('--samples', type=int, default=3)
    args = parser.parse_args()
    if args.interval <= 0 or args.samples < 1:
        parser.error('interval must be positive and samples must be at least one')
    if sys.platform != 'darwin':
        parser.error('run this tool on the iOS device, not the Linux host')
    lib = c.CDLL(None)
    lib.proc_pidinfo.argtypes = [c.c_int, c.c_int, c.c_uint64, c.c_void_p, c.c_int]
    lib.proc_pid_rusage.argtypes = [c.c_int, c.c_int, c.c_void_p]
    lib.proc_name.argtypes = [c.c_int, c.c_void_p, c.c_uint32]
    tb = Timebase()
    if lib.mach_timebase_info(c.byref(tb)) != 0 or tb.denom == 0:
        raise RuntimeError('Cannot read Mach timebase')
    before = sample(lib)
    for _ in range(args.samples):
        time.sleep(args.interval)
        after = sample(lib)
        print(json.dumps({'elapsed_seconds': after['monotonic'] - before['monotonic'],
                          'timebase': [tb.numer, tb.denom],
                          'pressure_flags': after['pressure_flags'], 'vm_stat': after['vm_stat'],
                          'processes': deltas(before, after, tb.numer, tb.denom)}), flush=True)
        before = after


if __name__ == '__main__':
    main()
