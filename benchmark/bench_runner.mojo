"""Benchmark: scalar vs SIMD buffer fill at multiple sizes, and mutation throughput.

**What we measure and why:**

Fill throughput (GB/s, GElems/s)
    The PRNG's ``fill`` method is called by every mutation operator that
    needs fresh random bytes (``ByteInsertion``, ``BlockDuplication``).
    We compare two implementations across three buffer sizes to show how
    the SIMD advantage scales:

    ─ ``fill/scalar``  8 individual byte-extract-and-store per u64
                       (7 shifts + 8 masks + 8 stores per 8-byte block)
    ─ ``fill/simd``    one ``bitcast[UInt64]`` store per u64 — zero arithmetic

    Sizes benchmarked:
    ─  64 B  — typical short fuzz input (HTTP header, URL, small packet)
    ─   1 KB — typical large fuzz input (HTTP body, WebSocket frame)
    ─  16 KB — stress test (large file formats, network buffers)

    DataMovement (GB/s): bytes written to the output buffer.
    throughput (GElems/s): u64 calls to next_u64(), i.e. SIZE / 8.

Mutation throughput (GElems/s, GB/s)
    One full fuzz step: ``corpus.pick`` + ``mutate``.
    GElems/s = mutations per second (multiply by 1e9 to get absolute count).
    GB/s     = approximate bytes processed (64-byte representative seed).
    This is the number that maps to "inputs tested per second."

Run:
    pixi run bench
"""

from benchmark import (
    Bench,
    BenchConfig,
    Bencher,
    BenchId,
    ThroughputMeasure,
    BenchMetric,
    keep,
    clobber_memory,
)

from mozz.rng import Xoshiro256
from mozz.mutator import default_mutator
from mozz.corpus import Corpus


# ---------------------------------------------------------------------------
# Scalar fill: 8 individual byte-extract-and-store per u64 (baseline)
# ---------------------------------------------------------------------------


@always_inline
fn _fill_scalar(mut rng: Xoshiro256, mut buf: List[UInt8]):
    var n = len(buf)
    var ptr = buf.unsafe_ptr()
    var i = 0
    while i + 8 <= n:
        var v = rng.next_u64()
        (ptr + i).store(UInt8(v & 0xFF))
        (ptr + i + 1).store(UInt8((v >> 8) & 0xFF))
        (ptr + i + 2).store(UInt8((v >> 16) & 0xFF))
        (ptr + i + 3).store(UInt8((v >> 24) & 0xFF))
        (ptr + i + 4).store(UInt8((v >> 32) & 0xFF))
        (ptr + i + 5).store(UInt8((v >> 40) & 0xFF))
        (ptr + i + 6).store(UInt8((v >> 48) & 0xFF))
        (ptr + i + 7).store(UInt8((v >> 56) & 0xFF))
        i += 8
    while i < n:
        (ptr + i).store(rng.next_byte())
        i += 1


# ---------------------------------------------------------------------------
# SIMD fill: one bitcast store per u64 — what rng.fill uses in production
# ---------------------------------------------------------------------------


@always_inline
fn _fill_simd(mut rng: Xoshiro256, mut buf: List[UInt8]):
    var n = len(buf)
    var ptr = buf.unsafe_ptr()
    var i = 0
    while i + 8 <= n:
        var v = rng.next_u64()
        (ptr + i).bitcast[UInt64]().store(v)
        i += 8
    while i < n:
        (ptr + i).store(rng.next_byte())
        i += 1


# ---------------------------------------------------------------------------
# Helper: register both DataMovement and throughput for a fill bench
# ---------------------------------------------------------------------------


