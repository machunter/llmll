# Cascading refinement — decomposing a hole into a tree, top-down

`patch` fills a leaf. **`refine`** decomposes a hole: it installs a hole's body **and
spawns new contracted sub-holes the body calls**, atomically. No agent is handed the whole
problem — one agent takes a hole, refines it into a couple of *narrower* sub-holes with
their own contracts, and each of those becomes a hole for the *next* agent. The
decomposition tree emerges from the work; it is not drawn up front.

Every intermediate state verifies `SAFE` — each function proven against the current
frontier's *contracts* via assume-guarantee — and the finished tree verifies as one program
with zero holes.

## The tree — a TLS record-delivery gate

Deliver a plaintext byte only if the record is **authenticated** and **ordered**. That
splits, and splits again, into four leaf checks:

```
admit-byte (L1)              true iff authenticated AND ordered
├── authenticated (L2)       iff MAC matches AND handshake connected
│   ├── mac-matches (L3)      iff computed = expected
│   └── handshake-up (L3)     iff hs_state = CONNECTED (2)
└── ordered (L2)             iff sequence fresh AND length sound
    ├── seq-fresh (L3)        iff seq > last
    └── length-sound (L3)     iff claimed ≤ received      ← the Heartbleed bound, reused
```

Every node returns `bool`, and its contract is an exact biconditional — `(<=> result C)`,
"the result is true exactly when condition `C` holds". Internal nodes are the `and` of their
two child calls; leaves are the bare comparison. No contract is a passthrough the vacuity
gate would reject.

## The program

`base.llmll` (→ `base.ast.json`, what the ops run on) is a single hole with the L1 contract:

```lisp
(def-shell admit-byte
    [computed: int expected: int hs_state: int seq: int last: int claimed: int received: int] -> bool
  (post (<=> result (and (and (= computed expected) (= hs_state 2))
                         (and (> seq last) (<= claimed received)))))
  ?body)
```

The contract reads as the specification it is: *deliver exactly when the MAC matched, the
handshake reached CONNECTED, the sequence was fresh, and the length was sound.* Each leaf is
the same shape one level down — `length-sound`'s whole contract is `(<=> result (<= claimed received))`.

## The cascade — one agent per hole, applied in sequence

Each step is a different agent taking **one** hole, given only its checkout brief (its
contract, return type, and in-scope names — never the rest of the tree). Re-checkout
immediately before each step: the module uses a whole-file compare-and-swap, so any write
makes an earlier token stale.

Each `NN-*.json` request has a readable `NN-*.sexp` companion showing the same fill body and
spawned contracts in LLMLL surface syntax — read those to follow the cascade without parsing JSON.

```bash
# one step, in full — the shape every step follows:
TOKEN=$(llmll checkout base.ast.json /statements/0/body --json | jq -r .token)
sed "s/<TOKEN-from-checkout>/$TOKEN/" 01-refine-admit.json > /tmp/step.json
llmll refine base.ast.json /tmp/step.json      # apply
llmll verify base.ast.json                     # every state is SAFE
llmll holes  base.ast.json                     # watch the frontier move
```

Running all seven steps (`refine` for the internal nodes, `patch` for the leaves), the open
frontier **fans out** as the tree grows, then **contracts** as the leaves fill:

| # | step | checkout | apply | verify | open holes |
|---|---|---|---|---|---|
| — | start | — | — | `SAFE` | **1** (`admit-byte`) |
| 1 | `refine admit-byte` → spawn `authenticated`, `ordered` | `/statements/0/body` | `PatchSuccess` | `SAFE` | **2** |
| 2 | `refine authenticated` → spawn `mac-matches`, `handshake-up` | `/statements/1/body` | `PatchSuccess` | `SAFE` | **3** |
| 3 | `refine ordered` → spawn `seq-fresh`, `length-sound` | `/statements/2/body` | `PatchSuccess` | `SAFE` | **4** |
| 4 | `patch` fill `mac-matches` | `/statements/3/body` | `PatchSuccess` | `SAFE` | **3** |
| 5 | `patch` fill `handshake-up` | `/statements/4/body` | `PatchSuccess` | `SAFE` | **2** |
| 6 | `patch` fill `seq-fresh` | `/statements/5/body` | `PatchSuccess` | `SAFE` | **1** |
| 7 | `patch` fill `length-sound` | `/statements/6/body` | `PatchSuccess` | `SAFE` | **0** |

Final: `llmll verify` → `SAFE`, `llmll holes` → **0 holes**, seven functions —
`admit-byte`, `authenticated`, `ordered`, `mac-matches`, `handshake-up`, `seq-fresh`,
`length-sound` — verified as one program.

At step 1, `admit-byte` verifies **modulo** `authenticated` and `ordered`'s contracts before
either of those has a body; the guarantee is real at every level, and the leaves only have
to meet the contracts their parents already relied on.

## The two gates on an invented decomposition

An agent invents both a sub-contract *and* its filling, so two rejections keep a
decomposition from cheating. Each operates on the base hole:

```bash
llmll refine base.ast.json 08-refine-vacuous.json
#  → refine gate: spawned sub-contract 'authenticated' is vacuous — a trivial
#    (identity/constant) body already satisfies it … strengthen the contract
```
`08` weakens `authenticated`'s contract from the biconditional to a one-way implication
(`(=> (and (= computed expected) (= hs_state 2)) result)`) — which a constant `true` body
already satisfies. The CDP vacuity gate refuses it: you cannot make progress by splitting a
hard goal into an empty one.

```bash
llmll refine base.ast.json 09-refine-orphan.json
#  → refine: spawned def 'audit-log' is not referenced by the fill body
```
`09` adds a function the fill body never calls. The scope predicate refuses it: a `refine`
may only introduce sub-functions the decomposition actually uses, so the operation cannot
become a way to write arbitrary code into the module.

## Parallelism

The steps above are serialized because they write one module file, guarded by a whole-file
compare-and-swap (once agent A's refine lands, agent B's outstanding token goes stale and B
re-checks-out). The agents still *reason* independently — each sees only its own hole's
brief. For agents that write **at the same time**, give each subtree its own module and
assemble through the cross-module contract system; that is how the 163-function flagship in
[`../heartbleed/secure-channel/`](../heartbleed/secure-channel/) was built, with agents
owning modules in parallel.

*Every command here was run against the built `llmll` (v0.14.61). The request `token`
fields read `<TOKEN-from-checkout>`; substitute the token `checkout` returns — a real token
witnesses the file's content hash and goes stale if the file changed under you.*
