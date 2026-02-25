"""Typed random value generation for property-based testing.

The ``Arbitrary`` trait enables ``forall[T: Arbitrary](...)`` to generate
well-typed test cases.  Implementations for all primitive Mojo types ship
with the library.

Example:
    ```mojo
    var rng = Xoshiro256(seed=99)
    var u = UInt16.arbitrary(rng)   # random UInt16 (boundary-biased)
    var s = String.arbitrary(rng)   # random valid UTF-8 string
    var xs = List[UInt8].arbitrary(rng)  # List[UInt8] with Arbitrary[UInt8]
    ```

Custom types:
    ```mojo
    struct Point:
        var x: Int
        var y: Int

        @staticmethod
        fn arbitrary(mut rng: Xoshiro256) -> Point:
            return Point(x=Int.arbitrary(rng), y=Int.arbitrary(rng))

        @staticmethod
        fn shrink(value: Point) -> List[Point]:
            var out = List[Point]()
            if value.x != 0:
                out.append(Point(x=0, y=value.y))
            if value.y != 0:
                out.append(Point(x=value.x, y=0))
            return out^
    ```
"""

from .rng import Xoshiro256


fn _int_boundaries() -> List[Int]:
    """Return boundary integer values for numeric type generation.

    Includes both positive and negative extremes so that ``ArbitraryInt``
    exercises the full signed 64-bit domain.
    """
    return [
        0,
        1,
        -1,
        127,
        -127,
        128,
        -128,
        255,
        -255,
        256,
        -256,
        32767,
        -32767,
        32768,
        -32768,
        65535,
        -65535,
        65536,
        -65536,
        2147483647,
        -2147483647,
        2147483648,
        -2147483648,
        4294967295,
        -4294967295,
    ]


# ── Arbitrary trait ────────────────────────────────────────────────────────────


trait Arbitrary(Copyable, Movable):
    """Trait for types that can generate random instances of themselves.

    Implement ``arbitrary(rng)`` to produce a random value and optionally
    ``shrink(value)`` to return simpler variants for counterexample
    minimization.

    Types implementing ``Arbitrary`` work automatically with ``forall[T]()``
    and ``forall_bytes()``.

    Note:
        Requires ``Copyable`` and ``Movable`` because ``shrink()`` returns
        ``List[Self]``, which requires ``Self: Copyable``.
    """

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> Self:
        """Generate a random instance of ``Self``.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random value of type ``Self``.
        """
        ...

    @staticmethod
    fn shrink(value: Self) -> List[Self]:
        """Return simpler variants of ``value`` for counterexample minimization.

        The default implementation returns an empty list (no shrinking).
        Override to provide problem-specific simplifications.

        Args:
            value: The counterexample to simplify.

        Returns:
            A list of simpler variants (may be empty).
        """
        return List[Self]()


# ── Primitive implementations ──────────────────────────────────────────────────


struct ArbitraryBool:
    """``Arbitrary`` implementation for ``Bool``."""

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> Bool:
        """Generate a uniformly random boolean.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            ``True`` or ``False`` with equal probability.
        """
        return rng.next_bool()

    @staticmethod
    fn shrink(value: Bool) -> List[Bool]:
        """Shrink: ``True`` → ``[False]``, ``False`` → ``[]``.

        Args:
            value: The value to shrink.

        Returns:
            A simpler variant list.
        """
        var out = List[Bool]()
        if value:
            out.append(False)
        return out^


