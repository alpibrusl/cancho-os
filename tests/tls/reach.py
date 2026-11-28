#!/usr/bin/env python3
"""reach.py MODULE.ll [ROOT] -- the functions a module's ROOT (default main) can reach, and of those the ones the
module does not define, or defines without the name of a cancho function (the runtime's). A function whose address is
taken counts as reached, so the list can be long and cannot be short (the method of cancho docs/bare-system.md, 2)."""
import re, sys
text = open(sys.argv[1]).read()
root = sys.argv[2] if len(sys.argv) > 2 else "main"
defs, cur, body = {}, None, []
for line in text.split("\n"):
    m = re.match(r"define\b.*?@([\w.$]+)\(", line)
    if m:
        cur, body = m.group(1), []
        continue
    if cur is not None:
        if line.startswith("}"):
            defs[cur] = "\n".join(body); cur = None
        else:
            body.append(line)
declared = set(re.findall(r"^declare\b.*?@([\w.$]+)\(", text, re.M))
seen, todo = set(), [root]
while todo:
    f = todo.pop()
    if f in seen: continue
    seen.add(f)
    for g in re.findall(r"@([\w.$]+)", defs.get(f, "")):
        if g not in seen and (g in defs or g in declared): todo.append(g)
user = sorted(f for f in seen if f in defs and re.match(r"lexs_\d+$", f))
runtime = sorted(f for f in seen if f in defs and not re.match(r"lexs_\d+$", f))
outside = sorted(f for f in seen if f not in defs)
print("functions of the program reached:", len(user), "of", sum(1 for f in defs if re.match(r"lexs_\d+$", f)))
print("the runtime's, reached:", " ".join(runtime))
print("not defined in the module, reached:", " ".join(outside))
