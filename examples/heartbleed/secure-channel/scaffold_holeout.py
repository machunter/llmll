#!/usr/bin/env python3
"""Hole-out a filled LLMLL channel into a fillable scaffold.

For each top-level (def ...) / (def-shell ...), keep the signature + (pre ...) +
(post ...) and replace the BODY (everything after the post form, up to the def's
closing paren) with `?impl`. Converts `def` -> `def-shell` (holes need the
permissive body form). Comments and blank lines between defs are preserved.
`;` line-comments are skipped during scanning (they often contain stray parens).

Usage: scaffold_holeout.py FILLED.llmll SCAFFOLD.llmll
"""
import sys, re


def find_forms(s, i):
    """Yield (start, end) of each balanced top-level () form from i.
    Skips `;`..EOL comments both between and inside forms."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == ';':
            eol = s.find('\n', i)
            i = n if eol < 0 else eol + 1
            continue
        if c == '(':
            depth, j = 0, i
            while j < n:
                cj = s[j]
                if cj == ';':
                    eol = s.find('\n', j)
                    j = n if eol < 0 else eol + 1
                    continue
                if cj == '(':
                    depth += 1
                elif cj == ')':
                    depth -= 1
                    if depth == 0:
                        yield (i, j + 1)
                        i = j + 1
                        break
                j += 1
            else:
                return
        else:
            i += 1


def holeout_def(form):
    """Rewrite one (def ...) form: body -> ?impl, def -> def-shell."""
    head = re.match(r'\(\s*def(-shell)?\b', form)
    if not head:
        return form
    inner = form[head.end():-1]           # strip "(def..." head and trailing ")"
    post_end = None
    for (a, b) in find_forms(inner, 0):
        if re.match(r'\(\s*post\b', inner[a:b]):
            post_end = b
    if post_end is None:
        return form                        # no post -> leave as-is
    return "(def-shell" + inner[:post_end] + "\n  ?impl)"


def main():
    src = open(sys.argv[1]).read()
    out, last = [], 0
    for (a, b) in find_forms(src, 0):
        out.append(src[last:a])            # preserve comments/whitespace before form
        form = src[a:b]
        out.append(holeout_def(form) if re.match(r'\(\s*def(-shell)?\b', form) else form)
        last = b
    out.append(src[last:])
    text = "".join(out)
    open(sys.argv[2], 'w').write(text)
    print(f"wrote {sys.argv[2]} ({text.count('?impl')} holes)")


if __name__ == "__main__":
    main()
