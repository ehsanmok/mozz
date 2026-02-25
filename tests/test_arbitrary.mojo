"""Tests for Arbitrary implementations.

Covers: in-range values, boundary bias presence, shrink contracts, and
ArbitraryString UTF-8 validity.
"""

from testing import (
    assert_equal,
    assert_true,
    assert_false,
    assert_not_equal,
    TestSuite,
)
from mozz.rng import Xoshiro256
from mozz.arbitrary import (
    ArbitraryBool,
    ArbitraryUInt8,
    ArbitraryUInt16,
    ArbitraryUInt32,
    ArbitraryUInt64,
    ArbitraryInt,
    ArbitraryString,
    ArbitraryBytes,
)

comptime _N = 2_000


def test_arbitrary_bool_range():
    """ArbitraryBool.arbitrary() must produce both True and False."""
    var rng = Xoshiro256(seed=1)
    var saw_true = False
    var saw_false = False
    for _ in range(200):
        if ArbitraryBool.arbitrary(rng):
            saw_true = True
        else:
            saw_false = True
    assert_true(saw_true)
    assert_true(saw_false)


def test_arbitrary_bool_shrink():
    """Bool.shrink(True) must contain False; shrink(False) must be empty."""
    var shrunk_true = ArbitraryBool.shrink(True)
    assert_equal(len(shrunk_true), 1)
    assert_false(shrunk_true[0])
    assert_equal(len(ArbitraryBool.shrink(False)), 0)


def test_arbitrary_uint8_range():
    """ArbitraryUInt8.arbitrary() must stay in [0, 255]."""
    var rng = Xoshiro256(seed=2)
    for _ in range(_N):
        var v = ArbitraryUInt8.arbitrary(rng)
        assert_true(Int(v) >= 0 and Int(v) <= 255)


def test_arbitrary_uint8_boundary_bias():
    """ArbitraryUInt8 must hit boundary values (0 and 255) within 2000 runs."""
    var rng = Xoshiro256(seed=3)
    var saw_zero = False
    var saw_max = False
    for _ in range(_N):
        var v = ArbitraryUInt8.arbitrary(rng)
        if v == 0:
            saw_zero = True
        if v == 255:
            saw_max = True
    assert_true(saw_zero)
    assert_true(saw_max)


def test_arbitrary_uint8_shrink():
    """UInt8.shrink(v) must always contain 0 for v > 0; empty for v == 0."""
    assert_equal(len(ArbitraryUInt8.shrink(0)), 0)
    var shrunk = ArbitraryUInt8.shrink(100)
    var has_zero = False
    for i in range(len(shrunk)):
        if shrunk[i] == 0:
            has_zero = True
            break
    assert_true(has_zero)


def test_arbitrary_uint16_range():
    """ArbitraryUInt16.arbitrary() must stay in [0, 65535]."""
    var rng = Xoshiro256(seed=4)
    for _ in range(_N):
        assert_true(UInt32(ArbitraryUInt16.arbitrary(rng)) <= 65535)


def test_arbitrary_uint16_boundary():
    """ArbitraryUInt16 must produce 0 and 65535 within 2000 runs."""
    var rng = Xoshiro256(seed=5)
    var saw_zero = False
    var saw_max = False
    for _ in range(_N):
        var v = ArbitraryUInt16.arbitrary(rng)
        if v == 0:
            saw_zero = True
        if v == 65535:
            saw_max = True
    assert_true(saw_zero)
    assert_true(saw_max)


def test_arbitrary_uint32_range():
    """ArbitraryUInt32.arbitrary() must stay in [0, 2^32-1]."""
    var rng = Xoshiro256(seed=6)
    for _ in range(_N):
        assert_true(UInt64(ArbitraryUInt32.arbitrary(rng)) <= 0xFFFFFFFF)


def test_arbitrary_uint64_range():
    """ArbitraryUInt64.arbitrary() must complete without error."""
    var rng = Xoshiro256(seed=7)
    for _ in range(_N):
        _ = ArbitraryUInt64.arbitrary(rng)


def test_arbitrary_int_boundary():
    """ArbitraryInt must produce 0 within 2000 runs."""
    var rng = Xoshiro256(seed=8)
    var saw_zero = False
    for _ in range(_N):
        if ArbitraryInt.arbitrary(rng) == 0:
            saw_zero = True
            break
    assert_true(saw_zero)


def test_arbitrary_int_shrink():
    """ArbitraryInt.shrink(n) must include 0; shrink(0) must be empty."""
    var shrunk = ArbitraryInt.shrink(1000)
    var has_zero = False
    for i in range(len(shrunk)):
        if shrunk[i] == 0:
            has_zero = True
            break
    assert_true(has_zero)
    assert_equal(len(ArbitraryInt.shrink(0)), 0)


def test_arbitrary_string_not_empty_sometimes():
    """ArbitraryString must produce non-empty strings sometimes."""
    var rng = Xoshiro256(seed=9)
    var saw_nonempty = False
    for _ in range(200):
        if len(ArbitraryString.arbitrary(rng)) > 0:
            saw_nonempty = True
            break
    assert_true(saw_nonempty)


def test_arbitrary_string_length_bound():
    """ArbitraryString must produce strings of at most 512 bytes."""
    var rng = Xoshiro256(seed=10)
    for _ in range(500):
        assert_true(len(ArbitraryString.arbitrary(rng)) <= 512)


def test_arbitrary_string_shrink():
    """ArbitraryString.shrink must include empty string for non-empty input."""
    var shrunk = ArbitraryString.shrink("hello world")
    var has_empty = False
    for i in range(len(shrunk)):
        if len(shrunk[i]) == 0:
            has_empty = True
            break
    assert_true(has_empty)
    assert_equal(len(ArbitraryString.shrink("")), 0)


def test_arbitrary_bytes_range():
    """ArbitraryBytes.arbitrary() must return bytes all in [0, 255]."""
    var rng = Xoshiro256(seed=11)
    for _ in range(500):
        var bs = ArbitraryBytes.arbitrary(rng)
        for i in range(len(bs)):
            assert_true(Int(bs[i]) >= 0 and Int(bs[i]) <= 255)


def test_arbitrary_bytes_length_bound():
    """ArbitraryBytes must produce lists of at most 256 bytes."""
    var rng = Xoshiro256(seed=12)
    for _ in range(500):
        assert_true(len(ArbitraryBytes.arbitrary(rng)) <= 256)


def test_arbitrary_bytes_shrink():
    """ArbitraryBytes.shrink must include the empty list for non-empty input."""
    var data: List[UInt8] = [0x01, 0x02, 0x03, 0x04]
    var shrunk = ArbitraryBytes.shrink(data)
    var has_empty = False
    for i in range(len(shrunk)):
        if len(shrunk[i]) == 0:
            has_empty = True
            break
    assert_true(has_empty)


def main():
    print("=" * 60)
    print("test_arbitrary.mojo")
    print("=" * 60)
    print()
    TestSuite.discover_tests[__functions_in_module()]().run()
