#!/usr/bin/env python3
"""Drive one module's emergent cascade to zero holes.

Per step: checkout the first open hole -> hand ONLY the brief (+ the fixed
operation manual) to a fresh, tool-disabled `claude -p` fill agent -> convert
its FILL/REFINE reply -> apply -> accept iff verify is SAFE and the filled
function is body-faithful; otherwise roll back and retry with the compiler's
error as feedback (max 3 attempts per hole). Every prompt, reply, request and
verdict is logged under audit/<module>/.

Usage: runner.py <module-name>
Env:   LLMLL_BIN (path to the llmll binary)
"""
import json, os, re, shutil, subprocess, sys

MODULE = sys.argv[1]
BASE = "/Users/burcsahinoglu/Documents/llmll/examples/token-revocation-emergent"
WORK = f"{BASE}/work"
AST = f"{WORK}/{MODULE}.ast.json"
AUDIT = f"{BASE}/audit/{MODULE}"
MANUAL = f"{BASE}/audit/OPERATION-MANUAL.md"
LLMLL = os.environ["LLMLL_BIN"]
DENY = ("Read,Glob,Grep,Bash,Edit,Write,WebFetch,WebSearch,Task,Agent,"
        "NotebookEdit,TodoWrite,KillShell,BashOutput,Skill,ToolSearch,"
        "EnterPlanMode,ExitPlanMode")
MAX_STEPS, MAX_ATTEMPTS = 60, 3

os.makedirs(AUDIT, exist_ok=True)

def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)

def llmll(*args):
    return run([LLMLL, *args])

def last_json(text):
    for line in reversed(text.strip().splitlines()):
        line = line.strip()
        if line.startswith(("[", "{")):
            return json.loads(line)
    raise ValueError(f"no JSON in output: {text[-300:]!r}")

def log(step, name, content):
    with open(f"{AUDIT}/step{step:02d}-{name}", "w") as f:
        f.write(content)

def manual_body():
    t = open(MANUAL).read()
    return t.split("\n---\n", 1)[1]

def checkout(step, ptr):
    r = llmll("--json", "checkout", AST, ptr)
    if "already checked out" in r.stdout + r.stderr:
        lock = f"{WORK}/{MODULE}.llmll-lock.json"
        if os.path.exists(lock):
            os.remove(lock)
            r = llmll("--json", "checkout", AST, ptr)
    brief = last_json(r.stdout)
    token = brief.pop("token")
    for k in ("source_hash", "verified_hash", "timestamp", "ttl"):
        brief.pop(k, None)
    log(step, "brief-given.json", json.dumps(brief, indent=1))
    return brief, token

def agent(step, attempt, prompt):
    log(step, f"a{attempt}-prompt.txt", prompt)
    r = run(["claude", "-p", "--disallowedTools", DENY, "--strict-mcp-config"],
            input=prompt, timeout=600)
    reply = r.stdout.strip()
    log(step, f"a{attempt}-reply.txt", reply)
    return reply

def convert(step, attempt, brief, token):
    bp = f"{AUDIT}/step{step:02d}-a{attempt}-b.json"
    tp = f"{AUDIT}/step{step:02d}-a{attempt}-t"
    rp = f"{AUDIT}/step{step:02d}-a{attempt}-reply.txt"
    op = f"{AUDIT}/step{step:02d}-a{attempt}-req.json"
    open(bp, "w").write(json.dumps(brief))
    open(tp, "w").write(token)
    r = run(["python3", f"{BASE}/audit/convert_reply.py", bp, tp, rp, op],
            env={**os.environ})
    if r.returncode != 0:
        return None, None, (r.stdout + r.stderr)[-500:]
    return r.stdout.strip(), op, None

def verify_accept(fname):
    r = llmll("verify", AST)
    out = r.stdout + r.stderr
    safe = "SAFE (liquid-fixpoint)" in out
    m = re.search(r"body-faithful: (.*)", out)
    faithful = [s.strip() for s in m.group(1).split(",")] if m else []
    return safe and fname in faithful, out

def main():
    for step in range(1, MAX_STEPS + 1):
        holes = last_json(llmll("--json", "holes", AST).stdout)
        if not holes:
            print(f"[{MODULE}] complete after {step-1} steps")
            ok, out = verify_accept("")  # final plain verify for the log
            log(step, "final-verify.txt", out)
            return 0
        ptr = holes[0]["pointer"]
        print(f"[{MODULE}] step {step}: {holes[0]['module-path']} ({ptr}), "
              f"{len(holes)} open")
        feedback = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            brief, token = checkout(step, ptr)
            hole_fns = [f["name"] for f in brief["available_functions"]
                        if f["status"] == "hole"]
            fname = hole_fns[0]
            prompt = manual_body() + json.dumps(brief, indent=1)
            if feedback:
                prompt += ("\n\nYour previous reply was rejected by the "
                           "harness:\n" + feedback +
                           "\n\nReply again with a corrected FILL or REFINE.")
            reply = agent(step, attempt, prompt)
            _ = reply  # logged by agent(); conversion reads the logged file
            op, req, err = convert(step, attempt, brief, token)
            if err:
                feedback = "reply could not be parsed/converted: " + err
                continue
            shutil.copy(AST, AST + ".bak")
            r = llmll(op, AST, req)
            if "PatchSuccess" not in r.stdout:
                feedback = (r.stdout + r.stderr)[-500:]
                shutil.copy(AST + ".bak", AST)
                log(step, f"a{attempt}-rejected.txt", feedback)
                continue
            ok, out = verify_accept(fname)
            log(step, f"a{attempt}-verify.txt", out)
            if ok:
                os.remove(AST + ".bak")
                print(f"[{MODULE}]   accepted ({op}, attempt {attempt})")
                break
            shutil.copy(AST + ".bak", AST)
            os.remove(AST + ".bak")
            feedback = ("applied but not accepted (fill must verify "
                        "body-faithful):\n" + out[-500:])
        else:
            print(f"[{MODULE}] FAILED at step {step} ({ptr}) after "
                  f"{MAX_ATTEMPTS} attempts")
            return 1
    print(f"[{MODULE}] hit MAX_STEPS")
    return 1

if __name__ == "__main__":
    sys.exit(main())
