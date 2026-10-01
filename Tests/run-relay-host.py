#!/usr/bin/env python3
"""macOS Foundation/libnotify integration tests; --static-check needs only Python."""
import argparse, ast, json, os
from pathlib import Path
import plistlib, re, select, subprocess
import sys, tempfile, time, uuid

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "Tests/relay-host"
BASE = "com.minis.rainbowkeyboard"
SAVED = "/var/mobile/Library/Preferences/" + BASE + ".plist"

def sources():
    result = {}
    def load(name):
        if name in result:
            return
        result[name] = (ROOT / name).read_text()
        for header in re.findall(r'^#(?:import|include) "([^"]+)"', result[name], re.M):
            load(header)
    load("RKPreferencesRelay.m")
    ctor = result["RKPreferencesRelay.m"]
    assert "__attribute__((constructor))" in ctor and "dispatch_get_main_queue()" in ctor
    assert "RKStartPreferencesRelay();" in ctor and "RKRequestPreferencesRelay();" in ctor
    assert SAVED in result["RKPreferences.h"]
    assert 'CFSTR("' + BASE + '")' in result["RKPreferences.h"]
    probe = (HOST / "Probe.m").read_text()
    assert not re.search(r'RK(?:InstallPreferencesRelayObservers|StartPreferencesRelay)\s*\(', probe)
    assert "@implementation" not in (HOST / "UIKit/UIKit.h").read_text()
    return dict(result, **{"Probe.m": probe})

def prepare(work, source, namespace, isolated):
    target = work / ("isolated" if isolated else "shared")
    target.mkdir()
    disk = namespace + (".inaccessible" if isolated else ".stored")
    path = work / ("missing/never-created.plist" if isolated else "saved.plist")
    for name, text in source.items():
        text = text.replace(SAVED, str(path)).replace(BASE, namespace)
        text = text.replace('CFSTR("' + namespace + '")', 'CFSTR("' + disk + '")')
        text = text.replace("com.apple.springboard", namespace + ".relay")
        assert SAVED not in text and "com.apple.springboard" not in text
        assert not re.search(re.escape(BASE) + r'(?!\.relaytest\.)', text)
        (target / name).parent.mkdir(parents=True, exist_ok=True)
        (target / name).write_text(text)
    return target

def build(work, shared, isolated, namespace):
    flags = ["xcrun", "clang", "-fobjc-arc", "-fblocks", "-O1", "-Wall", "-Wextra",
             "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-I", str(HOST),
             "-include", "dispatch/dispatch.h"]
    for folder in (shared, isolated):
        for stem in ("Probe", "RKPreferencesRelay"):
            subprocess.run(flags + ["-I", str(folder), "-c", str(folder / (stem + ".m")),
                                   "-o", str(folder / (stem + ".o"))], check=True, timeout=60)
    apps = {}
    for role, folder, startup, identity in (("control", isolated, False, "control"),
            ("reader", isolated, True, "reader"), ("writer", shared, True, "writer"),
            ("omitted", shared, False, "relay"), ("relay", shared, True, "relay")):
        contents = work / (role + ".app") / "Contents"
        executable = contents / "MacOS/Probe"
        executable.parent.mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as out:
            plistlib.dump({"CFBundleIdentifier":namespace + "." + identity,
                          "CFBundleExecutable":"Probe", "CFBundlePackageType":"APPL"}, out)
        objects = [str(folder / "Probe.o")]
        if startup:
            objects.append(str(folder / "RKPreferencesRelay.o"))
        subprocess.run(flags + objects + ["-framework", "Foundation", "-o", str(executable)],
                       check=True, timeout=60)
        apps[role] = executable
    return apps

