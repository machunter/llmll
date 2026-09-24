# Contributing to LLMLL

## Build and test

You need GHC and Stack (see [docs/getting-started.md](docs/getting-started.md)). From the repo root:

```bash
make build      # stack build in compiler/
make test       # Haskell tests (stack test) and Python tests (scripts/tests)
make install    # optional: copies llmll into ~/.local/bin
```

`llmll verify` also needs `fixpoint` (liquid-fixpoint) and `z3` on `PATH`. The install recipe is in [docs/getting-started.md](docs/getting-started.md#install-the-solver-verify-only). Run `make help` for the other targets, including the CI verdict gate (`make refute-crux-gate`).

## Where things live

- [LLMLL.md](LLMLL.md): the language specification.
- [docs/getting-started.md](docs/getting-started.md): building, commands, and patterns that work in the current compiler.
- [docs/design/](docs/design/INDEX.md): design proposals and their status.
- [docs/compiler-team-roadmap.md](docs/compiler-team-roadmap.md): open work items.
- [docs/UPDATE-PROTOCOL.md](docs/UPDATE-PROTOCOL.md): which document owns which claim, and what to update when.
- [examples/](examples/README.md): the example index.

## Rules for changes

- A change to the compiler (`compiler/`) lands with tests that exercise it, in `compiler/test` or `scripts/tests`.
- A change to a verification verdict must keep `make refute-crux-gate` passing. If the verdict change is intended, update the example's `EXPECTED_VERDICTS.json` in the same change and say why.
- The version number must agree across `compiler/package.yaml`, `README.md`, `LLMLL.md` and `CHANGELOG.md`. `bash scripts/version_gate.sh` checks this.

## Experimenting with `llmll verify`

`llmll verify` writes a `<file>.verified.json` sidecar next to the file it verifies, and some examples track theirs (for example `examples/banking_ledger/banking.llmll.verified.json`). When you experiment on a tracked example, work on a copy:

```bash
cp -r examples/banking_ledger /tmp/banking_ledger && llmll verify /tmp/banking_ledger/banking.llmll
```

If you did run it in place, restore the sidecars before you commit (`git checkout -- '*.verified.json'`).

## Reporting issues

Open an issue at <https://github.com/machunter/llmll/issues>. For a bug, use the bug report template: it asks for the `llmll version` output, the command you ran, the expected and actual output, and your solver versions.
