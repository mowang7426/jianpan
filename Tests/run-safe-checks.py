#!/usr/bin/env python3
"""Native Foundation theme checks and safe production source selection guard."""
import plistlib
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
makefile = (root / 'Makefile').read_text()
files = next(x.split(':=', 1)[1].split() for x in makefile.splitlines() if x.startswith('RainbowKeyboard_FILES := '))
assert 'PureBlackKeyboard.xm' not in files
assert 'RKBlackKeyboardDisabled.m' in files and 'RKPreferencesRelay.m' in files
for file in ('Tweak.xm', 'CandidateGradient.xm', 'RainbowEffectView.m'):
    assert file in files
stub = (root / 'RKBlackKeyboardDisabled.m').read_text()
assert 'void RKApplyBlackKeyboardHost(__unused UIView *host) {}' in stub
assert '%hook' not in stub and '%init' not in stub
startup = (root / 'RKPreferencesRelay.m').read_text()
assert '__attribute__((constructor))' in startup and 'RKStartPreferencesRelay();' in startup
print('PASS safe build selection: independent relay, no PureBlack implementation', flush=True)
with tempfile.TemporaryDirectory(prefix='rk-safe-theme-') as temp:
    for role, bundle in [('native', 'com.minis.tests.native'), ('wetype', 'com.minis.tests.wetype')]:
        contents = Path(temp) / (role + '.app') / 'Contents'
        exe = contents / 'MacOS' / 'ThemeProbe'
        exe.parent.mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle,
            'CFBundleExecutable': 'ThemeProbe', 'CFBundlePackageType': 'APPL'}))
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                        str(root/'Tests/SafeThemeProbe.m'), str(root/'RKThemeEngine.m'), '-o', str(exe)], check=True)
        subprocess.run([str(exe)], check=True, timeout=15)
