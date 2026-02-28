"""Replay and minimise crash inputs found by fuzz().

When ``fuzz()`` detects a crash it saves each unique crashing input to
``<crash_dir>/crash_NNNN.bin``.  This example shows three common
post-crash workflows:

1. **List** — enumerate every crash file in a crash directory.
2. **Replay** — feed one file back through the target to reproduce the error.
3. **Minimise** — use ``minimize_bytes`` to reduce the crashing input to its
   smallest form before filing a bug report.

Usage (after a fuzz run that produced crashes):

    pixi run example-replay

The example uses the same toy ``crasher`` target from ``test_runner.mojo``
so it works without any external harness.
"""

from mozz import fuzz, FuzzConfig, Corpus, minimize_bytes


# ── Toy target (same as in test_runner.mojo) ──────────────────────────────────

fn crasher(data: List[UInt8]) raises:
    """Crashes when both 0x00 and 0xFF appear anywhere in the input."""
    var has_zero = False
    var has_ff = False
    for i in range(len(data)):
        if data[i] == 0x00:
            has_zero = True
        if data[i] == 0xFF:
            has_ff = True
    if has_zero and has_ff:
        raise Error("panic: found both 0x00 and 0xFF")


fn is_crash(data: List[UInt8]) raises -> Bool:
    """Return True if ``data`` triggers the crash in ``crasher``."""
    try:
        crasher(data)
        return False
    except e:
        return String(e).find("panic") >= 0


# ── Helpers ───────────────────────────────────────────────────────────────────

fn _hex(data: List[UInt8]) -> String:
    """Encode ``data`` as lowercase hex."""
    comptime HEX = "0123456789abcdef"
    var out = String(capacity=len(data) * 2)
    for i in range(len(data)):
        out += HEX[Int(data[i] >> 4)]
        out += HEX[Int(data[i] & 0xF)]
    return out


# ── Main ─────────────────────────────────────────────────────────────────────

fn main() raises:
    var crash_dir = ".mozz_crashes/replay_demo"

    # ── Step 0: produce a few crashes so the demo has something to replay ──────
    print("── step 0: running fuzz() to generate crash inputs ─────────────────")
    var seeds = List[List[UInt8]]()
    var seed_bytes: List[UInt8] = [0x00, 0xFF]
    seeds.append(seed_bytes^)
    # fuzz() raises when it finds crashes — that's expected; we catch it here
    # so the replay workflow can proceed.
    try:
        fuzz(
            crasher,
            FuzzConfig(
                max_runs=2_000,
                seed=42,
                verbose=False,
                crash_dir=crash_dir,
            ),
            seeds,
        )
    except e:
        print(" ", String(e))

    # ── Step 1: list crash files ───────────────────────────────────────────────
    print("\n── step 1: list crash files in '" + crash_dir + "' ──────────────")
    var paths: List[String]
    try:
        paths = Corpus.list_crashes(crash_dir)
    except e:
        print("  no crashes found:", String(e))
        return

    print("  found", len(paths), "unique crash input(s)")
    var show = min(5, len(paths))
    for i in range(show):
        print("  ", paths[i])
    if len(paths) > show:
        print("  ... and", len(paths) - show, "more")

    if len(paths) == 0:
        print("  nothing to replay")
        return

    # ── Step 2: replay the first crash ────────────────────────────────────────
    print("\n── step 2: replay '" + paths[0] + "' ────────────────────────────")
    var crash_input = Corpus.load_crash(paths[0])
    print("  input bytes (" + String(len(crash_input)) + "):", _hex(crash_input))
    try:
        crasher(crash_input)
        print("  ⚠ target did NOT crash on replay (input may be stale)")
    except e:
        print("  ✓ crash reproduced:", String(e))

    # ── Step 3: minimize the crash input ──────────────────────────────────────
    print("\n── step 3: minimize the crash input ─────────────────────────────")
    print("  original:", len(crash_input), "bytes:", _hex(crash_input))
    var minimal = minimize_bytes(crash_input, is_crash)
    print("  minimal: ", len(minimal), "bytes:", _hex(minimal))
    print(
        "  reduced by",
        len(crash_input) - len(minimal),
        "bytes (" + String((len(crash_input) - len(minimal)) * 100
            // max(1, len(crash_input))) + "% smaller)",
    )
