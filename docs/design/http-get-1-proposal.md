---
name: http-get-1-proposal
title: "HTTP-GET-1: wasi.http.get, a byte-faithful fetch to a file"
status: "Rev 1, SETTLED 2026-09-07 on the one open question, the runtime realization: http-client and http-client-tls compiled into the generated program, emitted only for a program that calls wasi.http.get (option A, section 2). The contract (section 4) was settled earlier by three records and is carried forward unchanged. Ready for compiler-engineer. Section 11 names three measurements the implementation plan owes; none changes the design."
date: 2026-09-07
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# HTTP-GET-1: `wasi.http.get`, a byte-faithful fetch to a file

**One line.** The RFC-SWARM driver's stage A fetches an RFC as bytes, writes them to a file, and
pins the file's SHA-256. That pin is the provenance root of every later stage. LLMLL has no
operation that fetches, so the LLMLL driver's stage A is a filed STOP. This proposal gives the
language `wasi.http.get`, and it settles how the Haskell backend performs the transfer.

---

## 0. Where this sits

The `DRIVER-LL` row of the roadmap (Active Items, G0) sequences `HTTP-GET-1` as step (1), in
parallel with sub-phase 4d, and as step (3), the ship that unblocks stage A. The `HTTP-GET-1` row
(Active Items, G7) carries a **DECIDE** marker. This document is that decision. When the
documentation-lead records it, the marker moves to **PLAN**.

Three records already settle the shape and are not reopened here: the `HTTP-GET-1` roadmap row,
[`driver-ll-open-work.md`](driver-ll-open-work.md) R-11, and
[`effect-response-channel-proposal.md`](effect-response-channel-proposal.md), section
"`wasi.http.get` delivers no payload; it fetches to a file" (Rev 6). What they settled:

- **Signature.** `wasi.http.get : string -> string -> Command`, arguments `(url dest)`.
- **Arms.** `RNone` on a 2xx response. `RErr` carrying the status otherwise.
- **Atomicity.** `dest` is either unchanged or holds the complete 2xx body, never a prefix.
  Realization: write to a temporary in `dest`'s directory, then rename.
- **Why not `RText`.** The reference does `dest.write_bytes(r.read())` and hashes the file
  (`scripts/rfc_to_implementation.py`, `stage_A_intake`). A text round trip is not byte-faithful,
  so the pin would diverge.

What those records left open is the realization, and they left it open on a measurement: adding
`http-client` and `http-client-tls` moved a generated project's dependency closure from 33 to 79
packages. Section 2 re-measures that and decides.

---

## 1. Background: the two drop grounds, re-read

`wasi.http.get` was dropped from CAP-PROC at v0.14.81 on two grounds, either sufficient
(`driver-ll-open-work.md` R-11):

1. The Rev 5 arm table mapped it to `RText`, which cannot reproduce `stage_A_intake`. **Closed
   by Rev 6 of the effect-response proposal**: the operation delivers `RNone` and the payload
   stays in the filesystem.
2. The dependency closure. **This is the ground this proposal decides.** It was a scoping
   decision for CAP-PROC's release date, not a verdict on the design. Section 2 shows the cost is
   paid once and is small.

The campaign then measured the row's original "pick this up only as standalone capability work"
false: stage A STOPPED on it, no RFC source bytes are committed anywhere in this repository, and
`self_test()` carries no stage A block, so the mechanical spine cannot substitute a committed file
(`tools/llmll-driver/spine.llmll`, header comment). The row has been on the campaign's critical
path since v0.14.83.

---

## 2. The realization decision

Two candidates were debated on 2026-09-07. The user chose A.

**A. Runtime-native.** `http-client` and `http-client-tls` compiled into the generated program.
The dependency and the preamble body are emitted **only when the program calls `wasi.http.get`**,
by the same `callsName` test the codegen already uses for the `wasi.http.post` warning.

**B. Sealed `curl`.** The preamble spawns the host's `curl` with a runtime-constructed argument
vector. Zero new packages.