struct ArbitraryUInt8:
    """``Arbitrary`` implementation for ``UInt8``."""

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> UInt8:
        """Generate a random ``UInt8`` with 20% boundary bias.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random ``UInt8``.
        """
        if rng.next_below(10) < 2:  # 20% boundary
            var boundary_bytes: List[UInt8] = [
                0x00,
                0x01,
                0x7F,
                0x80,
                0xFE,
                0xFF,
            ]
            return boundary_bytes[Int(rng.next_below(6))]
        return rng.next_byte()

    @staticmethod
    fn shrink(value: UInt8) -> List[UInt8]:
        """Shrink toward 0: ``v`` → ``[0, v/2]`` (if distinct).

        Args:
            value: Value to shrink.

        Returns:
            Simpler variants.
        """
        var out = List[UInt8]()
        if value != 0:
            out.append(0)
        if value // 2 != value and value // 2 != 0:
            out.append(value // 2)
        return out^


struct ArbitraryUInt16:
    """``Arbitrary`` implementation for ``UInt16``."""

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> UInt16:
        """Generate a random ``UInt16`` with 20% boundary bias.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random ``UInt16``.
        """
        if rng.next_below(10) < 2:
            var boundaries: List[UInt16] = [
                0,
                1,
                127,
                128,
                255,
                256,
                32767,
                32768,
                65534,
                65535,
            ]
            return boundaries[Int(rng.next_below(10))]
        return UInt16(rng.next_u32() & 0xFFFF)

    @staticmethod
    fn shrink(value: UInt16) -> List[UInt16]:
        """Shrink toward 0.

        Args:
            value: Value to shrink.

        Returns:
            Simpler variants.
        """
        var out = List[UInt16]()
        if value != 0:
            out.append(0)
        if value // 2 != value and value // 2 != 0:
            out.append(value // 2)
        return out^


struct ArbitraryUInt32:
    """``Arbitrary`` implementation for ``UInt32``."""

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> UInt32:
        """Generate a random ``UInt32`` with 20% boundary bias.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random ``UInt32``.
        """
        if rng.next_below(10) < 2:
            var boundaries: List[UInt32] = [
                0,
                1,
                127,
                128,
                255,
                256,
                32767,
                32768,
                65535,
                65536,
                2147483647,
                2147483648,
                4294967294,
                4294967295,
            ]
            return boundaries[Int(rng.next_below(14))]
        return rng.next_u32()

    @staticmethod
    fn shrink(value: UInt32) -> List[UInt32]:
        """Shrink toward 0.

        Args:
            value: Value to shrink.

        Returns:
            Simpler variants.
        """
        var out = List[UInt32]()
        if value != 0:
            out.append(0)
        if value // 2 != value and value // 2 != 0:
            out.append(value // 2)
        return out^


struct ArbitraryUInt64:
    """``Arbitrary`` implementation for ``UInt64``."""

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> UInt64:
        """Generate a random ``UInt64`` with 20% boundary bias.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random ``UInt64``.
        """
        if rng.next_below(10) < 2:
            var boundaries: List[UInt64] = [
                0,
                1,
                127,
                128,
                255,
                256,
                32767,
                32768,
                65535,
                65536,
                2147483647,
                2147483648,
                4294967295,
                4294967296,
                9223372036854775807,
                9223372036854775808,
                18446744073709551614,
                18446744073709551615,
            ]
            return boundaries[Int(rng.next_below(18))]
        return rng.next_u64()

    @staticmethod
    fn shrink(value: UInt64) -> List[UInt64]:
        """Shrink toward 0.

        Args:
            value: Value to shrink.

        Returns:
            Simpler variants.
        """
        var out = List[UInt64]()
        if value != 0:
            out.append(0)
        if value // 2 != value and value // 2 != 0:
            out.append(value // 2)
        return out^


struct ArbitraryInt:
    """``Arbitrary`` implementation for ``Int``."""

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> Int:
        """Generate a random ``Int`` with 20% boundary bias.

        Generates values across the full signed range, including negative
        integers.  Boundary values (0, ±1, ±2^7, ±2^31, etc.) are produced
        with 20% probability to increase edge-case coverage.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random ``Int`` covering the full signed 64-bit range.
        """
        if rng.next_below(10) < 2:
            var int_b = _int_boundaries()
            var idx = Int(rng.next_below(UInt64(len(int_b))))
            return int_b[idx]
        # Generate a non-negative magnitude then randomly negate it so that
        # both positive and negative halves of the signed range are covered.
        var magnitude = Int(rng.next_u64() >> 1)
        return -magnitude if rng.next_bool() else magnitude

    @staticmethod
    fn shrink(value: Int) -> List[Int]:
        """Shrink toward 0.

        Args:
            value: Value to shrink.

        Returns:
            Simpler variants.
        """
        var out = List[Int]()
        if value != 0:
            out.append(0)
        if value < 0:
            out.append(-value)
        var half = value // 2
        if half != value and half != 0:
            out.append(half)
        return out^


struct ArbitraryString:
    """``Arbitrary`` implementation for ``String``.

    Generates valid UTF-8 strings of length 0–256.  The character set is
    weighted: 70% ASCII printable, 15% ASCII control, 15% multi-byte UTF-8.
    """

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> String:
        """Generate a random valid UTF-8 string.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A pseudo-random ``String`` of length 0–256 (byte count).
        """
        var length = Int(rng.next_below(257))
        var out = String()
        var i = 0
        while i < length:
            var kind = rng.next_below(20)
            if kind < 14:
                # ASCII printable 0x20–0x7E
                var c = UInt8(0x20 + Int(rng.next_below(0x5F)))
                out += chr(Int(c))
                i += 1
            elif kind < 17:
                # ASCII control (tab, newline, carriage return)
                var ctrl: List[UInt8] = [0x09, 0x0A, 0x0D]
                out += chr(Int(ctrl[Int(rng.next_below(3))]))
                i += 1
            else:
                # 2-byte UTF-8 codepoint (U+0080–U+07FF)
                var cp = UInt32(0x0080) + UInt32(rng.next_below(0x0780))
                out += _encode_utf8_codepoint(cp)
                i += 2
        return out^

    @staticmethod
    fn shrink(value: String) -> List[String]:
        """Shrink by dropping the second half or removing a character.

        Args:
            value: String to shrink.

        Returns:
            Simpler string variants.
        """
        var out = List[String]()
        var n = len(value)
        if n == 0:
            return out^
        out.append(String(""))
        if n > 1:
            out.append(String(value[: n // 2]))
        return out^


struct ArbitraryBytes:
    """``Arbitrary`` implementation for raw bytes ``List[UInt8]``.

    Generates length 0–256 byte sequences with no UTF-8 constraint.
    Useful for raw byte fuzzing targets.
    """

    @staticmethod
    fn arbitrary(mut rng: Xoshiro256) -> List[UInt8]:
        """Generate a random byte sequence of length 0–256.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A ``List[UInt8]`` of pseudo-random bytes.
        """
        var length = Int(rng.next_below(257))
        var out = List[UInt8](capacity=length)
        for _ in range(length):
            out.append(rng.next_byte())
        return out^

    @staticmethod
    fn shrink(value: List[UInt8]) -> List[List[UInt8]]:
        """Shrink by halving or truncating.

        Args:
            value: Bytes to shrink.

        Returns:
            Simpler byte sequences.
        """
        var out = List[List[UInt8]]()
        var n = len(value)
        if n == 0:
            return out^
        out.append(List[UInt8]())
        if n > 1:
            out.append(List[UInt8](value[: n // 2]))
        return out^


# ── UTF-8 encoding helper ─────────────────────────────────────────────────────


fn _encode_utf8_codepoint(cp: UInt32) -> String:
    """Encode a Unicode codepoint as a UTF-8 ``String``.

    Handles 1–3 byte encodings (covers BMP).  Codepoints above U+FFFF are
    clamped to U+FFFD (replacement character).

    Args:
        cp: Unicode codepoint value.

    Returns:
        UTF-8 encoded string for the codepoint.
    """
    if cp < 0x80:
        return chr(Int(cp))
    elif cp < 0x800:
        var b0 = UInt8(0xC0 | (cp >> 6))
        var b1 = UInt8(0x80 | (cp & 0x3F))
        var s = String()
        s += chr(Int(b0))
        s += chr(Int(b1))
        return s^
    elif cp < 0x10000:
        var b0 = UInt8(0xE0 | (cp >> 12))
        var b1 = UInt8(0x80 | ((cp >> 6) & 0x3F))
        var b2 = UInt8(0x80 | (cp & 0x3F))
        var s = String()
        s += chr(Int(b0))
        s += chr(Int(b1))
        s += chr(Int(b2))
        return s^
    else:
        return chr(0xFFFD)  # replacement character
