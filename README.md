<div align="center">
  <img src="logo.png" alt="mozz logo" width="200" />
</div>

# mozz

[![CI](https://github.com/ehsanmok/mozz/actions/workflows/ci.yml/badge.svg)](https://github.com/ehsanmok/mozz/actions/workflows/ci.yml)
[![Docs](https://github.com/ehsanmok/mozz/actions/workflows/docs.yml/badge.svg)](https://github.com/ehsanmok/mozz/actions/workflows/docs.yml)

> [!WARNING]
> **Under development.** APIs may change.

A **pure-Mojo fuzzing and property-based testing library** with zero external
dependencies and no compiler flags required. Write a harness, call `fuzz()`.

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
invariant that must hold across all inputs (for example: "encoding then decoding
any value returns the original") and the library generates hundreds or thousands
of random inputs to try to falsify it. Instead of writing assertions for a
handful of chosen cases, you write the invariant once and let the library find
inputs that break it. When a counterexample is found, the input is automatically
shrunk to the simplest possible case that still triggers the failure, making the
root cause easier to isolate and fix. Well-known property-based testing libraries
include Haskell's [QuickCheck](https://hackage.haskell.org/package/QuickCheck), Python's [Hypothesis](https://hypothesis.readthedocs.io), and Rust's [proptest](https://github.com/proptest-rs/proptest).

The combination of fuzzing and property-based testing covers different failure
modes: fuzzing finds crashes caused by inputs the developer never considered,
while property tests find logic errors where the function produces a wrong result
rather than crashing.

## Key properties of mozz

- **Zero deps**: no libFuzzer, no C ABI, no FFI surface whatsoever
- **Three levels**: raw byte fuzzing, typed property tests, custom generators
- **Deterministic**: every run is seeded; crashing inputs are saved to disk for replay
- **Shrinking**: failing inputs are minimized automatically via delta-debugging

## Requirements

[pixi](https://pixi.sh) package manager (wraps Mojo nightly automatically)

## Installation

Add mozz to your project's `pixi.toml`:

```toml
[workspace]
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
preview = ["pixi-build"]

[dependencies]
mozz = { git = "https://github.com/ehsanmok/mozz.git", branch = "main" }
```

Then run:

```bash
pixi install
```

## Quick Start

### Level 1 -- Raw byte fuzzing

Write one function, call `fuzz()`. Any `raises` is treated as a normal
rejection; a panic or `debug_assert` failure is a crash and is saved to disk.

```mojo
from mozz import fuzz, FuzzConfig

fn target(data: List[UInt8]) raises:
    _ = MyParser.parse(data)  # raises = fine, panic = bug

fn main() raises:
    fuzz(
        target,
        FuzzConfig(
            max_runs=100_000,
            seed=42,
            verbose=True,           # progress lines + final report to stdout
            report_file="fuzz.log", # also write final report to file
        ),
    )
```

```
[mozz] crashes: 0 | runs: 5000  | corpus: 4  | rejects: 312  | 5%
[mozz] crashes: 0 | runs: 10000 | corpus: 7  | rejects: 601  | 10%
...
[mozz] crashes: 0 | runs: 100000 | corpus: 14 | rejects: 6183 | 100%

[mozz] -- final report -------------------------------------------
[mozz]   seed:           42
[mozz]   runs:           100000
[mozz]   ok:             93817
[mozz]   rejections:     6183
[mozz]   corpus:         14 seeds
[mozz]   crashes (hits): 0
[mozz]   crashes (uniq): 0
[mozz] ----------------------------------------------------------
```

When crashes are found, the final report also shows where to find the inputs:

```
[mozz]   crashes (hits): 42        <- total crash triggers (incl. duplicates)
[mozz]   crashes (uniq): 3         <- unique inputs saved to disk
[mozz]   crash inputs: .mozz_crashes/crash_*.bin
[mozz]   replay:       mojo replay.mojo <crash_file>
```

### Replaying crashes

Every unique crashing input is saved to `<crash_dir>/crash_NNNN.bin`.
Duplicate inputs (same byte content) are deduplicated, so a single crash
type produces exactly one file. Load and replay them with `Corpus.load_crash`,
then minimize with `shrink_bytes`:

```mojo
from mozz import Corpus, shrink_bytes

fn is_crash(data: List[UInt8]) raises -> Bool:
    try:
        my_target(data)
        return False
    except e:
        return String(e).find("panic") >= 0

fn main() raises:
    # List all crash files
    var paths = Corpus.list_crashes(".mozz_crashes")
    print("found", len(paths), "unique crash(es)")

    # Replay and minimise the first one
    var input = Corpus.load_crash(paths[0])
    print("original:", len(input), "bytes")

    var minimal = shrink_bytes(input, is_crash)
    print("minimal: ", len(minimal), "bytes")
```

```bash
pixi run example-replay   # full worked example: generate -> list -> replay -> minimise
```

Seed the corpus with known-interesting inputs and mozz will mutate from there:

```mojo
fn main() raises:
    var seeds = List[List[UInt8]]()
    var valid_frame: List[UInt8] = [0x81, 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F]
    seeds.append(valid_frame^)
    fuzz(target, FuzzConfig(max_runs=500_000, seed=1), seeds)
```

### Level 2 -- Typed property tests

Test invariants over typed values. Built-in generators handle arbitrary
generation and shrinking; named helper functions replace lambdas:

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

### Level 3 -- Raw byte property tests

Property tests over arbitrary byte sequences, with automatic shrinking:

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

## Development Setup

```bash
git clone https://github.com/ehsanmok/mozz.git && cd mozz
pixi install
pixi run tests
```

Run individual test modules:

```bash
pixi run test-rng
pixi run test-mutators
pixi run test-corpus
pixi run test-arbitrary
pixi run test-property
pixi run test-runner
```

Run examples:

```bash
pixi run examples               # all three examples
pixi run example-raw-bytes      # raw byte fuzzing
pixi run example-property-test  # typed property tests
pixi run example-custom-type    # custom Arbitrary type
```

## API

### Core functions

```mojo
# Raw byte fuzzing
fuzz(target, config)                        # run the fuzz loop
fuzz(target, config, seeds)                 # with initial corpus

# Typed property tests
forall[T](prop, gen, shrink, trials, seed)  # typed: prop is fn(T)->Bool
forall_bytes(prop, max_len, trials, seed)   # byte: prop is fn(List[UInt8])->Bool

# Shrinking
shrink_bytes(input, is_crash)               # standalone ddmin minimizer
```

### `FuzzConfig`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_runs` | `Int` | `100_000` | Number of mutation iterations |
| `max_input_len` | `Int` | `65_540` | Maximum mutated input size (bytes) |
| `seed` | `UInt64` | `0` | PRNG seed (0 = entropy from heap address) |
| `corpus_dir` | `String` | `""` | Load/save persistent corpus; empty = in-memory only |
| `crash_dir` | `String` | `".mozz_crashes"` | Directory for saved crash inputs |
| `verbose` | `Bool` | `True` | Print progress lines and final report to stdout |
| `report_file` | `String` | `""` | Also write the final report to this file; empty = no file |
| `timeout_ms` | `Int` | `0` | Per-iteration timeout (reserved; not enforced in v0.1.0) |

### `Arbitrary` trait

Implement this trait on any type to use it with `forall`:

```mojo
trait Arbitrary:
    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> Self
        """Return a random instance."""

    @staticmethod
    fn shrink(value: Self) -> List[Self]:
        """Return simpler candidates for minimization."""
```

Built-in implementations: `ArbitraryBool`, `ArbitraryUInt8`, `ArbitraryUInt16`,
`ArbitraryUInt32`, `ArbitraryUInt64`, `ArbitraryInt`, `ArbitraryString`,
`ArbitraryBytes`.

### Custom `Arbitrary` type

```mojo
from mozz import Arbitrary, forall, Xoshiro256

struct Color(ImplicitlyCopyable, Movable):
    var r: UInt8
    var g: UInt8
    var b: UInt8

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> Color:
        return Color(rng.next_byte(), rng.next_byte(), rng.next_byte())

    @staticmethod
    fn shrink(c: Color) -> List[Color]:
        var out = List[Color]()
        if c.r > 0: out.append(Color(c.r - 1, c.g, c.b))
        if c.g > 0: out.append(Color(c.r, c.g - 1, c.b))
        if c.b > 0: out.append(Color(c.r, c.g, c.b - 1))
        return out^

fn gen_color(mut rng: Xoshiro256) -> Color:
    return Color.arbitrary(rng)

fn shrink_color(c: Color) -> List[Color]:
    return Color.shrink(c)

fn double_invert_is_identity(c: Color) raises -> Bool:
    fn invert(x: Color) -> Color:
        return Color(255 - x.r, 255 - x.g, 255 - x.b)
    var result = invert(invert(c))
    return result.r == c.r and result.g == c.g and result.b == c.b

fn main() raises:
    forall[Color](double_invert_is_identity, gen_color, shrink_color, trials=3_000)
```

### Mutators

`mozz` ships eight built-in mutators. The default chain selects among them
with tunable weights:

| Mutator | Description |
|---------|-------------|
| `BitFlip` | Flip a random bit |
| `ByteSubstitution` | Replace a byte with a random value |
| `ByteInsertion` | Insert a random byte at a random position |
| `ByteDeletion` | Remove a byte at a random position |
| `BlockDuplication` | Duplicate a block of bytes |
| `Splice` | Splice in bytes from another corpus entry |
| `BoundaryInt` | Replace a byte with a boundary integer (0, 127, 128, 255) |
| `MutatorChain` | Weighted combination of any of the above |

```mojo
from mozz import default_mutator, FuzzConfig, fuzz

fn main() raises:
    var m = default_mutator()   # standard weighted chain
    # or build a custom chain:
    # var m = MutatorChain(mutators, weights, corpus_ref)
    fuzz(target, FuzzConfig(max_runs=200_000))
```

### PRNG

`Xoshiro256` is the library's seedable PRNG (xoshiro256++ algorithm).
Seed `0` derives entropy from the heap address at startup:

```mojo
from mozz import Xoshiro256

var rng = Xoshiro256(seed=42)
var byte  = rng.next_byte()          # UInt8 in [0, 255]
var u32   = rng.next_u32()           # UInt32
var u64   = rng.next_u64()           # UInt64
var below = rng.next_below(100)      # UInt64 in [0, 100)
var flag  = rng.next_bool()          # Bool

var buf = List[UInt8](length=32, fill=UInt8(0))
rng.fill(buf)                        # fill buffer with random bytes
```

## LICENSE

[MIT](./LICENSE)
