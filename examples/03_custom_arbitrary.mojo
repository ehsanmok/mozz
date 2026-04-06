"""Example 3: Custom Fuzzable implementation.

Demonstrates how to implement the ``Fuzzable`` pattern for a user-defined
type and use it with ``forall()``.

Run:
    pixi run example-custom-type
"""

from mozz import forall
from mozz.rng import Xoshiro256


# ── Custom type ───────────────────────────────────────────────────────────────


struct Color(ImplicitlyCopyable, Movable):
    """An 8-bit RGB colour triple."""

    var r: UInt8
    var g: UInt8
    var b: UInt8

    def __init__(out self, r: UInt8, g: UInt8, b: UInt8):
        self.r = r
        self.g = g
        self.b = b

    def luminance(self) -> Float32:
        """Compute perceived luminance (sRGB approximation).

        Returns:
            Luminance in [0, 255].
        """
        return (
            0.299 * Float32(self.r)
            + 0.587 * Float32(self.g)
            + 0.114 * Float32(self.b)
        )

    def invert(self) -> Color:
        """Return the bitwise-inverted colour (255 - channel).

        Returns:
            Inverted ``Color``.
        """
        return Color(255 - self.r, 255 - self.g, 255 - self.b)

    def __str__(self) -> String:
        return (
            "rgb("
            + String(Int(self.r))
            + ","
            + String(Int(self.g))
            + ","
            + String(Int(self.b))
            + ")"
        )


# ── Fuzzable for Color ────────────────────────────────────────────────────────


struct FuzzableColor:
    """Generator and minimizer for ``Color``.

    Generates random 8-bit RGB triples.  Minimizes by halving each channel.
    """

    @staticmethod
    def generate(mut rng: Xoshiro256) -> Color:
        """Generate a random ``Color``.

        Args:
            rng: PRNG state (advanced in-place).

        Returns:
            A ``Color`` with uniformly random R, G, B channels.
        """
        return Color(r=rng.next_byte(), g=rng.next_byte(), b=rng.next_byte())

    @staticmethod
    def minimize(value: Color) -> List[Color]:
        """Minimize by halving each channel independently.

        Args:
            value: The colour to simplify.

        Returns:
            A list of colours with smaller channel values.
        """
        var out = List[Color]()
        out.append(Color(0, 0, 0))  # black is the simplest colour
        if value.r > 0:
            out.append(Color(value.r // 2, value.g, value.b))
        if value.g > 0:
            out.append(Color(value.r, value.g // 2, value.b))
        if value.b > 0:
            out.append(Color(value.r, value.g, value.b // 2))
        return out^


# ── Generator / minimizer helpers ─────────────────────────────────────────────


def gen_color(mut rng: Xoshiro256) -> Color:
    return FuzzableColor.generate(rng)


def minimize_color(c: Color) -> List[Color]:
    return FuzzableColor.minimize(c)


# ── Properties ────────────────────────────────────────────────────────────────


def double_invert_is_identity(c: Color) raises -> Bool:
    """Property: invert(invert(c)) == c for all colours."""
    var once = c.invert()
    var twice = once.invert()
    return twice.r == c.r and twice.g == c.g and twice.b == c.b


def luminance_in_range(c: Color) raises -> Bool:
    """Property: luminance is always in [0, 255]."""
    var lum = c.luminance()
    return lum >= 0.0 and lum <= 255.0


def invert_changes_colour(c: Color) raises -> Bool:
    """Property: inverted colour differs from original.

    Note: 255 - channel == channel would require channel == 127.5, impossible
    for integers, so this property always holds for 8-bit channels.
    """
    var inv = c.invert()
    return not (inv.r == c.r and inv.g == c.g and inv.b == c.b)


# ── Main ──────────────────────────────────────────────────────────────────────


def main() raises:
    print("=== Example 3: Custom Fuzzable ===\n")

    print("1. Testing double-invert identity over 3 000 random colours...")
    forall[Color](
        double_invert_is_identity, gen_color, minimize_color, trials=3_000, seed=1
    )
    print("   PASS: invert(invert(c)) == c for all colours\n")

    print("2. Testing luminance stays in [0, 255] over 5 000 colours...")
    forall[Color](
        luminance_in_range, gen_color, minimize_color, trials=5_000, seed=2
    )
    print("   PASS: luminance always in [0, 255]\n")

    print("3. Testing that invert always changes the colour (2 000 trials)...")
    forall[Color](
        invert_changes_colour, gen_color, minimize_color, trials=2_000, seed=3
    )
    print("   PASS: invert always changes the colour\n")

    print("All custom Fuzzable properties hold!")
