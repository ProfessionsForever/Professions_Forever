#!/usr/bin/env python3
"""Draws Media/forever-new.tga and Media/forever-changed.tga: the glowing infinity that marks a recipe new in Forever
(gold) or changed in Forever (blue) in the recipe list and the detail panel. Needs Pillow.

    python3 tools/gen_forever_icon.py [preview.png]    also writes both at list sizes on a dark background
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

MEDIA = Path(__file__).resolve().parent.parent / "Media"
SIZE, SCALE = 64, 8  # drawn 8 times larger, then shrunk
# name -> (glow, body, core) colours
ICONS = {
    "forever-new": ((255, 140, 10), (255, 190, 40), (255, 245, 170)),
    "forever-changed": ((20, 120, 255), (70, 170, 255), (215, 240, 255)),
}


def stroke(big, width):
    """The figure eight (a lemniscate, a little taller than Bernoulli's) as a mask, `width` thick."""
    mask = Image.new("L", (big, big), 0)
    pen = ImageDraw.Draw(mask)
    reach, r = big * 0.40, width / 2
    for i in range(2000):
        t = 2 * math.pi * i / 2000
        s, c = math.sin(t), math.cos(t)
        x, y = big / 2 + reach * c / (1 + s * s), big / 2 + reach * 1.25 * s * c / (1 + s * s)
        pen.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return mask


def layer(big, mask, rgb, strength=1.0):
    image = Image.new("RGBA", (big, big), rgb + (0,))
    image.putalpha(mask.point(lambda v: int(min(255, v * strength))))
    return image


def draw(glow, body, core):
    big = SIZE * SCALE
    image = Image.new("RGBA", (big, big), glow + (0,))
    for mask, rgb, strength in (
        (stroke(big, big * 0.11).filter(ImageFilter.GaussianBlur(big * 0.055)), glow, 1.5),
        (stroke(big, big * 0.105).filter(ImageFilter.GaussianBlur(big * 0.012)), body, 1.0),
        (stroke(big, big * 0.045).filter(ImageFilter.GaussianBlur(big * 0.012)), core, 1.0),
    ):
        image = Image.alpha_composite(image, layer(big, mask, rgb, strength))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    icons = {name: draw(*colours) for name, colours in ICONS.items()}
    for name, image in icons.items():
        image.save(MEDIA / f"{name}.tga")
        print(f"{SIZE}x{SIZE} -> {MEDIA / name}.tga")
    if len(sys.argv) > 1:
        sizes = (64, 32, 18, 14, 12)
        preview = Image.new("RGBA", (sum(sizes) + 10 * (len(sizes) + 1), 2 * 74), (22, 22, 26, 255))
        for row, image in enumerate(icons.values()):
            x = 10
            for size in sizes:
                preview.alpha_composite(image.resize((size, size), Image.LANCZOS), (x, row * 74 + (74 - size) // 2))
                x += size + 10
        preview.save(sys.argv[1])


if __name__ == "__main__":
    main()
