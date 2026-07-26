# Writing a verified slice of TLS, with AI agents doing the typing

*A short series. We take a real piece of TLS, the layer where two famous security bugs
actually lived, and build it so that (a) a compiler proves the code meets a specification,
and (b) AI agents do the authoring. By the end we have a working slice of the protocol
that structurally cannot ship the bug that broke TLS. This first post is the problem and
the goal; the code starts in Post 2.*

## Post 1 — The bugs that looked like correct code

In February 2014, Apple shipped an emergency patch for CVE-2014-1266. For months, across
hundreds of millions of devices, a TLS handshake could be reported as *successful* for a
server that presented no valid signature: an attacker on the network could impersonate
any HTTPS site. The cause was one duplicated line:

```c
    if ((err = SSLHashSHA1.update(&hashCtx, &signedParams)) != 0)
        goto fail;
        goto fail;        // ← unconditional. always taken.
    if ((err = SSLHashSHA1.final(&hashCtx, &hashOut)) != 0)
        goto fail;
    ...
    err = sslRawVerify(ctx, ctx->peerPubKey, ...);
        // ← the actual signature check. never reached.
    ...
fail:
    return err;
        // ← err == 0, left by the last hash update ⇒ reported as "success"
```

The second `goto fail;` is unconditional. Control jumps to `fail:`, skips `sslRawVerify`,
the one call that checks the signature, and returns the `0` left over from the last
hash update. Zero means success. The routine certifies a signature it never checked.

Four months earlier, the other half of TLS had its own catastrophe. Heartbleed
(CVE-2014-0160) lived in the "heartbeat" responder, the code that answers a keep-alive
ping by echoing back the payload the peer sent:

```c
/* trimmed to the shape that matters */
/* bp: the reply buffer.  pl: the packet we received.
   payload_length: the length the sender CLAIMED,
   never checked against the bytes that actually arrived. */
memcpy(bp, pl, payload_length);
```

`payload_length` is attacker-controlled. Claim 64KB, send one byte, and the reply is that
one byte followed by 64KB of whatever sat next to `pl` in the server's memory: private
keys, session cookies, other users' in-flight requests.

Two bugs, two years, both in the plumbing of the web's encryption. Look at what they have
in common. Neither is exotic. goto-fail is a skipped statement; Heartbleed is a length
one forgot to compare. Both passed code reviews: humans read them top to bottom and saw
nothing. Both passed their test suites. Both compiled without error. Every individual line
is locally plausible. The defect is not in a line; it is in a *path a check does not take*,
or a *bound nobody wrote down*, and those are the mistakes that a reader, a test, and a
type-checker all slide straight past.

## The problem is about to get bigger

These are the highest-stakes programs we have, written by expert teams, and the ordinary
failure mode of code got through anyway. Now put AI agents at the keyboard, writing code
at a scale and speed no team can match. An agent will write a plausible-looking skipped
check exactly the way a human does, faster, and probably more of it. "Looks correct but isn't" is
the failure mode of machine-written code too, and there is going to be a great deal more
of it.

Reviews, tests, and type-checkers share one property: they can all be satisfied by code
that is wrong. That is why goto-fail shipped. If agents are going to write the plumbing,
the thing checking their work has to be able to *refuse* wrong code, not merely fail to
notice it.

## The goal of this series

So here is the question, and we are going to answer it by building the thing:

> Can we write a real piece of TLS, the record layer where goto-fail and Heartbleed
> actually lived, such that a **compiler proves** each function meets a specification,
> and **AI agents do the authoring**, and the goto-fail class of bug simply *cannot* be
> written and accepted?

Two words in that question need defining.

**"Proves"** does not mean "we tested it a lot." The tool we use is a refinement-type
compiler backed by an SMT solver: each function carries a contract (a precondition it may
assume and a postcondition it must establish), and the compiler proves, over *all* inputs,
that the body actually establishes the postcondition. Code that does not is rejected, not
warned about. This is the same technology behind Dafny, F\*, and Liquid Haskell; what is
new here is pointing it at agent-authored code.

**"Agents do the authoring"** is the part that's new here. A verifier on its own is old news.
The combination is the point: agents are fast and will happily write the plausible-but-
wrong body (the skipped check, the missing bound), and the verifier is the backstop that
turns that speed into something you can trust. The agent proposes; the compiler disposes.
Neither is sufficient alone. Together they are a way to write large, correct systems
faster than a human team and with a stronger guarantee than a human team gets.

## The one idea to carry into Post 2

The invariant goto-fail violated is not mysterious. It is a sentence: *report success only
if the signature check actually ran and passed.* You can write that down. It is a
**specification**, and the moment it exists as something a compiler enforces, the bug
stops being a bug you might catch and becomes a bug that cannot exist in accepted code.

That is where Post 2 starts: what it looks like to state that invariant, hand the
implementation to an agent, and watch the compiler reject the version that skips the
check, the goto-fail move, refuted before it can ship. From there the series builds
outward, through non-trivial multi-stage bodies, agents that decompose the problem into
their own sub-contracts, and finally the whole record layer assembled and verified as one
program, ending with a slice of TLS that machines wrote and a compiler proved, standing
exactly where TLS fell.
