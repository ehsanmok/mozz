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

from std.benchmark import (
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
def _fill_scalar(mut rng: Xoshiro256, mut buf: List[UInt8]):
    var n = len(buf)
    var ptr = buf.unsafe_ptr()
    var i = 0
    while i + 8 <= n:
        var v = rng.next_u64()
        ptr.unsafe_offset(i).unsafe_store(UInt8(v & 0xFF))
        ptr.unsafe_offset(i + 1).unsafe_store(UInt8((v >> 8) & 0xFF))
        ptr.unsafe_offset(i + 2).unsafe_store(UInt8((v >> 16) & 0xFF))
        ptr.unsafe_offset(i + 3).unsafe_store(UInt8((v >> 24) & 0xFF))
        ptr.unsafe_offset(i + 4).unsafe_store(UInt8((v >> 32) & 0xFF))
        ptr.unsafe_offset(i + 5).unsafe_store(UInt8((v >> 40) & 0xFF))
        ptr.unsafe_offset(i + 6).unsafe_store(UInt8((v >> 48) & 0xFF))
        ptr.unsafe_offset(i + 7).unsafe_store(UInt8((v >> 56) & 0xFF))
        i += 8
    while i < n:
        ptr.unsafe_offset(i).unsafe_store(rng.next_byte())
        i += 1


# ---------------------------------------------------------------------------
# SIMD fill: one bitcast store per u64 — what rng.fill uses in production
# ---------------------------------------------------------------------------


@always_inline
def _fill_simd(mut rng: Xoshiro256, mut buf: List[UInt8]):
    var n = len(buf)
    var ptr = buf.unsafe_ptr()
    var i = 0
    while i + 8 <= n:
        var v = rng.next_u64()
        ptr.unsafe_offset(i).unsafe_bitcast[UInt64]().unsafe_store(v)
        i += 8
    while i < n:
        ptr.unsafe_offset(i).unsafe_store(rng.next_byte())
        i += 1


# ---------------------------------------------------------------------------
# Helper: register both DataMovement and throughput for a fill bench
# ---------------------------------------------------------------------------


@always_inline
def _fill_measures(size: Int) -> List[ThroughputMeasure]:
    """Return [bytes, elements] measures for a fill benchmark of ``size`` bytes.
    """
    var m = List[ThroughputMeasure]()
    m.append(ThroughputMeasure(BenchMetric.bytes, size))
    # elements = number of next_u64() calls = size / 8
    m.append(ThroughputMeasure(BenchMetric.elements, size // 8))
    return m^


def _bench_scalar_fill[size: Int](mut b: Bencher) raises:
    """Scalar-fill closure for one buffer ``size``; owns its own rng/buf."""
    var rng = Xoshiro256(seed=1)
    var buf = List[UInt8](length=size, fill=UInt8(0))

    @always_inline
    def call_fn() raises {mut rng, mut buf}:
        _fill_scalar(rng, buf)
        clobber_memory()

    b.iter(call_fn)


def _bench_simd_fill[size: Int](mut b: Bencher) raises:
    """SIMD-fill closure for one buffer ``size``; owns its own rng/buf."""
    var rng = Xoshiro256(seed=1)
    var buf = List[UInt8](length=size, fill=UInt8(0))

    @always_inline
    def call_fn() raises {mut rng, mut buf}:
        _fill_simd(rng, buf)
        clobber_memory()

    b.iter(call_fn)


def _bench_mutate(mut b: Bencher) raises:
    """Mutation-throughput closure; owns its own rng/corpus/mutator."""
    var rng_m = Xoshiro256(seed=7)
    var corpus = Corpus.default()
    var mutator = default_mutator()
    mutator.update_corpus(corpus._seeds)

    @always_inline
    def call_fn() raises {mut rng_m, imm corpus, imm mutator}:
        var seed = corpus.pick(rng_m)
        var out = mutator.mutate(Span[UInt8, _](seed), rng_m)
        keep(out)

    b.iter(call_fn)


def main() raises:
    print("=" * 60)
    print("mozz benchmark")
    print("=" * 60)
    print()

    var bench = Bench(BenchConfig(max_iters=500))

    # ── Fill: 64 bytes ───────────────────────────────────────────────────────

    bench.bench_function(
        _bench_scalar_fill[64],
        BenchId("fill_64b", "scalar"),
        _fill_measures(64),
    )
    bench.bench_function(
        _bench_simd_fill[64], BenchId("fill_64b", "simd"), _fill_measures(64)
    )

    # ── Fill: 1 KB ───────────────────────────────────────────────────────────

    bench.bench_function(
        _bench_scalar_fill[1024],
        BenchId("fill_1kb", "scalar"),
        _fill_measures(1024),
    )
    bench.bench_function(
        _bench_simd_fill[1024],
        BenchId("fill_1kb", "simd"),
        _fill_measures(1024),
    )

    # ── Fill: 16 KB ──────────────────────────────────────────────────────────

    bench.bench_function(
        _bench_scalar_fill[16384],
        BenchId("fill_16kb", "scalar"),
        _fill_measures(16384),
    )
    bench.bench_function(
        _bench_simd_fill[16384],
        BenchId("fill_16kb", "simd"),
        _fill_measures(16384),
    )

    # ── Mutation throughput ───────────────────────────────────────────────────

    # elements = mutations/sec; bytes ≈ typical 64-byte seed in/out
    var mut_measures = List[ThroughputMeasure]()
    mut_measures.append(ThroughputMeasure(BenchMetric.elements, 1))
    mut_measures.append(ThroughputMeasure(BenchMetric.bytes, 64))
    bench.bench_function(
        _bench_mutate,
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