**C. Rejected middle.** `http-client-tls` in the compiler, exposed as a subcommand the preamble
spawns. A built program that cannot run without its compiler on `PATH` is a worse property than
either A or B, and it is still an exec.

### 2.1 Discriminating facts

| Property | A: runtime-native | B: sealed `curl` |
|---|---|---|
| Behaviour pinned by | the LTS resolver, per program | the host's `curl` build (version, protocols, TLS backend) |
| Non-HTTP(S) scheme refused by | the URL parser, by construction (`Network.HTTP.Client.Request`, `InvalidUrlException`) | a `--proto` flag, by discipline |
| Effect label argument | the library does HTTP, the runtime writes one file | an axiom over a pinned argument vector |
| Transfer budget | `System.Timeout` inside the RTS (`Network.HTTP.Client.Core`, `responseTimeout`); `PROC-TIMEOUT-1`'s class, needs a cell | `--max-time`, outside the RTS |
| Ambient binary | none on Linux; on macOS the trust store is loaded by running `security find-certificate -pa` (`System.X509.MacOS` in `crypton-x509-system`) | `curl` everywhere, plus `.curlrc` and proxy state |
| Generated closure | 33 to 75, only for programs that fetch | 33 |
| CI | the Stack cache key must learn the delta (section 10.3) | unchanged |
| `wasi.http.post` | gets a runtime from the same dependency | stays a stub, or needs a second argument-vector axiom |
| Docker runtime image | unchanged | needs `curl`; moot, the runtime stage has no GHC |

### 2.2 The measurement that settled the cost

Measured 2026-09-07 on an Apple silicon machine, `lts-22.43`, GHC 9.6.6 already installed, none of
the new packages prebuilt. The probe is the generated project's exact dependency list
(`emitPackageYaml` in `compiler/src/LLMLL/CodegenHs.hs`) with and without the two packages.

| Quantity | Value |
|---|---|
| Closure, generated list alone | 33 |
| Closure, plus `http-client` and `http-client-tls` | 75 |
| New packages | 41 |
| Cold `stack build` of the delta, wall clock | 40 s |
| CPU | 57 s user, 10 s system |

The roadmap's figure was 79, so 46 new packages; the current resolver gives 41. The new packages
are `crypton`, `tls`, `crypton-connection`, `crypton-x509` and its `store`, `system` and
`validation` siblings, three `asn1-*`, `network`, `network-uri`, `socks`, `pem`, `hourglass`,
`cereal`, `zlib`, `streaming-commons`, `blaze-builder`, `case-insensitive`, `cookie`,
`mime-types`, `iproute`, `unix-time`, `http-types`, `memory`, `basement`, `base64-bytestring`, the
`data-default` family, and small ones. A CI runner has fewer cores, so expect a few minutes, paid
once per cache key. The first CI run on the implementation branch is that measurement.

### 2.3 Grounds for A

1. **Reproducibility.** The transfer behaves the same on every host that runs the same binary.
   Under B one effect is host-dependent by construction, and this project replays runs.
2. **The scheme restriction is a parser property**, not a flag someone must remember.
3. **The soundness argument needs no external axiom.** Section 6.
4. **A second consumer exists already.** `wasi.http.post` is a declared builtin whose body is a
   stderr stub, pinned by three `Spec.hs` tests and exercised by
   `scripts/build-smoke/smoke.llmll`. Its stub was justified as a material expansion for a builtin
   with no call sites. Once `get` pays for the dependency, that justification inverts. G7's
   admission rule is "a request ships when a second consumer appears".
5. **Shape.** A WASI host performs `wasi:http` itself. A is that shape.

### 2.4 What B kept, and what A must earn

- **The budget.** Under B, `curl --max-time` runs outside the RTS. Under A the budget is
  `System.Timeout.timeout`, the mechanism `PROC-TIMEOUT-1` found inert in a built program around
  a blocking foreign call. Socket reads go through the IO manager and are interruptible in the
  non-threaded RTS; `getAddrInfo` is a blocking safe foreign call and is not. Section 11 owes the
  cell. If the resolver case is not covered, clause 4.6 becomes "best effort, disclosed", and the
  sequencer's `liveness.advancing` (`FS-STAT-1`) is the operator's detector, as for every stall.
