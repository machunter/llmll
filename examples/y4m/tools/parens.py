#!/usr/bin/env python3
"""Paren check before `llmll check`. LLMLL's parse errors for an unbalanced
paren point at the wrong place (netpbm-swarm FRICTION F9), so this script
flags a top-level form that is still open when a line starts with '(' in
column 0, and a form that closes too early. Comments and strings are
skipped."""
import sys

bad = 0
for path in sys.argv[1:]:
    depth, start, instr = 0, None, False
    for ln, line in enumerate(open(path), 1):
        if line.startswith("(") and depth != 0:
            print(f"{path}:{ln}: new form in column 0, but the form from line {start} is at depth {depth}")
            bad = 1
            depth = 0
        i = 0
        while i < len(line):
            c = line[i]
            if instr:
                if c == "\\":
                    i += 1
                elif c == '"':
                    instr = False
            elif c == '"':
                instr = True
            elif c == ";":
                break
            elif c == "(":
                if depth == 0:
                    start = ln
                depth += 1
            elif c == ")":
                depth -= 1
                if depth < 0:
                    print(f"{path}:{ln}: extra ')' (form from line {start})")
                    bad = 1
                    depth = 0
            i += 1
    if depth:
        print(f"{path}: unclosed at end of file, depth {depth} (form from line {start})")
        bad = 1
sys.exit(bad)
