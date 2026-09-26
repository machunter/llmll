# replay-demo: deterministic event-log replay

A console program that echoes each stdin line to stdout. Every compiled console
program writes a `<name>.event-log.jsonl` recording each input and output;
`llmll replay` rebuilds the program from source, feeds the logged inputs back,
and checks that each output matches. This is the worked example for the
[`replay` section of getting started](../../docs/getting-started.md#replay--deterministic-event-log-replay).
It has no contracts, so `verify` proves nothing.

| File | Contents |
|---|---|
| `replay-demo.llmll` | `echo-step` and a `def-main :mode console` with no `:done?` |

## Run and replay

Reproduced on llmll 0.26.5. Work on a copy: `replay` builds into
`generated/replay-demo/` under the current directory and writes a fresh event
log there too.

```bash
llmll build replay-demo.llmll -o /tmp/replay-demo
cd /tmp/replay-demo && printf 'hello\nworld\nthree\n' | stack exec replay-demo
```

The program echoes the three lines and exits 0 at end of input (no `:done?` is
declared). It leaves `replay-demo.event-log.jsonl` in the working directory:

```
{"type":"header","version":"0.3.1","module":"replay-demo"}
{"type":"event","seq":0,"input":{"kind":"stdin","value":"hello"},"result":{"kind":"stdout","value":"hello"},"captures":[]}
{"type":"event","seq":1,"input":{"kind":"stdin","value":"world"},"result":{"kind":"stdout","value":"world"},"captures":[]}
{"type":"event","seq":2,"input":{"kind":"stdin","value":"three"},"result":{"kind":"stdout","value":"three"},"captures":[]}
```

Replaying that log against the source matches every event and exits 0:

```
$ llmll replay ./replay-demo.llmll replay-demo.event-log.jsonl
...
3/3 events matched
```

Change one recorded output (here `"world"` to `"WORLD"` in `seq 1`) and replay
reports the divergence and exits 1:

```
Event log: 3 events found in tampered.jsonl
Building ./replay-demo.llmll ...
2/3 events matched
  DIVERGE seq 1: expected="WORLD" actual="world"
```

## What `verify` prints

```
$ llmll verify ./replay-demo.llmll
   Running liquid-fixpoint ...
⚠️  ./replay-demo.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```
