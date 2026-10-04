"""Runs the Trainer Locator tests: the data builder's checks in Python (the "build" scenario,
test_build.py), then the addon in real Lua 5.1 (lupa) against a mock of the WoW: Forever API.

    python3 -m venv /tmp/wowlua && /tmp/wowlua/bin/pip install lupa
    /tmp/wowlua/bin/python tools/test/run.py [scenario ...]
"""
import os
import sys

import lupa.lua51 as lua51

import test_build

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIOS = ["build", "basics", "professions", "search", "waypoint", "link", "pins", "combat", "otherfaction", "lowtrainer",
             "instance", "options", "minimap", "alldata"]

failed = 0
for scenario in sys.argv[1:] or SCENARIOS:
    print(f"--- {scenario}", flush=True)
    if scenario == "build":
        failed += test_build.run()
        continue
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute('io.stdout:setvbuf("no")')   # Lua's print in order with Python's when piped
    failed += rt.eval('function(dir, s) return assert(loadfile(dir .. "/test/tltest.lua"))(dir, s) end')(TOOLS, scenario)
print("FAILED" if failed else "all passed", failed)
sys.exit(1 if failed else 0)
