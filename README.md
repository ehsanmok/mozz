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

- **Zero deps**: no libFuzzer, no C ABI, no FFI surface whatsoever
- **Three levels**: raw byte fuzzing, typed property tests, custom generators
- **Deterministic**: every run is seeded; crashing inputs are saved to disk for replay
- **Minimization**: failing inputs are minimized automatically via delta-debugging

Full API reference lives in [`mozz/__init__.mojo`](mozz/__init__.mojo).

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

### Level 1 — Raw byte fuzzing

```mojo
from mozz import fuzz, FuzzConfig

fn target(data: List[UInt8]) raises:
    _ = MyParser.parse(data)  # raises = valid rejection; panic = bug

fn main() raises:
    fuzz(target, FuzzConfig(max_runs=100_000, seed=42, verbose=True))
```

### Level 2 — Typed property tests

`Gen[T]` dispatches to the right generator at compile time:

```mojo
from mozz import forall, Gen, Xoshiro256

fn gen_u16(mut rng: Xoshiro256) -> UInt16:
    return Gen[UInt16].arbitrary(rng)

fn minimize_u16(v: UInt16) -> List[UInt16]:
    return Gen[UInt16].minimize(v)

fn no_overflow(v: UInt16) raises -> Bool:
    return Int(v) + 1 > Int(v)

fn main() raises:
    forall[UInt16](no_overflow, gen_u16, minimize_u16, trials=5_000, seed=42)
```

### Level 3 — Raw byte property tests

```mojo
from mozz import forall_bytes

fn safe_roundtrip(data: List[UInt8]) raises -> Bool:
    try:
        return MyCodec.encode(MyCodec.decode(data)) == data
    except:
        return True

fn main() raises:
    forall_bytes(safe_roundtrip, max_len=512, trials=50_000, seed=1)
```

### Crash replay and minimization

```mojo
from mozz import Corpus, minimize_bytes

fn is_crash(data: List[UInt8]) raises -> Bool:
    try:
        my_target(data)
        return False
    except e:
        return String(e).find("panic") >= 0

fn main() raises:
    var paths = Corpus.list_crashes(".mozz_crashes")
    var input = Corpus.load_crash(paths[0])
    var minimal = minimize_bytes(input, is_crash)
    print(len(minimal), "bytes (was", len(input), ")")
```

## Development Setup

```bash
git clone https://github.com/ehsanmok/mozz.git && cd mozz
pixi install
pixi run tests
```

Individual suites: `pixi run test-rng`, `test-mutators`, `test-corpus`,
`test-arbitrary`, `test-property`, `test-runner`.

Examples: `pixi run example-raw-bytes`, `example-property-test`,
`example-custom-type`, `example-replay`.

## LICENSE

[MIT](./LICENSE)
