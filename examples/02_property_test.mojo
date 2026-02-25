"""Example 2: Property-based testing with forall_bytes() and forall().

Demonstrates Level 2 API: express mathematical properties and let mozz
find counterexamples automatically.

Run:
    pixi run example-2
"""

from mozz import forall, forall_bytes, ArbitraryUInt16, ArbitraryUInt8
from mozz.rng import Xoshiro256


# ── Raw-byte property ─────────────────────────────────────────────────────────


fn encode_decode_roundtrip(data: List[UInt8]) raises -> Bool:
    """Property: our trivial encoder/decoder round-trips any input.

    Encoder: XOR every byte with 0xAA (its own inverse).
    Decoder: XOR every byte with 0xAA again.
    Property: decode(encode(x)) == x for all x.
    """
    var n = len(data)
    var encoded = List[UInt8](capacity=n)
    for i in range(n):
        encoded.append(data[i] ^ 0xAA)

    var decoded = List[UInt8](capacity=n)
    for i in range(n):
        decoded.append(encoded[i] ^ 0xAA)

    if len(decoded) != n:
        return False
    for i in range(n):
        if decoded[i] != data[i]:
            return False
    return True


# ── Typed properties ──────────────────────────────────────────────────────────


fn uint16_sum_fits_in_u32(v: UInt16) raises -> Bool:
    """Property: UInt16 + UInt16 never exceeds UInt32 max."""
    return UInt32(v) + UInt32(v) <= UInt32(0xFFFFFFFF)


fn byte_division_safe(v: UInt8) raises -> Bool:
    """Property: non-zero byte divided by itself equals 1."""
    if v == 0:
        return True  # skip zero — division by zero is undefined
    return Int(v) // Int(v) == 1


# ── Generator / shrinker helpers ──────────────────────────────────────────────


fn gen_u16(mut rng: Xoshiro256) -> UInt16:
    return ArbitraryUInt16.arbitrary(rng)


fn shrink_u16(v: UInt16) -> List[UInt16]:
    return ArbitraryUInt16.shrink(v)


fn gen_u8(mut rng: Xoshiro256) -> UInt8:
    return ArbitraryUInt8.arbitrary(rng)


fn shrink_u8(v: UInt8) -> List[UInt8]:
    return ArbitraryUInt8.shrink(v)


# ── Main ──────────────────────────────────────────────────────────────────────


fn main() raises:
    print("=== Example 2: Property-based testing ===\n")

    print(
        "1. Testing XOR round-trip property over 10 000 random byte"
        " sequences..."
    )
    forall_bytes(encode_decode_roundtrip, max_len=256, trials=10_000, seed=1)
    print("   PASS: encode→decode round-trips for all inputs\n")

    print("2. Testing UInt16 addition fits in UInt32 (5 000 trials)...")
    forall[UInt16](
        uint16_sum_fits_in_u32, gen_u16, shrink_u16, trials=5_000, seed=2
    )
    print("   PASS: UInt16 + UInt16 always fits in UInt32\n")

    print("3. Testing non-zero byte / itself == 1 (2 000 trials)...")
    forall[UInt8](byte_division_safe, gen_u8, shrink_u8, trials=2_000, seed=3)
    print("   PASS: non-zero byte / itself == 1\n")

    print("All properties hold!")
