"""Mozz — pure-Mojo fuzzing and property-based testing library.

Zero external dependencies. No libFuzzer, no C ABI, no compiler flags.
Write a harness, call ``fuzz()``.

## What is fuzzing?

Fuzzing is the practice of automatically generating a large number of random or
semi-random inputs and feeding them to a function, looking for crashes,
assertion failures, or incorrect behavior. The key distinction from hand-written
unit tests is that fuzzing explores the input space programmatically rather than
relying on cases the developer thought to cover. A fuzz target is a single
function that accepts bytes and exercises the code under test. If it panics or
violates an assertion, the triggering input is saved to disk for inspection and
added to the regression suite.

Fuzzing is most valuable for parsers, codecs, and protocol implementations,
where the valid input space is large, malformed inputs from untrusted sources
are common, and a single mishandled byte can produce a security vulnerability.
Projects like OpenSSL, Chrome, and curl have found thousands of critical bugs
through fuzzing that years of manual code review and conventional testing missed.

## What is property-based testing?

Property-based testing is a generalization of unit testing where you describe an
invariant that must hold across all inputs — for example, "encoding then decoding
any value returns the original" — and the library generates hundreds or thousands
of random inputs to try to falsify it. Instead of writing assertions for a
handful of chosen cases, you write the invariant once and let the library find
inputs that break it. When a counterexample is found, the input is automatically
shrunk to the simplest possible case that still triggers the failure, making the
root cause easier to isolate and fix. Well-known property-based testing libraries
include Haskell's QuickCheck, Python's Hypothesis, and Rust's proptest.

The combination of fuzzing and property-based testing covers different failure
modes: fuzzing finds crashes caused by inputs the developer never considered,
while property tests find logic errors where the function produces a wrong result
rather than crashing.

## Key properties

- **Zero deps**: no libFuzzer, no C ABI, no FFI surface whatsoever.
- **Three levels**: raw byte fuzzing, typed property tests, custom generators.
- **Deterministic**: every run is seeded; crashing inputs are saved to disk for replay.
- **Shrinking**: failing inputs are minimized automatically via delta-debugging.

## Three levels of API

### Level 1 — Raw byte fuzzing

```mojo
from mozz import fuzz, FuzzConfig

fn target(data: List[UInt8]) raises:
    _ = MyParser.parse(data)  # raises = normal rejection; panic = crash saved to disk

fn main() raises:
    fuzz(
        target,
        FuzzConfig(
            max_runs=100_000,
            seed=42,
            verbose=True,            # progress lines + final report to stdout
            report_file="fuzz.log",  # also write final report to file
        ),
    )
```

Output:

```
[mozz] crashes: 0 | runs: 100000 | corpus: 14 | rejects: 6183 | 100%

[mozz] ── final report ──────────────────────────────
[mozz]   seed:           42
[mozz]   runs:           100000
[mozz]   ok:             93817
[mozz]   rejections:     6183
[mozz]   corpus:         14 seeds
[mozz]   crashes (hits): 0
[mozz]   crashes (uniq): 0
[mozz] ─────────────────────────────────────────────
```

### Level 2 — Property-based testing (typed)

```mojo
from mozz import forall, ArbitraryUInt16, Xoshiro256

fn gen_u16(mut rng: Xoshiro256) -> UInt16:
    return ArbitraryUInt16.arbitrary(rng)

fn shrink_u16(v: UInt16) -> List[UInt16]:
    return ArbitraryUInt16.shrink(v)

fn no_overflow(v: UInt16) raises -> Bool:
    return Int(v) + 1 > Int(v)

fn main() raises:
    forall[UInt16](no_overflow, gen_u16, shrink_u16, trials=5_000, seed=42)

```

### Level 3 — Raw byte property

```mojo
from mozz import forall_bytes

fn safe_roundtrip(data: List[UInt8]) raises -> Bool:
    try:
        var decoded = MyCodec.decode(data)
        var re_encoded = MyCodec.encode(decoded)
        return re_encoded == data
    except:
        return True  # rejections are fine

fn main() raises:
    forall_bytes(safe_roundtrip, max_len=512, trials=50_000, seed=1)
```
"""

from .rng import Xoshiro256
from .mutator import (
    MutatorChain,
    MutatorId,
    BitFlip,
    ByteSubstitution,
    ByteInsertion,
    ByteDeletion,
    BlockDuplication,
    Splice,
    BoundaryInt,
    default_mutator,
)
from .corpus import Corpus
from .arbitrary import (
    Arbitrary,
    ArbitraryBool,
    ArbitraryUInt8,
    ArbitraryUInt16,
    ArbitraryUInt32,
    ArbitraryUInt64,
    ArbitraryInt,
    ArbitraryString,
    ArbitraryBytes,
)
from .shrink import shrink_bytes
from .property import forall, forall_bytes
from .runner import FuzzConfig, FuzzTarget, fuzz
