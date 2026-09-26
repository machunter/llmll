# tools: what is proved

The tools under `tools/` are written in LLMLL, but the checkout holds no record that anything
in them was proved. `.gitignore` excludes `.verified.json` sidecars (three canonical example
sidecars are exempt), and CI regenerates them on every run. This page states what those runs
prove and what they do not. [`scripts/tools_verification.py`](../scripts/tools_verification.py)
regenerates the evidence on a copy of the tree and prints the per-file table.

```bash
python3 scripts/tools_verification.py            # uses the stack-built compiler
python3 scripts/tools_verification.py --llmll /path/to/llmll
```

Running `llmll verify FILE --trust-report` on a file that has no sidecar yet reports
`verified: 0` for every function. `--trust-report` renders the sidecar and does not run the
solver. Run plain `llmll verify FILE` first, as the script does.

## How the tools are built

Each tool is a program with no contracts (file I/O, parsing, subprocesses) that imports one
small contracted module and hands it the decision: pass or fail, and the exit status. Only the
contracted module is proved. Each tool's program starts with `(import adjudicate)`, and the
driver's `sequencer.llmll` imports its contracted modules directly or through `wave.llmll`
and `spine.llmll`.

## What is proved (llmll 0.26.5)

Counts are the file's own functions; a function a file imports is counted where it is defined.

| Tool | Proved core | Proved functions | What the contracts state |
|---|---|---|---|
| refute-crux, version-gate, doc-claims | `adjudicate.llmll` | `status-of` (1 each) | the exit status is in 0 to 255: a negative count gives 1, a count over 255 gives 255, anything else passes through |
| doc-path-lint | `adjudicate.llmll` | `reports?`, `tally`, `status-of` | a path is reported exactly when none of its six exemptions holds; the finding count rises by one per report and is never negative; strict mode exits 1 exactly when a strict run has findings |
| doc-archive | `adjudicate.llmll` | `side-of` | Shipped and Superseded route to the spec directory, Dropped and Deferred to the dormant directory, an unknown disposition to neither |
| build-smoke | `adjudicate.llmll` | `fsenc-verdict`, `status-of` | the encoding verdict is 0 unless the marker, digest, faithfulness and both binary comparisons hold; the stage passes with exit 0 and fails with exit 1 |
| llmll-driver | 12 modules | 31 | the driver spec's decision rules, each clause cited with `:source`; see below |

The driver's proved modules and what each one states are listed in
[`llmll-driver/README.md`](llmll-driver/README.md#what-is-proved). Per module: `shape` 5,
`oracle` 4, `spine` 9 (the stage E, J, L and G2 pins and outcomes), `fill` 3, `gate` 2,
`validate` 2, and one each in `liveness`, `report`, `skip`, `stage`, `token` and `sequencer`
(`exit-code`). `twin-skip-reassociated.llmll` also verifies (1 function); it is a correct twin of
`skip`, reassociated, kept to show the contract admits more than one phrasing, and the driver does
not import it.

## What is not proved

- **Everything outside the cores.** File reading, parsing, subprocess calls and orchestration
  carry no contracts. The programs print `nothing proved`. Functions with no contract:
  `sequencer` 357, `buildsmoke` 179, `wave` 109, `refutecrux` 90, `docclaims` 90, `pathlint` 62,
  `docarchive` 56, `spine` 54, `versiongate` 50, `registry` 32, `manifest` 13, `common` 10,
  `shell` 6.
- **The cores' preconditions at the tools' call sites.** A core is proved assuming its `pre`
  holds. The programs that call the cores are `def-shell` code outside the fragment, so their
  calls produce no call-site obligation, and nothing proves the arguments meet the `pre`.
  Measured on a copy: changing `pathlint.llmll` to call `tally` with -5 (its `pre` is
  `seen >= 0`) still verifies SAFE with exit 0. The `pre` survives as a runtime assertion: a
  two-module program that makes the same kind of call builds, and at run time stops with
  `pre-condition failed` and exit 1. A violated precondition therefore stops the tool; it is
  not ruled out in advance.
- **`drv-status` in `sequencer.llmll`** is asserted, not proved. It carries a contract (the
  exit status is in 0 to 255), but its body matches on `(second s)`, a pair component of
  datatype sort, and that falls outside the fragment (`body-outside-fragment`, refused by
  `match`). Measured on minimal files: a `match` on a `Ctl` variable is proved, and `second` of
  an `(int, int)` pair is proved; only the combination falls back. The tool cannot work around
  it: `:status` receives the whole `(Run, Ctl)` state, and a `def` cannot call a helper defined
  in the same file. Proving it needs compiler support for datatype-sorted pair components.
- **`fixtures/wave-roots.llmll`** is a holed fixture; its 2 contracts are assumed by design.

A `SAFE` headline on a program with no contracts means only that no contradiction was found.

## What the proofs mean

The proofs cover each tool's decision: given the counts and flags the tool gathered, it reaches
the right verdict and exit status. They do not cover whether the gathered values are right. That
side is tested, not proved, by the cover scripts in `scripts/`: differential covers against the
shell reference for build-smoke and version-gate (`build_smoke_cover.py`, `version_gate_cover.py`),
mutation covers for doc-archive, doc-claims, doc-path-lint and refute-crux, and a transition cover
over the built driver (`driver_ll_cover.py`).

## What CI checks

- `.github/workflows/version-gate.yml` verifies each `adjudicate.llmll` before it builds the
  tool that imports it, and fails the job if the core does not verify.
- The same workflow requires each of six mutants of those cores (`crux-*.llmll` in
  `build-smoke`, `doc-archive`, `doc-claims`, `doc-path-lint`, `refute-crux`, `version-gate`) to
  be refuted, and reads the solver's own line to confirm it.
- The refute-crux gate runs the driver's 38 frozen verdicts in
  [`llmll-driver/EXPECTED_VERDICTS.json`](llmll-driver/EXPECTED_VERDICTS.json): its modules
  are SAFE as recorded (17 files, including the programs that prove nothing and the correct
  twin), and its 21 mutants fail as recorded: 20 are
  refuted under `--strict-verified-core`, and `crux-shell-undeclared-authority` is rejected at
  the capability check.
