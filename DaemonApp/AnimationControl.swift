import Foundation

enum AnimationControl {
    static let script = #"""
import os, plistlib
BASE = '/var/jb/Library/MobileSubstrate/DynamicLibraries/NoAnimationsX'

def run(disable=None):
    try:
        base = BASE
        active = base + '.plist'
        inactive = base + '.plist.daemonmanager-disabled'
        if not os.path.isfile(base + '.dylib'):
            raise RuntimeError('Install NoAnimationsX 1.2 rootless from the developer’s repository in Sileo first.')
        if os.path.exists(active) == os.path.exists(inactive):
            raise RuntimeError('Animation filter is missing or duplicated; inspect the NoAnimationsX installation.')
        source = active if os.path.exists(active) else inactive
        with open(source, 'rb') as handle:
            filters = plistlib.load(handle)
        if filters != {'Filter': {'Bundles': ['com.apple.springboard']}}:
            raise RuntimeError('The installed filter is not the verified SpringBoard-only filter.')
        if disable is not None:
            destination = active if disable else inactive
            if source != destination:
                os.rename(source, destination)
        print('animations_disabled=' + str(os.path.exists(active)))
    except Exception as error:
        print('animation_error=' + str(error))
        raise SystemExit(1)
"""#
}
