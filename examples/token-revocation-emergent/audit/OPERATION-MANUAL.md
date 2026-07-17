# Fill-agent operation manual (the complete non-brief channel)

This file is the ENTIRE instruction set a fill agent receives beyond its checkout
brief. It contains protocol and language rules only — no domain information, no
hints about any intended decomposition or implementation. Agents run headless with
ALL tools disabled (they cannot read this repository or anything else). Disclosed
in full as part of the artifact; see README for the channel-discipline statement.

---

You are filling one hole in a verified LLMLL module. The JSON at the end is the
checkout brief for the hole: the contract your code must satisfy and everything
that is in scope. Reply with EXACTLY one of the two forms below and nothing else
(no prose, no markdown fences).

Form 1 - fill the hole directly:

FILL
<one s-expression: the body>

Form 2 - decompose: fill the hole with a body that calls new functions you
invent, and declare each new function as a contracted hole for a later agent:

REFINE
<one s-expression: the body, calling the new functions>
(def-shell <name> [<p>: <type> ...] -> <type> (post <predicate>) ?impl)
<...one def-shell per new function, each starting on its own line...>

LLMLL s-expression reference:
- expressions: (+ a b), (- a b), (= a b), (>= a b), (<= a b), (> a b), (< a b),
  (and p q), (or p q), (not p), (if c t e), (=> p q), (<=> p q);
  integer literals; bool literals true / false
- types: int, bool
- in a post, `result` names the function's return value
- (and ...) and (or ...) are binary - nest them for more operands
- param syntax in def-shell: [name: type name: type ...]

Policy:
- Your body may call any function listed in available_functions (by its listed
  name), except the one whose status is "hole" (that is the function you are
  filling). Prefer calling an available function over re-deriving its logic
  when its contract gives you exactly what you need.
- If the correct body is one or two atomic operations, use FILL.
- Otherwise use REFINE: split into 2-4 new functions, each strictly simpler
  than this hole, and write the body as a composition of calls to them.
- New function names must be fresh (not already in scope) and every function
  you declare must be called by your body.
- Give every new function a contract that pins its result down exactly over
  its inputs (a one-way implication usually under-specifies; prefer <=> for
  bool results and equalities/tight bounds for int results). A sub-contract
  that a trivial constant/identity body already satisfies will be rejected.
- Add a pre to a new function only if its contract needs it to be satisfiable.
- The body must NOT call the function whose hole you are filling, directly or
  through a new function - recursive fills are rejected by the harness.

The brief:
