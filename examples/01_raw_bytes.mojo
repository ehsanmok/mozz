"""Example 1: Raw-byte fuzzing with fuzz().

Demonstrates Level 1 API: provide any ``fn(List[UInt8]) raises -> None``
function and mozz will throw mutated bytes at it, looking for panics /
assertion failures.

Run:
    pixi run example-raw-bytes
"""

from mozz import fuzz, FuzzConfig


def toy_parser(data: List[UInt8]) raises:
    """A small hand-written parser that accepts a trivial TLV encoding.

    Format: [type: 1 byte][length: 1 byte][value: length bytes]

    Raises:
        Error: For any malformed input (expected; not a crash).
    """
    if len(data) < 2:
        raise Error("too short: need at least 2 bytes")

    var type_byte = data[0]
    var length = Int(data[1])

    if type_byte == 0x00:
        raise Error("reserved type byte 0x00")

    if len(data) < 2 + length:
        raise Error(
            "truncated value: need "
            + String(2 + length)
            + " bytes, got "
            + String(len(data))
        )

    # Consume value bytes (just validate they are non-zero for type 0x01)
    if type_byte == 0x01:
        for i in range(length):
            if data[2 + i] == 0x00:
                raise Error("type 0x01 value must not contain null bytes")

    # All other types: accepted


def main() raises:
    print("=== Example 1: Raw-byte fuzzing ===")
    print("Fuzzing a toy TLV parser for 10 000 iterations...")

    fuzz(
        toy_parser,
        FuzzConfig(
            max_runs=10_000,
            seed=42,  # deterministic — same result every run
            verbose=True,
            crash_dir=".mozz_crashes/example1",
        ),
    )

    print("Done! No crashes found.")
    print(
        "Tip: change the seed or increase max_runs to explore more of the"
        " input space."
    )
