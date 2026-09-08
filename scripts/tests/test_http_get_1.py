"""HTTP-GET-1: wasi.http.get's runtime contract, exercised end to end.

WHY THIS EXISTS ALONGSIDE THE HSPEC TESTS. `compiler/test/Spec.hs` (HG-1..HG-20)
pins what the compiler EMITS: the builtinEnv row, the literal-URL rule, the
effect label, the conditional body, imports and dependencies, the harness
entry. None of that observes a transfer. The contract in
docs/design/http-get-1-proposal.md section 4 is a runtime contract (which arm,
whether dest changed, whether a truncated body was renamed) and only a built
program against a real listener can grade it. So these cells BUILD the fixture
in scripts/tests/fixtures/http_get.llmll through LLMLL_BIN and RUN it.

NO CELL REACHES THE NETWORK. Every listener is on 127.0.0.1 and is started by
the test: http.server for 200/404/empty/redirect, a raw socket for the
truncated body and the two hung-server shapes, and an ssl-wrapped http.server
behind a self-signed certificate for the validation witness. The live pin
against rfc-editor.org (proposal cell 9) is the stage A port's acceptance, not
a unit-tier gate.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which has no Haskell toolchain. The binary-bearing invocation is
wired into the spec-roundtrip job beside test_source_encoding.py, which set the
convention.

THE TWO HUNG-SERVER CELLS WAIT THE BUDGET OUT BY DESIGN. They are the
proposal's section 11 measurement 2: `responseTimeout` is System.Timeout, the
mechanism PROC-TIMEOUT-1 found inert in a built program around a blocking
foreign call. A socket read is IO-manager interruptible and is expected to
time out; whether it does is what these two cells decide. The resolver target
(a name that never resolves) cannot be built offline and is measured by hand.
"""

from __future__ import annotations

import hashlib
import os
import shlex
import shutil
import socket
import ssl
import subprocess
import threading
import time
from contextlib import contextmanager
from functools import partial
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "scripts" / "tests" / "fixtures" / "http_get.llmll"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# The fixture's budget is 60 s (proposal clause 4.6). A run that outlives this
# is the negative outcome of measurement 2, and it must FAIL, not hang the suite.
RUN_TIMEOUT_S = 130


# ---------------------------------------------------------------------------
# Building and running the fixture
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def exe(tmp_path_factory) -> Path:
    """Build the fixture once per module. The first build on a machine also
    builds the http-client dependency group (41 packages, measured 40 s cold on
    Apple silicon); later builds hit the Stack snapshot cache."""
    out = tmp_path_factory.mktemp("http-get-build")
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    p = subprocess.run([*llmll, "build", str(FIXTURE), "-o", str(out)],
                       capture_output=True, text=True, cwd=str(REPO_ROOT))
    assert p.returncode == 0, f"the fixture does not build:\n{p.stdout}\n{p.stderr}"
    root = subprocess.run(["stack", "path", "--local-install-root"],
                          capture_output=True, text=True, cwd=str(out))
    assert root.returncode == 0, root.stderr
    binaries = [b for b in (Path(root.stdout.strip()) / "bin").iterdir() if os.access(b, os.X_OK)]
    assert len(binaries) == 1, f"expected one built binary, found {binaries}"
    return binaries[0]


def run(exe: Path, url: str, dest: Path, timeout_s: float = RUN_TIMEOUT_S):
    """Run the fixture: url and dest as argv, three stdin lines (one per turn).
    Returns (arm line, CompletedProcess, elapsed seconds). The arm line is the
    FIRST stdout line beginning `RNone` or `RErr `; `show HttpException` is
    multi-line (it prints the Request record), so the last line is not it, and
    the first run of this file read the last line and failed three cells that
    the program had passed."""
    t0 = time.monotonic()
    p = subprocess.run([str(exe), url, str(dest)], input="a\nb\nc\n",
                       capture_output=True, text=True, cwd=str(dest.parent),
                       timeout=timeout_s)
    elapsed = time.monotonic() - t0
    arms = [l for l in p.stdout.splitlines() if l.startswith("RNone") or l.startswith("RErr ")]
    assert p.returncode == 0, f"exit {p.returncode}; stdout={p.stdout!r} stderr={p.stderr!r}"
    assert len(arms) == 1, f"expected exactly one arm line; stdout={p.stdout!r} stderr={p.stderr!r}"
    return arms[0], p, elapsed


def temporaries_left(directory: Path) -> list[Path]:
    """Clause 4.5: every failure path removes the temporary."""
    return list(directory.glob(".wasi-http-get*"))


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------

class _Quiet(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):  # keep the test log readable
        pass


