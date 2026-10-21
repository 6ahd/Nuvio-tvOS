#!/usr/bin/env python3
"""Companion acceptance for NativeApplicationTests' real XCUIRemote presses.

Pass the simulator application's nuvio.log after running only the navigation
case. The trace is sampled from UIWindowScene.focusSystem, not from C selection
state or the test's expectations. Only aggregate results are emitted.
"""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("log", type=Path)
parser.add_argument("--json", type=Path)
args = parser.parse_args()
steps = re.findall(r"\[native-probe\] focus=(native-control-\d+)", args.log.read_text(errors="replace"))
steps = [value for index, value in enumerate(steps) if index == 0 or value != steps[index - 1]]
# Home hero -> first row -> next poster -> next row -> previous row, retaining
# its selected column. A direct-input receiver, missed direction, stale focus
# or focus loss cannot satisfy these five real UIKit focus transitions.
accepted = any(len(set(part[:4])) == 4 and part[4] == part[2]
               for part in (steps[index:index + 5] for index in range(max(0, len(steps) - 4))))
result = {"result": "passed" if accepted else "failed", "native_focus_transitions": len(steps),
          "scenario": "down, right, down, up with row-column restoration"}
if args.json:
    args.json.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result))
raise SystemExit(0 if accepted else 1)
