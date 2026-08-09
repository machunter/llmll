"""TOOL-LL: the standard in `docs/design/llmll-tooling-campaign.md`, enforced.

A standard no gate reads is a preference. This file is the gate. It needs no
toolchain: everything it checks is a fact about files, which is the tier that
survives a machine with no `llmll` on it.

WHAT IT IS FOR. The campaign's claim is that the repository's CI gates are
DECIDED BY LLMLL PROGRAMS. Three ways that claim rots quietly, each with a check
below:

  * a port ships beside a script that still decides, so nothing is replaced and
    the tool is a demo. The tri-state of campaign §4 is asserted against the
    FILESYSTEM, so `retired` with the script still present reddens;

  * a gap is worked around in silence, so the language never learns anything.
    Campaign §5 gives every gap one of three dispositions and requires a roadmap
    tag on the two that matter; this file checks the shape and the tag;

  * an RFC is written after the fact to match what was built, which is how a
    process becomes paperwork. This cannot be checked mechanically and is not
    claimed to be. What IS checked is that §9 exists and is not empty, because
    the decisions it names are the ones that get made at a keyboard.

WHAT IT DELIBERATELY DOES NOT CHECK. Whether the RFC is any good, whether the
disposition assigned to a gap is the right one, and whether the differential
battery is adequate. Those are review, and a gate that pretended to check them
would be the vacuous-instrument failure this repository keeps relearning.
"""

from __future__ import annotations

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DESIGN = REPO / "docs" / "design"
CAMPAIGN = DESIGN / "llmll-tooling-campaign.md"
TEMPLATE = DESIGN / "TOOL-RFC-TEMPLATE.md"
ROADMAP = REPO / "docs" / "compiler-team-roadmap.md"

STATES = {"blocked", "oracle", "retired"}
DISPOSITIONS = {"BLOCKS", "SHAPES", "COSMETIC"}

# The nine sections campaign §6 requires. Matched on the heading text, so a
# renumbering is caught and a rewording is caught.
#
# "Verification" sits before "Retirement" deliberately and the order is the
# point: retirement DELETES the reference, so §6's whole battery dies with it
# and §7 is what the port still has afterwards. A reader who meets the two in
# the other order learns nothing about why either exists.
SECTIONS = [
    "Subject", "Criteria", "Distribution", "Feasibility", "Gaps",
    "Differential plan", "Verification", "Retirement", "Decisions taken",
]


def _rfcs() -> list[pathlib.Path]:
    return sorted(DESIGN.glob("tool-rfc-*.md"))


def _frontmatter(p: pathlib.Path) -> dict[str, str]:
    text = p.read_text()
    assert text.startswith("---\n"), f"{p.name} has no frontmatter"
    block = text.split("---", 2)[1]
    out = {}
    for line in block.splitlines():
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip('"')
    return out


def _body(p: pathlib.Path) -> str:
    return p.read_text().split("---", 2)[2]


def _table_rows(body: str, heading: str) -> list[list[str]]:
    """The pipe-table rows under a `## N. <heading>` section."""
    m = re.search(rf"^##\s+\d+\.\s+{re.escape(heading)}\s*$", body, re.M)
    if not m:
        return []
    rest = body[m.end():]
    nxt = re.search(r"^##\s+\d+\.", rest, re.M)
    section = rest[:nxt.start()] if nxt else rest
    rows = []
    for line in section.splitlines():
        if line.strip().startswith("|") and not re.match(r"^\s*\|[\s|:-]+\|\s*$", line):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            rows.append(cells)
    return rows[1:] if rows else []          # drop the header row


# ---------------------------------------------------------------------------
# 1. The standard's own files
# ---------------------------------------------------------------------------

def test_the_campaign_and_template_exist():
    """Every check below is about conformance to these two. If they are gone,
    the rest of this file passes vacuously over an empty RFC set."""
    assert CAMPAIGN.exists(), "the campaign doc is gone; the standard has no text"
    assert TEMPLATE.exists(), "the RFC template is gone; there is nothing to copy"


