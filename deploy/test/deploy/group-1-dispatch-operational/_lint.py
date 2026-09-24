# Lint helper for the bench-console scripts in this folder.
#
# They are piped into IPython, which treats a BLANK LINE as end-of-block and does
# not expose module globals to a function body. So each script must be a single
# function with no blank lines inside it, followed by the call. A blank line in
# the wrong place truncates the script silently and it appears to "do nothing".
#
# Usage:  python deploy/test/deploy/group-1-dispatch-operational/_lint.py
import ast
import glob
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
bad = 0
for path in sorted(glob.glob(os.path.join(here, "*.py"))):
    name = os.path.basename(path)
    if name.startswith("_"):
        continue
    src = open(path, encoding="utf-8-sig").read()
    try:
        ast.parse(src)
    except SyntaxError as e:
        print("SYNTAX  %-38s line %s: %s" % (name, e.lineno, e.msg))
        bad += 1
        continue
    lines = src.split("\n")
    defs = [i for i, l in enumerate(lines) if l.startswith("def ")]
    if not defs:
        print("ok      %-38s (no top-level def)" % name)
        continue
    start = defs[0]
    fname = lines[start].split("def ", 1)[1].split("(")[0]
    calls = [i for i, l in enumerate(lines) if l.startswith(fname + "(")]
    end = calls[0] if calls else len(lines)
    blanks = [i + 1 for i in range(start, end) if lines[i].strip() == ""]
    if blanks:
        print("BLANK   %-38s blank line(s) inside %s(): %s" % (name, fname, blanks))
        bad += 1
    else:
        print("ok      %-38s %s() clean, %d lines" % (name, fname, end - start))

print("")
print("%d file(s) with problems" % bad)
sys.exit(1 if bad else 0)
