"""Tests for forall() and forall_bytes() property-based testing.

Verifies: trivially-true properties pass, known-bad properties are caught,
and the same seed reproduces the same failure.
"""

from testing import assert_equal, assert_true, assert_false, TestSuite
from mozz.rng import Xoshiro256
from mozz.arbitrary import ArbitraryUInt8, ArbitraryUInt16, ArbitraryInt
from mozz.property import forall, forall_bytes


# ── Helper predicates (not test_ prefix, excluded from discovery) ─────────────


fn uint8_always_in_range(v: UInt8) raises -> Bool:
    """Trivially true: UInt8 is always in [0, 255]."""
    return Int(v) >= 0 and Int(v) <= 255


fn uint8_always_false(v: UInt8) raises -> Bool:
    """Always fails — used to verify forall catches failures."""
    return False


fn uint16_positive_or_zero(v: UInt16) raises -> Bool:
    """UInt16 is always >= 0."""
    return UInt32(v) >= 0


fn int_abs_nonnegative(v: Int) raises -> Bool:
    """Absolute value is always non-negative."""
    if v >= 0:
        return v >= 0
    return -v >= 0


fn bytes_length_nonnegative(data: List[UInt8]) raises -> Bool:
    """Always true: len(data) >= 0 for any input."""
    return len(data) >= 0


fn bytes_always_false(data: List[UInt8]) raises -> Bool:
    """Always fails — used to verify forall_bytes catches failures."""
    return False


fn bytes_raises_on_nonempty(data: List[UInt8]) raises -> Bool:
    """Raises an error for non-empty inputs."""
    if len(data) > 0:
        raise Error("unexpected failure")
    return True


# ── Generator / shrinker wrappers ─────────────────────────────────────────────


fn gen_uint8(mut rng: Xoshiro256) -> UInt8:
    return ArbitraryUInt8.arbitrary(rng)


fn shrink_uint8(v: UInt8) -> List[UInt8]:
    return ArbitraryUInt8.shrink(v)


fn gen_uint16(mut rng: Xoshiro256) -> UInt16:
    return ArbitraryUInt16.arbitrary(rng)


fn shrink_uint16(v: UInt16) -> List[UInt16]:
    return ArbitraryUInt16.shrink(v)


fn gen_int(mut rng: Xoshiro256) -> Int:
    return ArbitraryInt.arbitrary(rng)


fn shrink_int(v: Int) -> List[Int]:
    return ArbitraryInt.shrink(v)


# ── Tests ─────────────────────────────────────────────────────────────────────


def test_forall_trivially_true():
    """Forall on an always-true property must not raise."""
    forall[UInt8](
        uint8_always_in_range, gen_uint8, shrink_uint8, trials=500, seed=1
    )


def test_forall_catches_false():
    """Forall must raise when the property returns False."""
    var caught = False
    try:
        forall[UInt8](
            uint8_always_false, gen_uint8, shrink_uint8, trials=100, seed=2
        )
    except:
        caught = True
    assert_true(caught)


def test_forall_uint16_trivial():
    """Forall on a trivially-true UInt16 property must pass."""
    forall[UInt16](
        uint16_positive_or_zero, gen_uint16, shrink_uint16, trials=1_000, seed=3
    )


def test_forall_int_trivial():
    """Forall on a simple Int property must pass."""
    forall[Int](int_abs_nonnegative, gen_int, shrink_int, trials=500, seed=4)


def test_forall_bytes_trivially_true():
    """Calling forall_bytes on a trivially-true property must not raise."""
    forall_bytes(bytes_length_nonnegative, max_len=256, trials=500, seed=5)


def test_forall_bytes_catches_false():
    """Calling forall_bytes must raise when the property returns False."""
    var caught = False
    try:
        forall_bytes(bytes_always_false, max_len=64, trials=10, seed=6)
    except:
        caught = True
    assert_true(caught)


def test_forall_bytes_catches_unexpected_raise():
    """Calling forall_bytes must catch unexpected raises from the predicate."""
    var caught = False
    try:
        forall_bytes(bytes_raises_on_nonempty, max_len=8, trials=100, seed=7)
    except:
        caught = True
    assert_true(caught)


def test_forall_zero_trials():
    """Forall with trials=0 must not raise (nothing to test)."""
    forall[UInt8](uint8_always_false, gen_uint8, shrink_uint8, trials=0, seed=8)


def test_forall_reproducible():
    """The same seed must produce the same failure message on repeated runs."""
    var failures = List[String]()
    for _ in range(2):
        try:
            forall[UInt8](
                uint8_always_false, gen_uint8, shrink_uint8, trials=10, seed=42
            )
        except e:
            failures.append(String(e))
    assert_equal(len(failures), 2)
    assert_equal(failures[0], failures[1])


def main():
    print("=" * 60)
    print("test_property.mojo")
    print("=" * 60)
    print()
    TestSuite.discover_tests[__functions_in_module()]().run()
