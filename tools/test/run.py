"""Runs the Trainer Locator tests in real Lua 5.1 (lupa) against a mock of the WoW: Forever API.

    python3 -m venv /tmp/wowlua && /tmp/wowlua/bin/pip install lupa
    /tmp/wowlua/bin/python tools/test/run.py [scenario ...]
"""
import os
import sys

import lupa.lua51 as lua51

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIOS = ["basics", "professions", "search", "waypoint", "pins", "otherfaction", "lowtrainer", "instance", "options", "minimap", "alldata"]

failed = 0
for scenario in sys.argv[1:] or SCENARIOS:
    print(f"--- {scenario}", flush=True)
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    failed += rt.eval('function(dir, s) return assert(loadfile(dir .. "/test/tltest.lua"))(dir, s) end')(TOOLS, scenario)
print("FAILED" if failed else "all passed", failed)
sys.exit(1 if failed else 0)
