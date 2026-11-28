#!/usr/bin/env python3
"""soften.py CANCHO_CHECKOUT OUT_DIR -- a copy of cancho's std and of packages/tls and packages/x509 in which the CPU is
never asked for its AES and SHA instructions: every `hw_sha256()` and `hw_aes_gcm()` is `false`, and the calls of the
builtins behind them are taken out. It is the software path the library already has, alone, so that the bare target,
which refuses those builtins, can be asked whether anything else is in the way. For measuring only (docs/tls.md)."""
import os, re, shutil, sys
src, out = sys.argv[1], sys.argv[2]
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
def sub(text, pattern, to, n):
    new, k = re.subn(pattern, to, text, flags=re.S)
    assert k == n, (pattern, k, n)
    return new
count = 0
for d in ("std", "packages/tls", "packages/x509"):
    for f in sorted(os.listdir(os.path.join(src, d))):
        if not f.endswith(".cho"):
            continue
        t = open(os.path.join(src, d, f)).read()
        if d == "std" and f == "crypto.cho":
            t = sub(t, r"    if hw_sha256\(\) \{\n        return sha256_blocks\([^\n]*\n    \}\n", "", 1)
            t = sub(t, r"    if hw_sha256\(\) \{\n        sha256_block_words\([^\n]*\n    \} else \{\n(.*?)\n    \}\n    return clear_block", r"    if true {\n\1\n    }\n    return clear_block", 1)
            count += 4
        if d == "std" and f == "gcm.cho":
            t = sub(t, r"\n *ghash_powers\([^\n]*", "", 1)
            t = sub(t, r"\n *aes_ctr32\([^\n]*", "", 4)
            t = sub(t, r"\n *gcm_tag\([^\n]*", "", 2)
            t = sub(t, r"gcm_tag_diff\([^\n]*\);", "1;", 2)
            count += 9
        k = len(re.findall(r"hw_aes_gcm\(\)|hw_sha256\(\)", "\n".join(l for l in t.split("\n") if not l.lstrip().startswith("//"))))
        t = "\n".join(l if l.lstrip().startswith("//") else re.sub(r"hw_aes_gcm\(\)|hw_sha256\(\)", "false", l) for l in t.split("\n"))
        count += k
        os.makedirs(os.path.join(out, d), exist_ok=True)
        open(os.path.join(out, d, f), "w").write(t)
print("call sites answered no or taken out:", count)