@contextmanager
def serve_dir(directory: Path, tls_cert: tuple[Path, Path] | None = None):
    srv = ThreadingHTTPServer(("127.0.0.1", 0), partial(_Quiet, directory=str(directory)))
    scheme = "http"
    if tls_cert is not None:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(certfile=str(tls_cert[0]), keyfile=str(tls_cert[1]))
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
        scheme = "https"
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        yield f"{scheme}://127.0.0.1:{srv.server_address[1]}"
    finally:
        srv.shutdown()
        srv.server_close()


class _Redirect(BaseHTTPRequestHandler):
    BODY = b"redirected body\n"

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == "/r":
            self.send_response(301)
            self.send_header("Location", "/target")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/target":
            self.send_response(200)
            self.send_header("Content-Length", str(len(self.BODY)))
            self.end_headers()
            self.wfile.write(self.BODY)
        else:
            self.send_error(404)


@contextmanager
def serve_redirect():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), _Redirect)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        yield f"http://127.0.0.1:{srv.server_address[1]}"
    finally:
        srv.shutdown()
        srv.server_close()


@contextmanager
def raw_listener(script):
    """One-connection raw socket server. `script(conn)` runs after the request
    line and headers have been read; it decides what, if anything, to send."""
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    stop = threading.Event()

    def serve():
        srv.settimeout(0.5)
        while not stop.is_set():
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            with conn:
                conn.settimeout(5)
                buf = b""
                try:
                    while b"\r\n\r\n" not in buf:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        buf += chunk
                except socket.timeout:
                    pass
                script(conn, stop)
            break

    t = threading.Thread(target=serve, daemon=True)
    t.start()
    try:
        yield f"http://127.0.0.1:{srv.getsockname()[1]}"
    finally:
        stop.set()
        srv.close()


def _truncate(conn, _stop):
    # Declares 1000 bytes, delivers 10, closes. The client's body reader must
    # raise before end of stream, and clause 4.4's conjunction must refuse the rename.
    conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n0123456789")


def _hang_silent(_conn, stop):
    # Accepts, reads the request, never writes a byte: the first target of
    # measurement 2. Holds the connection until the test releases it.
    stop.wait(RUN_TIMEOUT_S)


def _hang_after_one_byte(conn, stop):
    # Second target: headers plus one body byte, then silence.
    conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\nx")
    stop.wait(RUN_TIMEOUT_S)


# ---------------------------------------------------------------------------
# Cells (numbering follows docs/design/http-get-1-proposal.md section 8)
# ---------------------------------------------------------------------------

def test_refused_connection_is_rerr_and_dest_is_absent(exe, tmp_path):
    """Proposal cell 5, and the HttpException witness: llmll_publish_io catches
    IOException only, so without the body's own `try` a refused connection would
    be an uncaught exception. Exit 0 is asserted inside run()."""
    dest = tmp_path / "out.txt"
    arm, _p, _ = run(exe, f"http://127.0.0.1:{free_port()}/x.txt", dest)
    assert arm.startswith("RErr wasi.http.get: "), arm
    assert not dest.exists()
    assert temporaries_left(tmp_path) == []


def test_404_is_rerr_naming_the_status(exe, tmp_path):
    """Proposal cell 3: the status guard's positive witness."""
    served = tmp_path / "served"; served.mkdir()
    dest = tmp_path / "out.txt"
    with serve_dir(served) as base:
        arm, _p, _ = run(exe, f"{base}/missing.txt", dest)
    assert arm.startswith("RErr wasi.http.get: HTTP 404"), arm
    assert not dest.exists()
    assert temporaries_left(tmp_path) == []


def test_200_is_rnone_and_the_bytes_are_faithful(exe, tmp_path):
    """Proposal cell 9's offline twin: 70 KB of random bytes, larger than one
    read buffer, compared byte for byte and by digest. A text round trip
    would not survive this input; that is the whole reason the operation
    writes a file instead of delivering RText."""
    served = tmp_path / "served"; served.mkdir()
    payload = os.urandom(70_000)
    (served / "blob.bin").write_bytes(payload)
    dest = tmp_path / "out.bin"
    with serve_dir(served) as base:
        arm, _p, _ = run(exe, f"{base}/blob.bin", dest)
    assert arm == "RNone", arm
    assert dest.read_bytes() == payload
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == hashlib.sha256(payload).hexdigest()
    assert temporaries_left(tmp_path) == []


def test_empty_200_body_yields_an_empty_dest(exe, tmp_path):
    """Proposal cell 8: RNone means no payload on the channel; the payload is
    the (empty) file."""
    served = tmp_path / "served"; served.mkdir()
    (served / "empty.txt").write_bytes(b"")
    dest = tmp_path / "out.txt"
    with serve_dir(served) as base:
        arm, _p, _ = run(exe, f"{base}/empty.txt", dest)
    assert arm == "RNone", arm
    assert dest.exists() and dest.stat().st_size == 0


