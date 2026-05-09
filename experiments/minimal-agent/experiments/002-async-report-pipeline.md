# Async Report Pipeline with Error Recovery

**Difficulty:** ★★☆
**v0.3 features exercised:** `?delegate-async`, `await`, `Result[t, DelegationError]` pattern matching, `Promise[t]`, `?proof-required`, `def-interface`, `def-invariant`

## Specification

Build a report generation pipeline for a financial dashboard. The system coordinates three agents:

- **Lead Agent** — owns the pipeline, orchestrates the workflow
- **Data Agent (@data-agent)** — fetches and validates raw financial data
- **Chart Agent (@chart-agent)** — renders data into chart images

**The Lead Agent writes the program.** It must:

1. Define a `def-interface DataProvider` with:
   - `fetch-transactions`: takes an account ID (string), returns a list of integers (transaction amounts)
   - `validate-totals`: takes a list of integers, returns a boolean (true if the sum is non-negative)

2. Define a `def-interface ChartRenderer` with:
   - `render-bar-chart`: takes a list of integers (data points) and a title string, returns a string (the rendered chart as text/SVG)

3. Write a `generate-report` function that:
   - Accepts an account ID and a report title
   - Delegates data fetching to `@data-agent` asynchronously via `?delegate-async`
   - While waiting, prepares a report header (a formatted string with the title and account ID)
   - Awaits the data result and pattern-matches on `Success`/`Error`:
     - On `Success`: delegates chart rendering to `@chart-agent` (blocking `?delegate`), with an `on-failure` fallback that returns a text-only summary instead of a chart
     - On `Error`: returns an error report string describing which agent failed and the `DelegationError` variant
   - Returns the complete report as a string

4. Write a `summarize-amounts` function that:
   - Takes a list of integers and returns a pair: `(total, count)`
   - Has a `post` contract: `total` equals the sum of all elements
   - Has a `pre` contract: the list must not be empty
   - Mark the postcondition with `?proof-required` if it involves non-linear reasoning

5. Define a `def-invariant` on the report state:
   - The number of completed reports must never exceed the number of requested reports

6. Include `check` blocks:
   - Summarizing a single-element list returns that element as the total
   - The report header always contains the account ID
   - Awaiting a failed delegation produces an `Error` variant (test the error recovery path)