def test_the_template_declares_every_required_section():
    """The template is what authors copy, so a section missing there is a
    section missing from every future RFC."""
    body = TEMPLATE.read_text()
    for i, name in enumerate(SECTIONS, start=1):
        assert re.search(rf"^##\s+{i}\.\s+{re.escape(name)}", body, re.M), \
            f"the template lost section {i}, {name}"


def test_at_least_one_rfc_exists():
    """Guards this file against passing over nothing, which is the failure mode
    every census in this repository has had at least once."""
    assert _rfcs(), "no tool-rfc-*.md exists, so every assertion below is vacuous"


# ---------------------------------------------------------------------------
# 2. Each RFC's shape
# ---------------------------------------------------------------------------

def test_every_rfc_has_the_required_frontmatter():
    for p in _rfcs():
        fm = _frontmatter(p)
        for key in ("name", "title", "status", "date", "author", "tool_state",
                    "subject_script", "port_module"):
            assert key in fm, f"{p.name} frontmatter is missing `{key}`"
        assert fm["tool_state"] in STATES, \
            f"{p.name} has tool_state {fm['tool_state']!r}, not one of {sorted(STATES)}"


def test_every_rfc_has_all_required_sections():
    for p in _rfcs():
        body = _body(p)
        for i, name in enumerate(SECTIONS, start=1):
            assert re.search(rf"^##\s+{i}\.\s+{re.escape(name)}", body, re.M), \
                f"{p.name} is missing section {i}, {name}"


def test_no_rfc_leaves_its_decisions_section_empty():
    """Campaign §6 step 1: the decisions section is where policy calls are
    recorded, and an empty one means either that none were made (rare) or that
    they were made silently (usual). Cannot check which; can check that
    something is claimed.

    The number is DERIVED from SECTIONS rather than written here. It used to be
    hardcoded as 8, and inserting `Verification` ahead of it broke this test
    while leaving the assertion it makes perfectly valid: the check was keyed to
    a position rather than to the thing it was checking."""
    n = SECTIONS.index("Decisions taken") + 1
    for p in _rfcs():
        body = _body(p)
        m = re.search(rf"^##\s+{n}\.\s+Decisions taken\s*$", body, re.M)
        assert m, f"{p.name} has no section {n}"
        tail = body[m.end():]
        nxt = re.search(r"^##\s+\d+\.", tail, re.M)
        section = (tail[:nxt.start()] if nxt else tail).strip()
        assert len(section) > 120, \
            f"{p.name} section {n} is effectively empty ({len(section)} chars)"


# ---------------------------------------------------------------------------
# 3. The tri-state, against the filesystem
# ---------------------------------------------------------------------------

def test_the_tool_state_agrees_with_the_filesystem():
    """Campaign §4. This is the check that keeps a port from being a demo.

    `retired` means the subject script is DELETED. `oracle` and `blocked` both
    mean it is present. A doc that claims retirement while the script still
    decides is exactly the outcome the campaign says would make it a failure.
    """
    for p in _rfcs():
        fm = _frontmatter(p)
        subject = REPO / fm["subject_script"]
        state = fm["tool_state"]
        if state == "retired":
            assert not subject.exists(), (
                f"{p.name} claims `retired` but {fm['subject_script']} is still "
                f"present, so the port has not replaced anything")
        else:
            assert subject.exists(), (
                f"{p.name} is `{state}` and names a subject script that does not "
                f"exist: {fm['subject_script']}")


def test_a_port_that_is_not_blocked_has_a_module_on_disk():
    for p in _rfcs():
        fm = _frontmatter(p)
        if fm["tool_state"] == "blocked":
            continue
        module = REPO / fm["port_module"]
        assert module.exists(), (
            f"{p.name} is `{fm['tool_state']}` and its port_module does not "
            f"exist: {fm['port_module']}")
        assert re.search(r"\(def-main(?![\w?!-])", module.read_text()), \
            f"{fm['port_module']} has no def-main, so it is not a program"


