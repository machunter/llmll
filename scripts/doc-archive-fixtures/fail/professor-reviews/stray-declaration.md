---
name: stray-declaration
archive-disposition: shipped
---
Fixture: VIOLATION 4 of 4. A declaration in an archive directory the invariant does not govern.

`professor-reviews/`, `wasm-investigations/` and any future archive category are outside the
shipped-side/dormant-side split, so a disposition declared there is a claim the gate cannot honor.
Silently ignoring it is how an opt-in field quietly stops covering anything: the author believes the
file is gated and it is not. A review's disposition is its proposal's, not its own.