- **The trust store on macOS.** Disclosed in the harness assumption (section 7), not hidden.

---

## 3. Surface

```lisp
(import wasi.http (capability get "https://www.rfc-editor.org/"))
...
(wasi.http.get "https://www.rfc-editor.org/rfc/rfc4648.txt" "00-source/rfc4648.txt")   ;; : Command
```

**Capability verb.** `get` already parses (`CapHttpGet` in `compiler/src/LLMLL/Syntax.hs`;
`Parser.hs`, `ParserJSON.hs` and `AstEmit.hs` round-trip it). No `LLMLL.md` sentence names it
today. Section 13 files that as drift; this proposal gives the verb its producer.

**Capability check.** `checkWasiCapability` in `compiler/src/LLMLL/TypeCheck.hs` matches the
namespace `wasi.http` and nothing else, so any `wasi.http` import grants `get`, including a `serve`
or `post` grant. That is `CAP-1-REAL`'s existing class, recorded there, not new here.

**JSON-AST.** A `QualIdent` application node, as for every `wasi.*` constructor. `CapabilitySpec`
already accepts `get`. **No schema delta. No schema-version change.**

---

## 4. Semantics: the runtime contract

The contract is realization-independent. The realization notes in brackets name the library
construct that delivers each clause under A.

1. **Scheme.** The runtime rejects a URL that does not begin with `http://` or `https://` before
   any request, publishing `RErr "wasi.http.get: unsupported scheme"`. [A prefix check, before
   `parseRequest`. The parser refuses other schemes as well, with `InvalidUrlException`, so the
   property has two independent guards.]
2. **Redirects.** The runtime follows redirects, bounded at 10, the reference's `urllib` default
   and the library's default (`redirectCount`). The final response's status decides the arm. A
   redirect target that is not HTTP(S) is refused; the runtime then publishes `RErr` for the
   redirect status itself.
3. **Streaming to a temporary.** The runtime creates a temporary file in `dest`'s directory and
   streams the body into it in binary mode. The body is never decoded and never held whole in
   memory. [`withResponse`, `brRead` into a handle from `openBinaryTempFile`.]
4. **Decision rule.** The runtime renames the temporary onto `dest` and publishes `RNone` when
   **both** hold: the body reader reached end of stream without an exception, **and** the final
   status is in 200 to 299. An existing `dest` is replaced atomically.
5. **Every other case.** The runtime removes the temporary and leaves `dest` as it was. It
   publishes `RErr` whose text begins `wasi.http.get: `, followed by `HTTP <code>` for a completed
   non-2xx response, `incomplete transfer (HTTP <code>)` for a body that ended early on a 2xx, or
   the transport failure's text (name resolution, refused connection, certificate rejection,
   budget).
6. **Budget.** 60 seconds for the whole transfer, the reference's constant
   (`urlopen(url, timeout=60)`). The two-argument signature stands. A per-call budget parameter
   ships when a second consumer needs one, which is G7's group rule. [`responseTimeout` set
   explicitly; the library default is 30 s and is not relied on.]
7. **Certificate validation.** The server certificate is validated against the host's system
   store. There is no insecure mode. [`tlsManagerSettings`; validation is on by default and stays
   on. On Linux the store is the system certificate directory, with an environment override the
   library defines; on macOS it is loaded by running `security find-certificate -pa`.]
8. **Method.** The request is a GET. [The runtime sets `method` to `GET` after parsing. This
   matters: `parseRequest` reads a leading method word, so a URL string `"POST https://..."`
   would otherwise become a POST. Clause 1 refuses that string before the parser sees it, and
   the explicit `method` is the second guard.]
9. **Parent directory.** The builtin does not create `dest`'s parent. A missing parent is
   `RErr`. The reference calls `mkdir(parents=True)` first and the port calls `wasi.fs.mkdir`.
10. **Proxies.** The library's default proxy resolution applies (`defaultProxy` reads the
    environment). A proxied transfer is still HTTP. Disclosed in section 7, not checked.

