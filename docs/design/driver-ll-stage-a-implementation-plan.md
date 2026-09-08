---
name: driver-ll-stage-a-implementation-plan
title: "DRIVER-LL stage A port: implementation plan and running record"
status: "APPLIED TO REVIEW-READY on 2026-09-08 on branch driver-ll-a/stage-a-intake, NOT COMMITTED. Stage A is ported into the sequencer over wasi.http.get and the acceptance cover runs it against a listener the cover starts: 58 passed, 0 failed (52 before). Update this field at commit and again at release."
date: 2026-09-08
author: compiler-engineer
consumers: [compiler-engineer, language-team, experiment-lead, documentation-lead, user]
---

# DRIVER-LL stage A port: implementation plan and running record

Port `stage_A_intake` into
[`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) over
`wasi.http.get` (v0.21.0, `HTTP-GET-1`), the builtin that lifted the STOP this
stage carried since v0.14.83. This is step (3) of the roadmap's G0 PLAN and
the first mechanical stage the sequencer runs.

## What landed

**Registry.** `stage-ported?` claims ten: index 0 joins the nine of 4d. No
other row moves; stage A reads no template, delegates to no agent and
declares the one output it always declared, `00-source/PROVENANCE.json`.

**Sequencer** (271 to 290 statements, still SAFE with no flags). The module
imports `wasi.http` with `(capability get "https://www.rfc-editor.org/")`,
documentation rather than a bound under `CAP-1-REAL`. `Cfg` widens at the
tail a third time with `--rfc-url` and the repeatable `--amend-url`
(`flag-values`), the reference's `--rfc-url` and `action="append"`.
`--rfc-url` joins `missing-flags`, checked last so the three earlier flags
keep their messages. `started-step` routes a ported stage whose `stage-kind`
is `mechanical` to `a-enter` rather than to the agent body. Five arms reuse
the 4d `Loop` payload with the URL list as `rows`, the pins as `acc` and the
current digest as `note`: `AProbe` (`sha256` of the destination, the
reference's `dest.exists()`; present and not `--force` skips the fetch),
`AFetch` (`mkdir 00-source` then `wasi.http.get url dest`, the URL first;
`RErr` records `failed` with the status or transport text), `ADigest`,
`ALines` (`text.count("\n")` as one less than the `split-on` field count) and
`AWrote` (`{"sources": [...]}`, then the digest sweep). The file name is the
URL's last non-empty `/` field or `rfc.txt`. The log lines are the
reference's (`fetching URL`, `pinned NAME: HEX16... (N lines)`).

**Cover.** `main()` starts a `ThreadingHTTPServer` on 127.0.0.1 serving one
directory for the whole run, holding `rfc.txt` with the bytes `prepare()`
writes; `drive()` passes `--rfc-url` on every run (the listener's `rfc.txt`
unless the cell names its own) and repeats `--amend-url`. So the eleven
transition cells that select `A,B,C` now run the real stage: the file
`prepare()` laid down is present and the fetch is skipped, and the one
`--force` cell refetches the same bytes. Six new cells, all `localA` (the rig
never touches stage A and `self_test()` has no stage A block): A1 fetch and
pin, A2 a 404 leaves no file and no pin, A3 a present destination is not
refetched (manifest removed, listener bytes changed), A4 `--force` refetches,
A5 an amending RFC pins second, A6 `--rfc-url` is required.

**Tests.** [`test_driver_ll_a.py`](../../scripts/tests/test_driver_ll_a.py),
five tests, no toolchain. The 4c tier's `PORTED` is ten.

## Divergences from the reference, disclosed

1. **Decoding.** The reference counts lines over `errors="replace"` text and
   cannot fail; `wasi.fs.read` answers `RErr` on bytes that are not UTF-8 and
   the port records `failed`, the divergence the 4b header records for
   `_sources_text`.
2. **A failed fetch is a decision.** The reference tracebacks out of
   `urlopen`; the port records `failed`/`Errored` with the `RErr` text,
   section 9.1 item 1's precedent. The destination is unchanged either way
   (`wasi.http.get` renames only a whole 2xx body).
3. **One missing flag is named, not all.** The reference lists every missing
   flag at once; the port names the first, as since 4a, and `--rfc-url` is
   checked last.
4. **Serialization.** Measured on cell A1: `json-serialize` produces the same
   indent-1 layout as `write_json`'s `json.dumps(indent=1)`; only the trailing
   newline differs. The 4c disclosure about prompt whitespace does not apply
   here.

## Gates at the checkpoint

| Gate | Figure |
|---|---|
| `pytest scripts/tests/` | 200 passed, 20 skipped (was 195; +5 stage A tier) |
| `scripts/driver_ll_cover.py` | 58 passed, 0 failed (was 52), about 9 s wall-clock, first run |
| `llmll build sequencer.llmll` | 13.5 s with the http-client group already in the local Stack cache; the CI cold cost is a first-main-run measurement |
| `llmll verify sequencer.llmll` | SAFE, no flags, as frozen; sidecars unchanged |
| `llmll check sequencer.llmll` | OK, 290 statements, 20 warnings, the same classes as before |
| `stack test` | 1891 examples, 0 failures; no Haskell touched |

## Routing

- **documentation-lead**: the G0 row's step (3) closes; the RESTART record's
  status field still calls stage A a STOP; a CHANGELOG entry and a version.
- **language-team**: `spine.llmll`'s header still says stage A "is NOT here"
  because LLMLL had only `wasi.http.post`; the sentence is true of the spine
  and false of the campaign, and program unification is where it resolves.
- **compiler-engineer**: next per the G0 row are 4f and program unification.
