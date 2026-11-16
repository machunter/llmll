# Brief: write the vocabulary for RFC 1350 (TFTP), before any contract exists

You are the developer who will specify TFTP for a verifying compiler. Later, other people will write
one contract clause per RFC obligation, using fixed sentence templates over YOUR vocabulary, and a
solver will prove code against those clauses. Your job is only the vocabulary: the sorts, the step
functions and their signatures, the modeling decisions, and what is left out. Do not write contracts
or code.

Your sources are `rfc1350.txt` (618 lines, sha256 39c9534e…) and `rfc1123-s4.2.txt` (lines 2544-2760 of RFC 1123, its §4.2 corrections and requirements for TFTP; sha256 f276196f…), both in your folder. Cite them by file and line number.

## What the target can verify (read this as the tool manual)

- Values: `int` (mathematical, unbounded), `bool`, enums (nullary constructors), sums whose
  constructors are nullary or carry ONE payload (`int`, `bool`, or another such type). No records
  with two fields in one constructor: carry extra fields as separate parameters.
- Refinement aliases: `(type Serial (where [v: int] (and (>= v 0) (< v 4294967296))))`.
- Functions are pure and total: `f [x: T ...] -> R`. A protocol step is a function from the
  relevant inputs (decoded field values, current state facts) to a constructed result.
- Decidable reasoning: linear integer arithmetic (+, -, comparisons, constant multiples), equality,
  and/or/not, constructor tests on enums and sums, and finite maps `map[int|string, int|bool|string]`
  with get/has/set. Byte arrays of fixed length exist.
- Outside: time, clocks and timeouts, concurrency, I/O and the network itself, quantifiers in
  contracts, nonlinear arithmetic, regexes, byte-level parsing whose offsets depend on values read
  from the same packet.
- Practical constraints: discriminate on enum tags passed as parameters rather than matching a
  payload-bearing parameter; compare enums, not strings; do not import an ordering the RFC does not
  define.

## What to write, to `vocabulary.md` in your folder

1. **Sorts** (M-rows). Each type with its constructors or refinement, one line of reason, RFC lines.
2. **Steps.** The protocol functions you would specify, each with its full signature and a one-line
   purpose, plus RFC lines. Say how the RFC's algorithm is divided into steps and why.
3. **Modeling decisions** (D-rows). Every place where the RFC is ambiguous, silent, or allows more
   than one formalization, and you had to choose. For each: the question, the alternatives, your
   choice, RFC lines. Be exhaustive here; this is the part that matters most.
4. **Exclusions** (X-rows). What the vocabulary deliberately does not model, and why.
5. **Open questions** you would ask the RFC author if you could.

## Rules

- Read ONLY `rfc1350.txt` and `rfc1123-s4.2.txt` in your folder. Do not open, list, or search any other file or directory on
  this machine, and do not use the web. The point is an independent reading.
- Write only `vocabulary.md` in your folder.
- When done, reply with: the number of sorts, steps, D-rows, X-rows, and the file path.