---

## 5. The type-channel rule

A **literal** first argument that does not begin with `http://` or `https://` is a type error at
`check`. This mirrors the `wasi.env.get` literal-name rule at the `EApp` site in `inferExpr`
(`compiler/src/LLMLL/TypeCheck.hs`). Both parameters are `string`, so a reversed literal call
`(wasi.http.get "00-source/rfc.txt" "https://...")` is caught here rather than at run time.
Computed URLs fall to clause 4.1. The rule reaches what a literal can express and no further, the
same boundary `wasi.env.get` states.

---

## 6. Effect label and the soundness argument

`primEffect "wasi.http.get" = Just (Caps {ENetHttp, EFsWrite})`
(`compiler/src/LLMLL/ObligationAssembly.hs`), as a clause **above** the `wasi.` fallthrough to
`Unbounded`, with the negative pin (not `Unbounded`) the module already uses for `wasi.fs.rmdir`
and `wasi.proc.args`. `ENetHttp` exists already for `wasi.http.response` and `wasi.http.post`.
The catalog stays seven-wide.

**Soundness argument, as the lifted-freeze note requires** (roadmap, "What's NOT on this
Roadmap"). `wasi.proc.run` is ⊤ because the program chooses the executable and its arguments, so
the child may do anything (the comment above the `haskell.` and `c.` clauses in `primEffect`).
Here nothing the program supplies selects code to run. The library performs one HTTP(S) transfer
and the runtime writes one file. `Caps {ENetHttp, EFsWrite}` over-approximates that under
may-semantics on a join-semilattice, the same argument `wasi.fs.copy` made for
`Caps {EFsRead, EFsWrite}` ([`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) §8).
The trust assumption is "the pinned library does what its documentation says", the same class as
"`cryptohash-sha256` computes SHA-256". Under B this argument needed an extra axiom over a
constructed argument vector, and a professor question; under A both dissolve.

**Against the four-part arm admissibility rule** (`effect-response-channel-proposal.md`, "An arm
is admissible iff all four hold"): no new arm. `RNone` is nullary, so no fragment widening. The
payload routes through the filesystem, so the file-indirection test is satisfied maximally. No arm
names a capability.

**No `RespFact` row.** `RNone` has no payload and `RErr` carries text. `respFactTable` in
`compiler/src/LLMLL/RespFact.hs` stays at two rows, and the Spec pin on its content is unchanged.

---

## 7. Trust disclosure

One `harness_assumptions` entry, emitted when the program calls `wasi.http.get`, in
`harnessAssumptions` (`compiler/src/LLMLL/TrustReport.hs`), beside the RC-1..RC-4 entries.
Verbatim:

> `wasi.http.get` (HTTP-GET-1): the generated program performs the transfer with `http-client`
> and `http-client-tls`, pinned by the LTS resolver. The server certificate is validated against
> the host's system store; on macOS that store is loaded by running `security find-certificate`.
> Proxy resolution follows the library's environment default. Status classification (2xx),
> redirect following (10) and the 60-second budget are runtime properties with no type-level
> enforcement. Assumed, not proved.

This is the TRUST-AXIOM shape the effect-response proposal's verification table already assigns
to this operation ("`wasi.http.get` status classification: trust; no SMT obligation; a runtime
property requiring disclosure").

The existing entries are conditioned on a console `def-main`. This one is conditioned on a call.
`harnessAssumptions` takes the statement list, so the condition is expressible where it stands;
`callsName` lives in `CodegenHs.hs` today and the engineer decides whether it moves or is
duplicated.

---

## 8. Edge cases and degenerate inputs

Each cell names the input, the behaviour under section 4, the channel that catches it, and the
clause. Cells marked **witness** are the positive firing inputs the guard rule of
`docs/UPDATE-PROTOCOL.md` D2 requires; each is a concrete input, offline unless marked live.

1. **`(wasi.http.get "file:///etc/passwd" dest)`.** Literal: type error (section 5). Computed:
   `RErr unsupported scheme`, no request, `dest` unchanged. Channel: type, then trust (4.1).
   Without 4.1 the `wasi.http` namespace would confer `fs.read` authority.
2. **`(wasi.http.get "POST https://host/x" dest)`.** Literal: type error. Computed: `RErr
   unsupported scheme`. Channel: type, then trust (4.1, 4.8). **Witness** for 4.8: without the
   explicit method, the parser's leading-word rule issues a POST.
3. **404 from a live local server.** `python3 -m http.server` over an empty directory, URL naming
   a missing file. `RErr "wasi.http.get: HTTP 404"`; `dest` absent, or unchanged if it existed.
   Channel: trust (4.5). **Witness** for the status guard.
4. **200 with a truncated body.** A socket script sends `Content-Length: 1000` and closes after
   10 bytes. The body reader raises; `RErr incomplete transfer (HTTP 200)`; `dest` unchanged.
   Channel: trust (4.4). **Witness** for the conjunction in 4.4: a rule that renames on 2xx alone
   pins a partial download, and that pin is the campaign's provenance root.
5. **Connection refused, `http://127.0.0.1:9/x.txt`.** The reference's own offline negative cell
   (`scripts/tests/test_rfc_pipeline_integration.py`, the crash-manifest test). `RErr` with the
   transport text; `dest` absent. Channel: trust (4.5).
6. **Self-signed certificate on a local HTTPS server.** `RErr` with the certificate rejection;
   `dest` unchanged. Channel: trust (4.7). **Witness** that validation is on: a runtime built
   with validation disabled passes this cell wrongly.
7. **Redirect chain 301 → 200.** Final status decides: `RNone`, body written. A redirect to a
   non-HTTP(S) target: `RErr` for the 3xx. Channel: trust (4.2).
8. **Empty 2xx body.** `dest` exists with zero bytes; `RNone`. `RNone` means no payload on the
   channel, and the payload is the file. Channel: spec is explicit (4.4).
9. **Byte-faithfulness against a committed pin (live).** Fetch `rfc4648.txt`; `wasi.fs.sha256`
   on `dest` must equal the pin in `experiments/rfc-swarm/runs/rfc4648/PROVENANCE.json`
   (`84e14418…`). This is the stage A port's acceptance, not a unit-tier gate. Offline twin: serve
   a binary file with `http.server` and compare against `shasum -a 256`. Channel: trust.
10. **Reversed call `(wasi.http.get "00-source/rfc.txt" "https://...")`.** Literal: type error.
    Computed: `RErr unsupported scheme` before any request. Channel: type, then trust.
11. **Server accepts and never writes.** `RErr` after 60 s; `dest` unchanged. Channel: trust
    (4.6). Section 11's cell decides whether a hung resolver is also covered.
12. **`dest`'s parent directory absent.** `RErr` at temporary creation; no request is needed to
    fail, but the order is the engineer's. Channel: trust (4.9).
13. **`dest` exists and the transfer fails.** `dest` untouched. Channel: trust (4.5). Resume
    semantics belong to the program, through `wasi.fs.exists`, as the reference's
    `if not dest.exists()` does.

---

## 9. Verification mapping

| Obligation | Channel | Fragment | Where |
|---|---|---|---|
| `url`, `dest` are `string`; result `Command` | type | `builtinEnv` row | `TypeCheck.hs` |
| A literal URL begins `http://` or `https://` | type | decidable prefix test on a literal, at `check` | the `wasi.env.get` literal rule's site in `inferExpr` |
| `Caps {ENetHttp, EFsWrite}` bounds the operation | trust | catalog entry; may-over-approximation on a join-semilattice | `primEffect`; `effect_summary` is informational (`LLMLL.md` §11, "Effect summary") |
| 2xx classification, atomicity, redirects, budget, certificate validation | trust | runtime property; no SMT obligation; TRUST-AXIOM shape | `harnessAssumptions` |
| Contract channel | none | no QF-LIA obligation: `RNone` nullary, `RErr` text; no `RespFact` row | `LLMLL.md` §5.3.3 / §5.3.5 untouched |

Nothing escapes to Lean. Nothing widens `Σ_auto`.

---

## 10. Affected surface

The seam where the engineer takes over. Not a plan.

### 10.1 Compiler

1. `compiler/src/LLMLL/TypeCheck.hs`: the `builtinEnv` row; the literal-URL rule beside the
   `wasi.env.get` clause in `inferExpr`.
2. `compiler/src/LLMLL/ObligationAssembly.hs`: the `primEffect` clause above the `wasi.`
   fallthrough; the negative pin.
3. `compiler/src/LLMLL/CodegenHs.hs`: a preamble body `wasi_http_get :: String -> String -> IO ()`
   through `llmll_publish_io`, so every exception becomes `RErr` and the temporary is removed on
   the exception path; the `Network.HTTP.Client` and `Network.HTTP.Client.TLS` imports; the two
   `package.yaml` entries. **The body, the imports and the dependencies are all conditional on
   the same test**, `any (callsName "wasi.http.get")` over the statements. An unconditional import
   with a conditional dependency does not compile for the other programs. The dependency comment
   that ends "which is why that operation is not here" goes false and is reworded.
4. `compiler/src/LLMLL/TrustReport.hs`: the conditional entry of section 7.
5. `compiler/src/LLMLL/RespFact.hs`: no change.
6. `docs/llmll-ast.schema.json`: no change.

### 10.2 Tests

7. `compiler/test/Spec.hs`: the `builtinEnv` row; the literal rule, positive and negative (a
   literal `https://` URL passes); `primEffect` not `Unbounded`; the preamble body and imports
   **present** for a program that calls `wasi.http.get` and **absent** for one that does not; the
   `package.yaml` entries, both directions; `respFactTable` unchanged at two rows; the
   `wasi.http.post` stub pins unchanged.
8. A built-program tier in `scripts/tests/`, where the `http.server` rig precedent lives: cells 3,
   4, 5, 6, 7, 8 and the offline twin of 9. All local; none reaches the network. Cell 11 is
   section 11's measurement and lands as a test once its outcome is known.

### 10.3 CI

9. `.github/workflows/version-gate.yml`, step "Cache Stack global + project work". The key
   hashes the compiler's `stack.yaml`, its lock file and its `package.yaml`. The 41 new packages
   are built by a **generated** project, so they ride a key that cannot express whether they are
   there, and on an exact key hit `actions/cache` skips the save. The workflow's own "Cache
   fixpoint binary" step names this trap and solves it with a separate key. Proposed shape: a
   committed pin file under `compiler` listing the generated closure, a `Spec.hs` test that
   `emitPackageYaml`'s list equals it, and that file added to the key's `hashFiles` list. The
   engineer may choose the separate-cache form instead. Either form needs the negative the guard
   discipline requires: delete the cache, confirm the run rebuilds, confirm it then saves.
10. `Dockerfile`: no change. The runtime stage has no GHC and cannot build programs;
    `ca-certificates` is already installed for the day it matters.

### 10.4 Documents (documentation-lead's slot)

11. `LLMLL.md` §13.9: the table row; the delivery-notes paragraph that lists `RNone` deliveries;
    §7: name the `get` verb.
12. Roadmap: `HTTP-GET-1` marker DECIDE → PLAN, citing this file; `CAP-1-REAL`: `get` rides any
    `wasi.http` import, the `PROC-STDIN-1` pattern; the `DRIVER-LL` row's step (3) unchanged.
13. `driver-ll-open-work.md` R-11: status on landing. `effect-response-channel-proposal.md`: the
    internal drift of section 13 item (c).
14. `tools/llmll-driver/spine.llmll`, `sequencer.llmll`, `registry.llmll`: three comments cite
    `HTTP-GET-1` as the reason stage A is a stub. They go false when the **port** of stage A
    lands, which is G0 step (3), a DRIVER-LL sub-phase with its own cover, not this proposal.

### 10.5 Follow-on row, filed here, not folded

15. **`HTTP-POST-1`.** `wasi.http.post` has a stub body and a codegen warning because the
    dependency was judged a material expansion for a builtin with no call sites. This proposal
    pays the dependency for `get`. A runtime for `post` is one more preamble body under the same
    conditional, with its own contract turn (method, body encoding, response arm). It is filed as
    its own row so that `HTTP-GET-1`'s acceptance stays the campaign's. Until it ships, the stub,
    its three `Spec.hs` pins and `smoke.llmll`'s cell stay, and the dependency condition stays
    keyed on `get` alone.

---

## 11. Measurements the implementation plan owes

None changes the design. Each changes one sentence of spec text or one line of CI.

1. **Cold build on the runner.** The first CI run on the branch. Record wall clock for the 41
   packages and confirm the cache saves on the run after.
2. **The budget under the built program's RTS.** Three targets: a server that accepts and never
   writes; a server that writes one byte and stalls; a resolver that never answers. Record which
   of the three `responseTimeout` of 60 s interrupts. If all three: clause 4.6 stands. If the
   resolver case does not: clause 4.6 gains "best effort for name resolution" and the harness
   assumption says so. `PROC-TIMEOUT-1`'s own open item (why `-threaded` does not reach the link
   step) is not folded into this row.
3. **The cache guard's negative.** Section 10.3 item 9, last sentence.

---

## 12. Risks

Severity-ordered.

1. **The conjunction in clause 4.4.** soundness of the provenance root. A realization that
   renames on 2xx alone pins truncated downloads. Cell 4 is a mandatory cover cell. Blocks
   acceptance if absent.
2. **Trusted set grows by 41 pinned packages** for programs that fetch. trust. `tls`, `crypton`
   and the `x509` family are maintained and pinned by the LTS; they are not verified. Neither was
   `curl`. Disclosed. Complicates nothing.
3. **Budget class.** verification-ergonomics. Section 2.4 and section 11 item 2. Complicates one
   sentence.
4. **CI cache key.** scope. Without item 9 of section 10.3 every CI run rebuilds the delta while
   the cache reports healthy. A known trap with an in-repo solution. Complicates one step.
5. **`CAP-1-REAL` widening.** spec-drift / scope. Any `wasi.http` import now grants outbound
   GET. Existing class; only matters when `CAP-1` enforces.
6. **macOS trust-store shell-out.** trust. `security find-certificate -pa` runs once per manager
   on developer machines; never on CI or in Docker. Disclosed. Only matters if someone reads
   "runtime-native" as "no process is ever spawned".
7. **Same-filesystem rename.** trust. Atomic on POSIX for a temporary in `dest`'s directory; a
   network filesystem without atomic rename is out of scope, stated.
8. **`harness_assumptions` undocumented in `LLMLL.md`.** spec-drift. Section 13 item (a).

---

## 13. Drift found while reading, routed

None blocks. All are the documentation-lead's or the engineer's.

- **(a)** `TrustReport.hs` emits `harness_assumptions`; the string occurs zero times in
  `LLMLL.md`. `REPORT-GATE-1`'s class: a report field with no spec sentence. This proposal adds a
  fourth entry to it.
- **(b)** The verb `get` parses in `Parser.hs`, `ParserJSON.hs` and `AstEmit.hs`, and no
  `LLMLL.md` sentence names it. A declared surface with no producer; section 3 supplies the
  producer and §7 of the spec owes the sentence.
- **(c)** `effect-response-channel-proposal.md` carries both readings of this operation: the
  section "`wasi.http.get` does not expose the status code" still says the faithful mapping is
  `RText body`, while the Rev 6 section three paragraphs earlier corrects it to `RNone`. An
  internal contradiction in a settled document.
- **(d)** `CodegenHs.hs`, the dependency comment in `emitPackageYaml`, ends "which is why that
  operation is not here". Goes false on landing.

---

## 14. Revision history

| Rev | Date | What |
|---|---|---|
| 1 | 2026-09-07 | Written after the A-versus-B debate. The contract is carried from three earlier records unchanged. The realization is settled as A by the user on the measured cost (section 2.2) and the five grounds (section 2.3). One professor question from the first turn, on whether a runtime-constructed argument vector bounds an exec, dissolved with the choice of A and is not carried. |
