<div align="center">
  <img src="logo.png" alt="mozz logo" width="200" />
</div>

# mozz

[![CI](https://github.com/ehsanmok/mozz/actions/workflows/ci.yml/badge.svg)](https://github.com/ehsanmok/mozz/actions/workflows/ci.yml)
[![Docs](https://github.com/ehsanmok/mozz/actions/workflows/docs.yml/badge.svg)](https://ehsanmok.github.io/mozz/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Pure-Mojo fuzzing and property-based testing. No libFuzzer, no C FFI,
no compiler flags. Write a target, call `fuzz()`.

```mojo
from mozz import fuzz, FuzzConfig

def target(data: List[UInt8]) raises:
    _ = MyParser.parse(data)

def main() raises:
    fuzz(target, FuzzConfig(max_runs=100_000, seed=42))
```

```
[mozz] crashes: 0 | runs: 100000 | corpus: 14 | rejects: 6183 | 100%
```

Crashing inputs are saved to disk, deduplicated, and automatically minimized
via delta-debugging. Every run is seeded for reproducibility.

## Installation

Add to your `pixi.toml`:

```toml
[workspace]
channels = ["https://conda.modular.com/max-nightly", "conda-forge"]
preview = ["pixi-build"]

[dependencies]
mozz = { git = "https://github.com/ehsanmok/mozz.git", tag = "v0.1.0" }
```

```bash
pixi install
```

Requires [pixi](https://pixi.sh) (pulls Mojo nightly automatically).

For the latest development version:

```toml
[dependencies]
mozz = { git = "https://github.com/ehsanmok/mozz.git", branch = "main" }
```

## Usage

mozz has three levels of API depending on how much structure you want.

### Raw byte fuzzing

Throw mutated bytes at a function. Anything that panics or trips an assertion
is a crash; raised exceptions are treated as valid rejections.

```mojo
from mozz import fuzz, FuzzConfig

def target(data: List[UInt8]) raises:
    _ = MyParser.parse(data)

def main() raises:
    fuzz(target, FuzzConfig(max_runs=100_000, seed=42))
```

`FuzzConfig` controls iteration count, max input size, corpus/crash directories,
verbosity, and PRNG seed. See the [docs](https://ehsanmok.github.io/mozz/) for
all fields.

### Typed property tests

State an invariant, supply a generator and minimizer, and mozz will try to
falsify it. On failure the counterexample is minimized before the error is
raised.

```mojo
from mozz import forall, Gen, Xoshiro256

def gen_u16(mut rng: Xoshiro256) -> UInt16:
    return Gen[UInt16].generate(rng)

def minimize_u16(v: UInt16) -> List[UInt16]:
    return Gen[UInt16].minimize(v)

def no_overflow(v: UInt16) raises -> Bool:
    return Int(v) + 1 > Int(v)

def main() raises:
    forall[UInt16](no_overflow, gen_u16, minimize_u16, trials=5_000, seed=42)
```

`Gen[T]` dispatches at compile time for `Bool`, `UInt8`, `UInt16`, `UInt32`,
`UInt64`, `Int`, and `String`. For other types, write a companion struct (see
[Custom types](#custom-types) below.

### Byte-level property tests

When you just want to check a property over raw bytes without defining a type:

```mojo
from mozz import forall_bytes

def safe_roundtrip(data: List[UInt8]) raises -> Bool:
    try:
        return MyCodec.encode(MyCodec.decode(data)) == data
    except:
        return True

def main() raises:
    forall_bytes(safe_roundtrip, max_len=512, trials=50_000, seed=1)
```

### Crash replay & minimization

`fuzz()` saves each unique crash to `<crash_dir>/crash_NNNN.bin`. Load them
back for replay and minimization:

```mojo
from mozz import Corpus, minimize_bytes

def is_crash(data: List[UInt8]) raises -> Bool:
    try:
        my_target(data)
        return False
    except e:
        return String(e).find("panic") >= 0

def main() raises:
    var paths = Corpus.list_crashes(".mozz_crashes")
    var input = Corpus.load_crash(paths[0])
    var minimal = minimize_bytes(input, is_crash)
    print(len(minimal), "bytes (was", len(input), ")")
```

### Custom types

Implement `generate` and `minimize` on a companion struct, then wire them
into `forall`:

```mojo
from mozz import forall, Xoshiro256

struct Color(ImplicitlyCopyable, Movable):
    var r: UInt8
    var g: UInt8
    var b: UInt8

struct FuzzableColor:
    @staticmethod
    def generate(mut rng: Xoshiro256) -> Color:
        return Color(rng.next_byte(), rng.next_byte(), rng.next_byte())

    @staticmethod
    def minimize(c: Color) -> List[Color]:
        var out = List[Color]()
        if c.r > 0: out.append(Color(c.r // 2, c.g, c.b))
        if c.g > 0: out.append(Color(c.r, c.g // 2, c.b))
        if c.b > 0: out.append(Color(c.r, c.g, c.b // 2))
        return out^

def gen_color(mut rng: Xoshiro256) -> Color:
    return FuzzableColor.generate(rng)

def minimize_color(c: Color) -> List[Color]:
    return FuzzableColor.minimize(c)

def prop(c: Color) raises -> Bool:
    var inv = Color(255 - c.r, 255 - c.g, 255 - c.b)
    return inv.r != c.r or inv.g != c.g or inv.b != c.b

def main() raises:
    forall[Color](prop, gen_color, minimize_color, trials=5_000)
```

## Internals

The mutation engine uses seven weighted operators: bit flips, byte
substitution (boundary-biased), insertion, deletion, block duplication,
cross-corpus splicing, and boundary integer injection. `default_mutator()`
returns the standard chain; you can build a custom `MutatorChain` with
different weights.

The PRNG is Xoshiro256++ seeded via SplitMix64. Corpus deduplication uses
FNV-1a hashing with FIFO eviction at 10k seeds.

Full API reference: [ehsanmok.github.io/mozz](https://ehsanmok.github.io/mozz/)

## Development

```bash
git clone https://github.com/ehsanmok/mozz.git && cd mozz
pixi install
pixi run tests      # all tests + examples
pixi run bench      # mutation throughput benchmark
```

Individual suites: `pixi run test-rng`, `test-mutators`, `test-corpus`,
`test-arbitrary`, `test-property`, `test-runner`.

Examples: `pixi run example-raw-bytes`, `example-property-test`,
`example-custom-type`, `example-replay`.

## License

[MIT](./LICENSE)