# ---------------------------------------------------------------------------
# 4. The gap discipline
# ---------------------------------------------------------------------------

def test_every_gap_carries_one_of_the_three_dispositions():
    """Campaign §5. The disposition is what turns a gap into a language
    question instead of a workaround."""
    for p in _rfcs():
        rows = _table_rows(_body(p), "Gaps")
        assert rows, f"{p.name} section 5 has no gap table"
        for row in rows:
            assert len(row) >= 3, f"{p.name} gap row is malformed: {row}"
            found = [d for d in DISPOSITIONS if d in row[1]]
            assert len(found) == 1, (
                f"{p.name} gap {row[0]!r} has disposition {row[1]!r}, which is "
                f"not exactly one of {sorted(DISPOSITIONS)}")


def test_every_blocking_or_shaping_gap_cites_a_tag_or_says_it_is_owed():
    """A gap with no roadmap row is the silent workaround the campaign exists to
    prevent. `unfiled` is permitted as an explicit admission and is counted by
    the next test, so the debt is visible rather than absent."""
    for p in _rfcs():
        for row in _table_rows(_body(p), "Gaps"):
            if "COSMETIC" in row[1]:
                continue
            tag = row[2]
            assert tag and tag != "-", (
                f"{p.name} gap {row[0]!r} is {row[1]} and cites no roadmap tag")
            if "unfiled" in tag.lower():
                continue
            named = re.findall(r"[A-Z][A-Z0-9-]{3,}", tag)
            assert named, f"{p.name} gap {row[0]!r} cites {tag!r}, which names no tag"
            for t in named:
                assert t in ROADMAP.read_text(), (
                    f"{p.name} gap {row[0]!r} cites {t}, which is in no roadmap row")


def test_the_owed_gap_filings_are_counted_not_forgotten():
    """`unfiled` is an admission, not an exemption. The campaign's §5 table is
    where the debt lives, so it has to name at least as many owed filings as the
    RFCs do; otherwise a port can quietly accumulate them."""
    owed = set()
    for p in _rfcs():
        for row in _table_rows(_body(p), "Gaps"):
            if "COSMETIC" not in row[1] and "unfiled" in row[2].lower():
                owed.add(row[0][:40])
    campaign = CAMPAIGN.read_text()
    assert campaign.count("not filed") + campaign.count("unfiled") >= len(owed), (
        f"{len(owed)} gap(s) are marked unfiled in RFCs and the campaign's own "
        f"gap census does not carry them: {sorted(owed)}")


# ---------------------------------------------------------------------------
# 5. The campaign and its RFCs agree
# ---------------------------------------------------------------------------

def test_every_ported_gate_named_by_the_campaign_has_an_rfc():
    """The scope table in campaign §2 is the denominator. A gate marked PORTED
    there with no RFC is the paperwork gap in the other direction."""
    campaign = CAMPAIGN.read_text()
    subjects = {_frontmatter(p)["subject_script"] for p in _rfcs()}
    for m in re.finditer(r"\[`([\w.\-/]+)`\]\([^)]*\)\s*\|[^|]*\|\s*\*\*PORTED\*\*",
                         campaign):
        script = "scripts/" + m.group(1) if "/" not in m.group(1) else m.group(1)
        assert script in subjects, (
            f"the campaign marks {m.group(1)} as PORTED and no RFC names it as "
            f"its subject_script")


def test_rfc_numbers_are_unique():
    seen = {}
    for p in _rfcs():
        n = re.match(r"tool-rfc-(\d+)-", p.name)
        assert n, f"{p.name} does not carry a TOOL-RFC number"
        assert n.group(1) not in seen, \
            f"TOOL-RFC-{n.group(1)} is claimed by both {seen.get(n.group(1))} and {p.name}"
        seen[n.group(1)] = p.name
