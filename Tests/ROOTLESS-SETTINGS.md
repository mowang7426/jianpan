# Rootless settings loading regression (1.2.3)

## Confirmed from the 3656aff CI package

- PreferenceLoader entry and bundle were already installed in the correct `/var/jb/Library` directories. Do not add another prefix in the custom `internal-stage` recipe: Theos relocates it later.
- The Rootless tweak and preference bundle had only the `arm64` slice. Use `arm64 arm64e` for both; Debian architecture stays `iphoneos-arm64`. RootHide remains a separate `iphoneos-arm64e` package built as `arm64e`.
- Preference symbols (`PSListController`, `PSSpecifier`, `_specifiers`) used flat-namespace dynamic lookup. The bundle did not explicitly link Preferences. The Theos 16.5 SDK does include its link stub. Use that SDK explicitly and link the framework instead of hiding missing symbols with `-undefined dynamic_lookup`.
- These are packaging/compatibility fixes, not proof of the reported device's exact failure. The screenshot is a truncated AlarmLiveActivity extension crash summary, not a Preferences loading trace.

## Automated gate

Both GitHub Actions builds run:

```
python3 Tests/verify-package.py build/RainbowKeyboard-rootless.deb rootless
python3 Tests/verify-package.py build/RainbowKeyboard-roothide.deb roothide
```

The checker inspects the actual deb, validates paths, resources, entry/main-class agreement, version, executable modes, Mach-O architectures and an explicit Preferences load command in each settings slice. No device execution is claimed by these tests.

## On-device acceptance

1. Install the **Rootless** artifact on a conventional Rootless jailbreak, not the RootHide artifact. Check `preferenceloader` is installed and tweak injection into Settings is enabled. Quit Settings completely and reopen it (respring if the jailbreak requires it).
2. Confirm Settings → 彩虹键盘光效 is present. Open the main, advanced and candidate pages; save a setting, close/reopen and confirm persistence. Existing preference values are not reset by this update.
3. Test both an arm64 device and an A12+ arm64e device/Settings process where available.
4. If still missing, distinguish no entry, entry that fails to load, and Settings crashing. Supply device model, iOS version, jailbreak/injection environment, exact package version and the full Preferences/Settings `.ips` or dyld error. Alarm-extension crash summaries alone do not identify a settings-bundle failure.

## Separate known risk

This branch preserves the user-requested `3656aff` rollback: PureBlackKeyboard hooks are enabled. The earlier `fd4ab7a` isolation build disabled those hooks and the user reported that freezing stopped. **1.2.3 does not fix that runtime risk.** Adding architecture coverage can make the existing hooks load in more system processes; keep this as a controlled compatibility test, not a claim of a stable public release. No keyboard runtime hooks or effects were changed for this packaging fix.