@always_inline
fn _fill_measures(size: Int) -> List[ThroughputMeasure]:
    """Return [bytes, elements] measures for a fill benchmark of ``size`` bytes."""
    var m = List[ThroughputMeasure]()
    m.append(ThroughputMeasure(BenchMetric.bytes, size))
    # elements = number of next_u64() calls = size / 8
    m.append(ThroughputMeasure(BenchMetric.elements, size // 8))
    return m^


fn main() raises:
    print("=" * 60)
    print("mozz benchmark")
    print("=" * 60)
    print()

    var bench = Bench(BenchConfig(max_iters=500))

    # ── Fill: 64 bytes ───────────────────────────────────────────────────────

    var rng_s64 = Xoshiro256(seed=1)
    var buf_s64 = List[UInt8](length=64, fill=UInt8(0))
    var rng_v64 = Xoshiro256(seed=1)
    var buf_v64 = List[UInt8](length=64, fill=UInt8(0))

    @parameter
    @always_inline
    fn bench_scalar_64(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            _fill_scalar(rng_s64, buf_s64)
            clobber_memory()

        b.iter[call_fn]()

    @parameter
    @always_inline
    fn bench_simd_64(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            _fill_simd(rng_v64, buf_v64)
            clobber_memory()

        b.iter[call_fn]()

    bench.bench_function[bench_scalar_64](BenchId("fill_64b", "scalar"), _fill_measures(64))
    bench.bench_function[bench_simd_64](BenchId("fill_64b", "simd"), _fill_measures(64))

    # ── Fill: 1 KB ───────────────────────────────────────────────────────────

    var rng_s1k = Xoshiro256(seed=1)
    var buf_s1k = List[UInt8](length=1024, fill=UInt8(0))
    var rng_v1k = Xoshiro256(seed=1)
    var buf_v1k = List[UInt8](length=1024, fill=UInt8(0))

    @parameter
    @always_inline
    fn bench_scalar_1k(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            _fill_scalar(rng_s1k, buf_s1k)
            clobber_memory()

        b.iter[call_fn]()

    @parameter
    @always_inline
    fn bench_simd_1k(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            _fill_simd(rng_v1k, buf_v1k)
            clobber_memory()

        b.iter[call_fn]()

    bench.bench_function[bench_scalar_1k](BenchId("fill_1kb", "scalar"), _fill_measures(1024))
    bench.bench_function[bench_simd_1k](BenchId("fill_1kb", "simd"), _fill_measures(1024))

    # ── Fill: 16 KB ──────────────────────────────────────────────────────────

    var rng_s16k = Xoshiro256(seed=1)
    var buf_s16k = List[UInt8](length=16384, fill=UInt8(0))
    var rng_v16k = Xoshiro256(seed=1)
    var buf_v16k = List[UInt8](length=16384, fill=UInt8(0))

    @parameter
    @always_inline
    fn bench_scalar_16k(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            _fill_scalar(rng_s16k, buf_s16k)
            clobber_memory()

        b.iter[call_fn]()

    @parameter
    @always_inline
    fn bench_simd_16k(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            _fill_simd(rng_v16k, buf_v16k)
            clobber_memory()

        b.iter[call_fn]()

    bench.bench_function[bench_scalar_16k](BenchId("fill_16kb", "scalar"), _fill_measures(16384))
    bench.bench_function[bench_simd_16k](BenchId("fill_16kb", "simd"), _fill_measures(16384))

    # ── Mutation throughput ───────────────────────────────────────────────────

    var rng_m = Xoshiro256(seed=7)
    var corpus = Corpus.default()
    var mutator = default_mutator()
    mutator.update_corpus(corpus._seeds)

    @parameter
    @always_inline
    fn bench_mutate(mut b: Bencher) raises capturing:
        @parameter
        @always_inline
        fn call_fn() raises:
            var seed = corpus.pick(rng_m)
            var out = mutator.mutate(Span[UInt8](seed), rng_m)
            keep(out)

        b.iter[call_fn]()

    # elements = mutations/sec; bytes ≈ typical 64-byte seed in/out
    var mut_measures = List[ThroughputMeasure]()
    mut_measures.append(ThroughputMeasure(BenchMetric.elements, 1))
    mut_measures.append(ThroughputMeasure(BenchMetric.bytes, 64))
    bench.bench_function[bench_mutate](
        BenchId("fuzz", "mutations_per_sec"),
        mut_measures,
    )

    # ── Report ────────────────────────────────────────────────────────────────
    print(bench)
    print()
    print("fill DataMovement (GB/s): bytes written to the output buffer")
    print("fill throughput (GElems/s): next_u64() calls per second (× 1e9)")
    print()
    print(
        "fuzz throughput (GElems/s) × 1e9 = mutations/second"
        " (= inputs tested/sec for an instant target)"
    )
    print("fuzz DataMovement (GB/s): based on 64-byte representative seed")
