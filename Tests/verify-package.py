#!/usr/bin/env python3
"""Validate real deb payloads, not just existence/size. Python stdlib + dpkg-deb.

Rootless Debian architecture is iphoneos-arm64; Mach-O must contain arm64 AND
arm64e. RootHide remains a separate iphoneos-arm64e package without /var/jb.
No archive extraction or Apple command line tools are needed to inspect it.
"""
import io
import json
import plistlib
import struct
import subprocess
import sys
import tarfile
from pathlib import Path

PREFERENCES = '/System/Library/PrivateFrameworks/Preferences.framework/Preferences'


def macho_slices(data):
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        assert 0 < count <= 8, 'invalid fat architecture count'
        slices = []
        for i in range(count):
            cpu, sub, offset, size, align = struct.unpack_from('>5I', data, 8 + i * 20)
            assert offset + size <= len(data), 'truncated fat slice'
            slices.extend(macho_slices(data[offset:offset + size]))
        return slices
    assert data[:4] == b'\xcf\xfa\xed\xfe', 'expected 64-bit Mach-O'
    _, cpu, sub, kind, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', data)
    assert cpu == 0x0100000c, 'expected ARM64 CPU type'
    arch = {0: 'arm64', 2: 'arm64e'}.get(sub & 0xffffff)
    assert arch, 'unsupported ARM64 subtype'
    assert ncmds < 256 and 32 + sizeofcmds <= len(data), 'invalid Mach-O commands'
    dylibs = []
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', data, offset)
        assert size >= 8 and offset + size <= 32 + sizeofcmds, 'bad load command'
        # Normal/weak/reexport/upward dylib load commands (not LC_ID_DYLIB).
        if cmd in (0xc, 0x80000018, 0x8000001f, 0x80000023):
            name_offset = struct.unpack_from('<I', data, offset + 8)[0]
            assert 0 < name_offset < size, 'invalid dylib name offset'
            dylibs.append(data[offset + name_offset:offset + size].split(b'\0')[0].decode())
        offset += size
    assert offset == 32 + sizeofcmds, 'load command size mismatch'
    return [(arch, dylibs)]


def verify(deb, scheme):
    control = subprocess.check_output(['dpkg-deb', '-f', str(deb)], text=True)
    fields = dict(line.split(': ', 1) for line in control.splitlines()
                  if ': ' in line and not line.startswith(' '))
    required_arch = 'iphoneos-arm64' if scheme == 'rootless' else 'iphoneos-arm64e'
    assert fields['Architecture'] == required_arch, 'wrong Debian architecture'
    assert 'preferenceloader' in fields['Depends'], 'missing PreferenceLoader dependency'
    prefix = 'var/jb/' if scheme == 'rootless' else ''
    expected_slices = {'arm64', 'arm64e'} if scheme == 'rootless' else {'arm64e'}
    archive = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(deb)])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members = {m.name.removeprefix('./'): m for m in tar.getmembers() if m.isfile()}
        wrong_prefix = 'Library/' if prefix else 'var/jb/'
        assert not any(p.startswith(wrong_prefix) for p in members), 'mixed package install schemes'

        def read(relative):
            path = prefix + relative
            assert path in members, 'missing packaged resource: ' + path
            return tar.extractfile(members[path]).read()

        base = 'Library/PreferenceBundles/RainbowKeyboardPrefs.bundle/'
        entry = plistlib.loads(read('Library/PreferenceLoader/Preferences/com.minis.rainbowkeyboard.prefs.plist'))['entry']
        info = plistlib.loads(read(base + 'Info.plist'))
        assert entry['bundle'] == 'RainbowKeyboardPrefs'
        assert entry['detail'] == info['NSPrincipalClass'] == 'RKBRootListController'
        assert entry['cell'] == 'PSLinkCell' and entry['isController'] is True
        assert info['CFBundleExecutable'] == 'RainbowKeyboardPrefs'
        assert info['CFBundleVersion'] == fields['Version'], 'stale bundle version'
        assert json.loads(read(base + 'PackageInfo.json'))['version'] == fields['Version']
        for name in ('RainbowKeyboard', 'RainbowKeyboardAdvanced', 'RainbowKeyboardCandidate', 'defaults', 'SliderHelp'):
            resource = plistlib.loads(read(base + name + '.plist'))
            assert resource, 'empty settings resource: ' + name
        root = plistlib.loads(read(base + 'RainbowKeyboard.plist'))
        assert root.get('items'), 'settings list has no items'
        for icon in ('icon.png', 'icon@2x.png', 'icon@3x.png'):
            assert read(base + icon), 'empty icon'
        plistlib.loads(read('Library/MobileSubstrate/DynamicLibraries/RainbowKeyboard.plist'))
        binaries = (base + 'RainbowKeyboardPrefs', 'Library/MobileSubstrate/DynamicLibraries/RainbowKeyboard.dylib')
        for binary in binaries:
            assert members[prefix + binary].mode & 0o111, 'binary not executable'
            slices = macho_slices(read(binary))
            found = {a for a, _ in slices}
            assert found == expected_slices, f'{binary}: slices {found}, expected {expected_slices}'
            for arch, dylibs in slices:
                if binary.endswith('/RainbowKeyboardPrefs'):
                    assert PREFERENCES in dylibs, f'{arch}: settings must explicitly link Preferences'
                assert not any('/Users/' in lib or '/tmp/' in lib for lib in dylibs), 'build-machine dependency leaked'
                print(f'PASS {arch}: {binary}')
    print(f'PASS {scheme} {fields["Version"]}: settings entry, resources, paths, architectures, dependencies')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[2] not in ('rootless', 'roothide'):
        sys.exit('usage: verify-package.py package.deb rootless|roothide')
    verify(Path(sys.argv[1]), sys.argv[2])