def test_truncated_200_is_refused_and_nothing_is_renamed(exe, tmp_path):
    """Proposal cell 4, the conjunction witness. A runtime that renames on 2xx
    alone would leave a 10-byte dest here that wasi.fs.sha256 would then pin as
    the provenance root."""
    dest = tmp_path / "out.txt"
    with raw_listener(_truncate) as base:
        arm, _p, _ = run(exe, f"{base}/x.txt", dest)
    assert arm.startswith("RErr wasi.http.get: incomplete transfer (HTTP 200)"), arm
    assert not dest.exists()
    assert temporaries_left(tmp_path) == []


def test_redirect_chain_lands_on_the_final_status(exe, tmp_path):
    """Proposal cell 7: 301 then 200; the final status decides."""
    dest = tmp_path / "out.txt"
    with serve_redirect() as base:
        arm, _p, _ = run(exe, f"{base}/r", dest)
    assert arm == "RNone", arm
    assert dest.read_bytes() == _Redirect.BODY


def test_existing_dest_is_untouched_by_a_failure(exe, tmp_path):
    """Proposal cell 13, clause 4.5: dest is left as it was."""
    served = tmp_path / "served"; served.mkdir()
    dest = tmp_path / "out.txt"
    dest.write_bytes(b"previous contents\n")
    with serve_dir(served) as base:
        arm, _p, _ = run(exe, f"{base}/missing.txt", dest)
    assert arm.startswith("RErr wasi.http.get: HTTP 404"), arm
    assert dest.read_bytes() == b"previous contents\n"


@pytest.mark.skipif(shutil.which("openssl") is None, reason="openssl is needed to mint the self-signed certificate")
def test_self_signed_certificate_is_refused(exe, tmp_path):
    """Proposal cell 6, the validation-on witness: a runtime built with
    validation disabled would fetch this file and pass every other cell."""
    cert, key = tmp_path / "cert.pem", tmp_path / "key.pem"
    p = subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-keyout", str(key), "-out", str(cert), "-days", "1",
                        "-subj", "/CN=127.0.0.1"], capture_output=True, text=True)
    assert p.returncode == 0, p.stderr
    served = tmp_path / "served"; served.mkdir()
    (served / "x.txt").write_bytes(b"should never arrive\n")
    dest = tmp_path / "out.txt"
    with serve_dir(served, tls_cert=(cert, key)) as base:
        arm, _p, _ = run(exe, f"{base}/x.txt", dest)
    assert arm.startswith("RErr wasi.http.get: "), arm
    assert not dest.exists()
    assert temporaries_left(tmp_path) == []


# MEASURED 2026-09-07, two runs of the built program. Run one carried
# http-client's responseTimeout ALONE (60 s): both hung-server shapes held the
# process past 130 s and nothing reached stdout, so the library's budget covered
# neither shape here. Run two added a System.Timeout wrapper around the whole
# transfer in the preamble: both shapes answered RErr at about 60 s. So the
# budget is real, clause 4.6 stands as written, and the wrapper is the layer
# that delivers it. This is also the discriminator PROC-TIMEOUT-1 leaves
# implicit: a blocked socket read is IO-manager interruptible in the generated
# program's RTS, while waitForProcess (that row's site) is a blocking foreign
# call that is not.
#
# 60 s budget plus a margin. A firing budget answers in about 60 s; a hang is
# cut here rather than at RUN_TIMEOUT_S so a regression costs the suite 150 s,
# not 260. The two cells cost about 120 s when they pass; that is the price of
# measuring the contract's one time-valued clause rather than pinning its text.
BUDGET_RUN_TIMEOUT_S = 75


def test_hung_server_that_never_writes_hits_the_budget(exe, tmp_path):
    """Proposal cell 11 and section 11 measurement 2, target one: a listener
    that accepts, reads the request and never writes a byte. The header phase,
    which responseTimeout is documented to cover."""
    dest = tmp_path / "out.txt"
    with raw_listener(_hang_silent) as base:
        arm, _p, elapsed = run(exe, f"{base}/x.txt", dest, timeout_s=BUDGET_RUN_TIMEOUT_S)
    assert arm.startswith("RErr wasi.http.get: "), arm
    assert 50 <= elapsed <= 75, f"budget fired at {elapsed:.1f}s; the contract says 60"
    assert not dest.exists()
    assert temporaries_left(tmp_path) == []


def test_hung_server_after_one_byte_hits_the_budget(exe, tmp_path):
    """Measurement 2, target two: headers and one body byte, then silence. The
    stall is inside the body loop, which only the System.Timeout layer covers,
    and the temporary must still go."""
    dest = tmp_path / "out.txt"
    with raw_listener(_hang_after_one_byte) as base:
        arm, _p, elapsed = run(exe, f"{base}/x.txt", dest, timeout_s=BUDGET_RUN_TIMEOUT_S)
    assert arm.startswith("RErr wasi.http.get: "), arm
    assert 50 <= elapsed <= 75, f"budget fired at {elapsed:.1f}s; the contract says 60"
    assert not dest.exists()
    assert temporaries_left(tmp_path) == []