class Actor:
    def __init__(self, executable):
        self.error_path = executable.parent.parent / "stderr.log"
        self.error = self.error_path.open("ab")
        self.process = subprocess.Popen([str(executable)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=self.error)
        self.buffer = b""

    def ask(self, op, **arguments):
        process = self.process
        process.stdin.write((json.dumps(dict(op=op, **arguments)) + "\n").encode())
        process.stdin.flush()
        deadline = time.monotonic() + 6
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            assert remaining > 0, f"{op}: deadline; {self.error_path.read_text()}"
            assert select.select([process.stdout], [], [], remaining)[0], f"{op}: no reply"
            data = os.read(process.stdout.fileno(), 65536)
            assert data, f"child exited {process.poll()}: {self.error_path.read_text()}"
            self.buffer += data
        line, self.buffer = self.buffer.split(b"\n", 1)
        reply = json.loads(line)
        assert "error" not in reply and reply.get("ok", True), reply
        return reply

    def stop(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.process.stdout.close()
        self.error.close()

def wait_for(check, label, seconds=6):
    deadline = time.monotonic() + seconds
    while True:
        if check():
            return
        remaining = deadline - time.monotonic()
        assert remaining > 0, "deadline: " + label
        select.select([], [], [], min(.04, remaining))

def matches(actual, expected):
    if not isinstance(actual, dict):
        return False
    for key, value in expected.items():
        got = actual.get(key)
        if isinstance(value, list):
            if not isinstance(got, list) or len(got) != len(value):
                return False
            if any(not abs(a - b) <= 2e-5 for a, b in zip(got, value)):
                return False
        elif isinstance(value, float):
            if not isinstance(got, (int, float)) or not abs(got - value) <= 2e-5:
                return False
        elif got != value:
            return False
    return True

def exercise(apps, work, namespace):
    actors = []
    def start(role):
        actor = Actor(apps[role])
        actors.append(actor)
        info = actor.ask("read")
        identity = "relay" if role == "omitted" else role
        assert info["bundle"] == namespace + "." + identity, info
        return actor
    def restored():
        info = reader.ask("read")
        assert info["stored"] == {}, "reader must not see file or domain"
        return matches(info["snapshot"], saved) and matches(info["effective"], saved)
    def absent_for(actor, seconds=1.3):
        deadline = time.monotonic() + seconds
        def check():
            control.ask("request", count=1)
            assert actor.ask("read")["snapshot"] is None, "unauthorized/missing ctor restored state"
            return time.monotonic() >= deadline
        wait_for(check, "negative relay gate", seconds + 2)
    try:
        control, writer = start("control"), start("writer")
        values = {key: True for key in ("Enabled", "RippleEnabled", "CandidateGradient",
                                       "CandidateNative", "CandidateWeType")}
        values.update(Opacity=.42, Brightness=.73, CandidateStart=[.17, .63, .28],
                      CandidateEnd=[.89, .15, .4], KeyboardBackgroundColor=[.08, .03, .13],
                      KeycapColor=[.72, .32, .61])
        saved = writer.ask("save", values=values)["values"]
        writer.stop()
        original_file = (work / "saved.plist").read_bytes()
        control.ask("clear")
        omitted = start("omitted")
        assert matches(omitted.ask("read")["stored"], saved)
        absent_for(omitted)  # Same relay bundle ID and header, but no constructor object.
        omitted.stop()
        writer = start("writer")
        assert matches(writer.ask("read")["stored"], saved)
        absent_for(writer)  # Constructor linked, saved file accessible, wrong bundle ID.
        reader = start("reader")
        assert reader.ask("read")["stored"] == {}
        relay = start("relay")
        wait_for(restored, "cold saved restore without another save")
        assert (work / "saved.plist").read_bytes() == original_file
        print("PASS constructor-only cold restore and both negative controls", flush=True)
        for enabled, opacity, brightness in ((False, .18, .29), (True, .81, .94)):
            values.update({key: enabled for key in ("Enabled", "RippleEnabled", "CandidateGradient",
                                                    "CandidateNative", "CandidateWeType")})
            values.update(Opacity=opacity, Brightness=brightness, CandidateStart=[opacity, .31, brightness])
            previous = saved["RKSettingsRevision"]
            saved = writer.ask("save", values=values)["values"]
            assert saved["RKSettingsRevision"] > previous
            wait_for(restored, "live on-off-on update")
        assert reader.ask("hot")["reads"] <= 2, "unbounded stored reads on hot path"
        relay.stop()
        for fault in ("partial", "checksum", "clear"):
            control.ask(fault)
            info = reader.ask("read")
            assert info["snapshot"] is None and matches(info["effective"], saved), (fault, info)
        absent_for(writer)  # Nonrelay must not repair a lost snapshot, even after saves.
        original_file = (work / "saved.plist").read_bytes()
        relay = start("relay")
        wait_for(restored, "recovery after invalid snapshots")
        baseline = control.ask("stats")["changes"]
        def quiet():
            assert control.ask("stats")["changes"] <= baseline + 2, "notification feedback loop"
            return time.monotonic() >= until
        until = time.monotonic() + 1.3
        wait_for(quiet, "settling notifications")
        control.ask("clear")
        assert control.ask("read")["snapshot"] is None
        wait_for(restored, "live relay recovers lost notify state on reader request")
        baseline = control.ask("stats")
        until = time.monotonic() + 2
        def requests_bounded():
            control.ask("request", count=100)
            stats = control.ask("stats")
            assert stats["changes"] <= baseline["changes"] + 4, stats
            return time.monotonic() >= until
        wait_for(requests_bounded, "idempotent repeated requests")
        assert control.ask("stats")["requests"] > baseline["requests"]
        assert (work / "saved.plist").read_bytes() == original_file
        assert restored()
        print("PASS live flags/colors, cache, partial/checksum retention, state loss, bounded requests", flush=True)
    finally:
        for actor in reversed(actors):
            actor.stop()
        cleanup = Actor(apps["writer"])
        try:
            cleanup.ask("cleanup")
        finally:
            cleanup.stop()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-check", action="store_true")
    args = parser.parse_args()
    ast.parse(Path(__file__).read_text())
    source = sources()
    with tempfile.TemporaryDirectory(prefix="rk-relay-") as directory:
        work = Path(directory)
        namespace = BASE + ".relaytest." + uuid.uuid4().hex
        shared = prepare(work, source, namespace, False)
        isolated = prepare(work, source, namespace, True)
        if args.static_check:
            print("PASS Python syntax, production constructor/dependencies, namespace/path isolation; native tests NOT run")
            return
        if sys.platform != "darwin":
            parser.error("native tests require macOS Foundation/libnotify; use --static-check on Linux")
        exercise(build(work, shared, isolated, namespace), work, namespace)

if __name__ == "__main__":
    main()
