#!/usr/bin/env python3
"""Generate the SimulationOS ("SimOS") branding assets.

Everything SimOS-branded is drawn "in binary": the wordmark is a dot matrix
whose lit cells are 0/1 digits, and the caption is the ASCII encoding of the
name itself:

    S        i        m        O        S
    01010011 01101001 01101101 01001111 01010011

Outputs (all committed; re-run this script to regenerate them):

    airootfs/usr/share/backgrounds/simulationos/simos-winter.png
    airootfs/usr/share/backgrounds/simulationos/simos-fire.png
    airootfs/usr/share/backgrounds/simulationos/simos-throne.png
    airootfs/usr/share/pixmaps/simulationos.svg            (application icon)
    airootfs/usr/share/simulationos/fastfetch/logo.txt     (fastfetch logo)
    airootfs/usr/share/simulationos/calamares/branding/simulationos/{logo,welcome,icon}.png
    syslinux/splash.png                                    (BIOS boot menu)

The three wallpapers are original artwork on fantasy themes in the spirit of
"Game of Thrones" - a wall of ice under a winter moon, a dragon's eye in
fire, and a throne forged from swords. They contain no logos, sigils, stills
or text from the books or the series.

Requires Pillow (a development-time dependency only; nothing here runs during
the ISO build). Output is deterministic: fixed seeds, no timestamps.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 2560, 1440
CELL_W, CELL_H = 10, 16          # one binary digit per cell
COLS, ROWS = W // CELL_W, H // CELL_H
NAME = "SimOS"
NAME_BITS = " ".join(f"{ord(c):08b}" for c in NAME)

# 5x7 dot-matrix glyphs for the wallpaper/logo wordmark.
GLYPHS_7 = {
    "S": [".###.", "#...#", "#....", ".###.", "....#", "#...#", ".###."],
    "i": [".#.", "...", "##.", ".#.", ".#.", ".#.", "###"],
    "m": [".......", ".......", "###.##.", "#..#..#", "#..#..#", "#..#..#", "#..#..#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
}
# 5-row glyphs for the terminal logo, where every cell is two characters wide.
GLYPHS_5 = {
    "S": [".###", "#...", ".##.", "...#", "###."],
    "i": ["#", ".", "#", "#", "#"],
    "m": [".....", "##.#.", "#.#.#", "#.#.#", "#.#.#"],
    "O": [".##.", "#..#", "#..#", "#..#", ".##."],
}

MONO_FONTS = [
    ("/System/Library/Fonts/Menlo.ttc", 1),
    ("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf", 0),
    ("/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf", 0),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 0),
]


def mono(size):
    for path, index in MONO_FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size, index=index)
    sys.exit("no monospace font found; add one to MONO_FONTS")


def wordmark(glyphs, gap=1):
    """Return the name as a list of equal-length rows of '#'/'.'."""
    rows = len(next(iter(glyphs.values())))
    out = [""] * rows
    for n, ch in enumerate(NAME):
        for r in range(rows):
            out[r] += ("." * gap if n else "") + glyphs[ch][r]
    return out


# --------------------------------------------------------------------- scenes
# Each scene paints an 8-bit intensity image; the palette turns intensity into
# colour. Shapes are drawn large and soft because the final picture is sampled
# once per digit cell.

def vgradient(top, bottom):
    g = Image.linear_gradient("L").resize((W, H))
    return g.point(lambda v: int(top + (bottom - top) * v / 255))


def scene_winter(rng):
    img = vgradient(26, 8)
    # Moon with a wide halo.
    mx, my = int(W * 0.80), int(H * 0.20)
    halo = Image.new("L", (W, H), 0)
    hd = ImageDraw.Draw(halo)
    hd.ellipse([mx - 420, my - 420, mx + 420, my + 420], fill=70)
    hd.ellipse([mx - 230, my - 230, mx + 230, my + 230], fill=120)
    img = ImageChops.add(img, halo.filter(ImageFilter.GaussianBlur(120)))
    d = ImageDraw.Draw(img)
    d.ellipse([mx - 120, my - 120, mx + 120, my + 120], fill=250)
    d.ellipse([mx - 60, my - 150, mx + 150, my + 60], fill=40)  # crescent bite

    # The wall of ice: a colossal cliff across the whole horizon.
    top = int(H * 0.44)
    base = int(H * 0.80)
    crest = []
    x = 0
    y = top
    while x <= W:
        crest.append((x, y))
        x += rng.randint(30, 110)
        y = max(top - 40, min(top + 40, y + rng.randint(-22, 22)))
    crest.append((W, y))
    d.polygon(crest + [(W, base), (0, base)], fill=96)
    # Vertical ice striations, brighter near the crest.
    for _ in range(520):
        sx = rng.randint(0, W)
        sy = top + rng.randint(-20, 60)
        length = rng.randint(80, base - top)
        shade = rng.randint(110, 215)
        d.line([(sx, sy), (sx + rng.randint(-6, 6), min(base, sy + length))], fill=shade, width=rng.randint(2, 9))
    # Snow-lit rim on the crest.
    d.line(crest, fill=245, width=7)
    # Darkness at the foot of the wall and a forest of pines in front of it.
    foot = Image.new("L", (W, H), 0)
    ImageDraw.Draw(foot).rectangle([0, base - 120, W, H], fill=150)
    img = ImageChops.subtract(img, foot.filter(ImageFilter.GaussianBlur(70)))
    d = ImageDraw.Draw(img)
    x = -40
    while x < W + 40:
        height = rng.randint(140, 330)
        width = int(height * rng.uniform(0.30, 0.42))
        ground = H - rng.randint(0, 50)
        tiers = 5
        for t in range(tiers):
            ty = ground - height + int(height * t / tiers * 0.8)
            tw = int(width * (t + 1.6) / tiers)
            d.polygon([(x, ty), (x - tw, ty + height // 3), (x + tw, ty + height // 3)], fill=rng.randint(18, 44))
        x += rng.randint(45, 120)
    return img.filter(ImageFilter.GaussianBlur(3))


def scene_fire(rng):
    img = vgradient(6, 30)
    cx, cy = W // 2, int(H * 0.40)
    rx, ry = 760, 330

    # Heat rising from below.
    heat = Image.new("L", (W, H), 0)
    hd = ImageDraw.Draw(heat)
    for _ in range(90):
        fx = rng.randint(0, W)
        fh = rng.randint(120, 520)
        fw = rng.randint(30, 110)
        hd.polygon([(fx - fw, H), (fx + fw, H), (fx + rng.randint(-60, 60), H - fh)], fill=rng.randint(90, 200))
    img = ImageChops.add(img, heat.filter(ImageFilter.GaussianBlur(38)))

    # Scaled hide around the eye: overlapping arcs fading with distance.
    scales = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(scales)
    for ring in range(1, 9):
        count = 18 + ring * 6
        for k in range(count):
            a = 2 * math.pi * k / count + ring * 0.21
            px = cx + math.cos(a) * (rx + ring * 105)
            py = cy + math.sin(a) * (ry + ring * 92)
            r = 62 + ring * 5
            sd.arc([px - r, py - r, px + r, py + r], math.degrees(a) - 70, math.degrees(a) + 70,
                   fill=max(26, 120 - ring * 12), width=9)
    img = ImageChops.add(img, scales.filter(ImageFilter.GaussianBlur(3)))

    # The eye: an almond lens (intersection of two circles).
    def lens(shrink=0):
        a = Image.new("L", (W, H), 0)
        b = Image.new("L", (W, H), 0)
        big = 1250 - shrink
        off = big - (ry - shrink)
        ImageDraw.Draw(a).ellipse([cx - big, cy - off - big, cx + big, cy - off + big], fill=255)
        ImageDraw.Draw(b).ellipse([cx - big, cy + off - big, cx + big, cy + off + big], fill=255)
        return ImageChops.multiply(a, b)

    lid = lens(-34).filter(ImageFilter.GaussianBlur(6))
    img = ImageChops.subtract(img, lid.point(lambda v: v // 2))   # dark eyelid rim
    eye = lens()
    iris = Image.new("L", (W, H), 0)
    idr = ImageDraw.Draw(iris)
    for r in range(ry + 60, 0, -6):                                # radial glow
        idr.ellipse([cx - r * 1.5, cy - r, cx + r * 1.5, cy + r], fill=int(120 + 135 * (1 - r / (ry + 60))))
    for _ in range(420):                                           # iris fibres
        a = rng.uniform(0, 2 * math.pi)
        r0, r1 = rng.uniform(40, 120), rng.uniform(220, 560)
        idr.line([(cx + math.cos(a) * r0 * 1.5, cy + math.sin(a) * r0),
                  (cx + math.cos(a) * r1 * 1.5, cy + math.sin(a) * r1)],
                 fill=rng.randint(150, 255), width=rng.randint(2, 6))
    iris = iris.filter(ImageFilter.GaussianBlur(2))
    img = Image.composite(iris, img, eye.filter(ImageFilter.GaussianBlur(2)))
    # Vertical slit pupil.
    pupil = Image.new("L", (W, H), 0)
    pd = ImageDraw.Draw(pupil)
    pd.polygon([(cx, cy - ry + 26), (cx + 74, cy), (cx, cy + ry - 26), (cx - 74, cy)], fill=255)
    pd.ellipse([cx - 62, cy - 190, cx + 62, cy + 190], fill=255)
    img = Image.composite(Image.new("L", (W, H), 0), img, pupil.filter(ImageFilter.GaussianBlur(5)))
    return img.filter(ImageFilter.GaussianBlur(2))


def scene_throne(rng):
    img = vgradient(20, 6)
    cx = W // 2
    seat_y = int(H * 0.47)

    # A shaft of light from a high window.
    shaft = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shaft).polygon([(cx - 170, 0), (cx + 170, 0), (cx + 820, H), (cx - 820, H)], fill=120)
    img = ImageChops.add(img, shaft.filter(ImageFilter.GaussianBlur(90)))
    d = ImageDraw.Draw(img)

    def sword(x0, y0, angle, length, shade):
        """A blade from (x0, y0) pointing along `angle` (0 = straight up)."""
        ux, uy = math.sin(angle), -math.cos(angle)       # along the blade
        vx, vy = -uy, ux                                 # across the blade
        half = max(7, length * 0.022)
        tip = (x0 + ux * length, y0 + uy * length)
        neck = (x0 + ux * length * 0.90, y0 + uy * length * 0.90)
        d.polygon([(x0 - vx * half, y0 - vy * half), (neck[0] - vx * half, neck[1] - vy * half), tip,
                   (neck[0] + vx * half, neck[1] + vy * half), (x0 + vx * half, y0 + vy * half)], fill=shade)
        d.line([(x0, y0), tip], fill=min(255, shade + 60), width=3)           # fuller
        gx, gy = x0 + ux * length * 0.10, y0 + uy * length * 0.10           # crossguard
        guard = half * 4.2
        d.line([(gx - vx * guard, gy - vy * guard), (gx + vx * guard, gy + vy * guard)],
               fill=min(255, shade + 30), width=int(half * 1.3))
        d.ellipse([x0 - half * 1.5, y0 - half * 1.5, x0 + half * 1.5, y0 + half * 1.5], fill=shade)  # pommel

    # The throne's back: a fan of blades, long in the middle, in three layers.
    for layer, (count, spread, lmin, lmax, lo, hi) in enumerate(
            [(46, 1.42, 470, 720, 78, 140), (34, 1.20, 400, 640, 128, 196), (22, 0.92, 320, 540, 176, 250)]):
        for k in range(count):
            t = (k + rng.uniform(-0.3, 0.3)) / (count - 1) * 2 - 1
            angle = t * spread + rng.uniform(-0.05, 0.05)
            length = rng.uniform(lmin, lmax) * (1.0 - 0.42 * abs(t))
            x0 = cx + t * (300 - layer * 40) + rng.uniform(-18, 18)
            y0 = seat_y + 70 - abs(t) * 60 + rng.uniform(-20, 30)
            sword(x0, y0, angle, length, rng.randint(lo, hi))

    # Seat, arm rests and the dais steps, cut out in shadow.
    d.polygon([(cx - 250, seat_y - 20), (cx + 250, seat_y - 20), (cx + 320, seat_y + 170), (cx - 320, seat_y + 170)], fill=30)
    d.polygon([(cx - 200, seat_y - 250), (cx + 200, seat_y - 250), (cx + 240, seat_y - 20), (cx - 240, seat_y - 20)], fill=22)
    d.rectangle([cx - 360, seat_y - 90, cx - 250, seat_y + 170], fill=44)
    d.rectangle([cx + 250, seat_y - 90, cx + 360, seat_y + 170], fill=44)
    d.line([(cx - 200, seat_y - 250), (cx + 200, seat_y - 250)], fill=210, width=6)
    d.line([(cx - 360, seat_y - 90), (cx - 250, seat_y - 90)], fill=190, width=6)
    d.line([(cx + 250, seat_y - 90), (cx + 360, seat_y - 90)], fill=190, width=6)
    d.line([(cx - 250, seat_y - 20), (cx + 250, seat_y - 20)], fill=150, width=5)
    for step in range(4):
        wstep = 430 + step * 190
        y = seat_y + 170 + step * 62
        d.rectangle([cx - wstep, y, cx + wstep, y + 62], fill=74 - step * 12)
        d.line([(cx - wstep, y), (cx + wstep, y)], fill=200 - step * 26, width=5)
    return img.filter(ImageFilter.GaussianBlur(2))


SCENES = {
    # name: (painter, shadow colour, mid colour, highlight colour, wordmark colour, wordmark row)
    "winter": (scene_winter, (2, 6, 16),  (30, 110, 190), (214, 244, 255), (235, 250, 255), 0.215),
    "fire":   (scene_fire,   (8, 1, 0),   (200, 48, 6),   (255, 214, 96),  (255, 244, 214), 0.690),
    "throne": (scene_throne, (5, 5, 7),   (168, 150, 120), (255, 222, 150), (255, 236, 180), 0.700),
}


def render_wallpaper(name):
    painter, shadow, mid, high, mark_rgb, mark_at = SCENES[name]
    rng = random.Random(f"simos-{name}")
    scene = painter(rng)

    # Background: the scene itself, dimmed, so shapes read between the digits.
    base = ImageOps.colorize(scene.filter(ImageFilter.GaussianBlur(10)), shadow, high, mid)
    base = Image.blend(Image.new("RGB", (W, H), shadow), base, 0.34)

    grid = scene.resize((COLS, ROWS), Image.BOX)
    lut = ImageOps.colorize(Image.frombytes("L", (256, 1), bytes(range(256))), shadow, high, mid).load()

    # Wordmark placement: every dot-matrix pixel is a 3x3 block of digit cells.
    rows7 = wordmark(GLYPHS_7, gap=2)
    scale = 3
    mark_w, mark_h = len(rows7[0]) * scale, len(rows7) * scale
    col0 = (COLS - mark_w) // 2
    row0 = int(ROWS * mark_at)
    lit = set()
    for r, line in enumerate(rows7):
        for c, ch in enumerate(line):
            if ch == "#":
                for dy in range(scale):
                    for dx in range(scale):
                        lit.add((col0 + c * scale + dx, row0 + r * scale + dy))
    # Caption: the name in ASCII binary, centred under the wordmark.
    cap_row = row0 + mark_h + 3
    cap_col = (COLS - len(NAME_BITS)) // 2
    caption = {(cap_col + i, cap_row): ch for i, ch in enumerate(NAME_BITS) if ch != " "}
    # Keep the area around the wordmark calm so it stays legible.
    quiet = (col0 - 5, row0 - 3, col0 + mark_w + 5, cap_row + 3)

    digits = Image.new("RGB", (W, H), (0, 0, 0))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    dd, gd = ImageDraw.Draw(digits), ImageDraw.Draw(glow)
    font = mono(15)
    gpx = grid.load()
    for row in range(ROWS):
        for col in range(COLS):
            x, y = col * CELL_W + 1, row * CELL_H - 1
            if (col, row) in lit:
                dd.text((x, y), rng.choice("01"), font=font, fill=mark_rgb)
                gd.rectangle([x - 1, y + 1, x + CELL_W, y + CELL_H], fill=mark_rgb)
                continue
            if (col, row) in caption:
                dd.text((x, y), caption[(col, row)], font=font, fill=mark_rgb)
                gd.text((x, y), caption[(col, row)], font=font, fill=mark_rgb)
                continue
            v = gpx[col, row]
            v = min(255, int(v * rng.uniform(0.72, 1.18)) + rng.randint(0, 10))
            if quiet[0] <= col < quiet[2] and quiet[1] <= row < quiet[3]:
                v = int(v * 0.30)
            if rng.random() < 0.012:                      # snow / embers / sparks
                v = min(255, v + rng.randint(70, 170))
            if v < 12:
                continue
            dd.text((x, y), rng.choice("01"), font=font, fill=lut[v, 0])
            if v > 150:
                gd.text((x, y), "1", font=font, fill=lut[v, 0])

    bloom = glow.filter(ImageFilter.GaussianBlur(14)).point(lambda p: int(p * 0.75))
    out = ImageChops.add(ImageChops.add(base, bloom), digits)
    # Vignette.
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse([-W * 0.18, -H * 0.28, W * 1.18, H * 1.28], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(260)).point(lambda p: 90 + int(p * 165 / 255))
    out = ImageChops.multiply(out, Image.merge("RGB", (vig, vig, vig)))
    return out


# ------------------------------------------------------------------ logo marks
def render_mark(rows, cell, bg, on, off, pad, caption=True, radius=0):
    """Dot-matrix `rows` drawn with digits: lit cells bright, unlit cells dim."""
    cols, nrows = len(rows[0]), len(rows)
    cw, ch = cell, int(cell * 1.6)
    width = cols * cw + pad * 2
    height = nrows * ch + pad * 2 + (ch * 2 if caption else 0)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, width - 1, height - 1], radius=radius, fill=bg)
    font = mono(int(cell * 1.45))
    for r, line in enumerate(rows):
        for c, chv in enumerate(line):
            x, y = pad + c * cw + cw * 0.08, pad + r * ch - ch * 0.08
            d.text((x, y), "1" if chv == "#" else "0", font=font, fill=on if chv == "#" else off)
    if caption:
        small = mono(max(8, int(cols * cw / len(NAME_BITS) * 1.55)))
        tw = d.textlength(NAME_BITS, font=small)
        d.text(((width - tw) / 2, pad + nrows * ch + ch * 0.45), NAME_BITS, font=small, fill=on)
    return img


def write_icon_svg(path):
    """Application icon: the 'S' of SimOS as a 5x7 matrix of binary digits."""
    rows = GLYPHS_7["S"]
    cw, ch, ox, oy = 36, 30, 38, 23
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">',
        '  <!-- SimulationOS icon: the S of "SimOS" as binary digits. Generated by scripts/make-branding.py -->',
        '  <defs>',
        '    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">',
        '      <stop offset="0" stop-color="#7fe3ff"/>',
        '      <stop offset="1" stop-color="#1793d1"/>',
        '    </linearGradient>',
        '  </defs>',
        '  <rect width="256" height="256" rx="48" fill="#0b0e13"/>',
        '  <g font-family="\'JetBrainsMono Nerd Font\', \'JetBrains Mono\', \'DejaVu Sans Mono\', monospace" '
        'font-weight="700" font-size="34" text-anchor="middle">',
    ]
    for r, line in enumerate(rows):
        for c, chv in enumerate(line):
            x, y = ox + c * cw + cw / 2, oy + r * ch + ch
            if chv == "#":
                parts.append(f'    <text x="{x:g}" y="{y:g}" fill="url(#g)">1</text>')
            else:
                parts.append(f'    <text x="{x:g}" y="{y:g}" fill="#1c2733">0</text>')
    parts += ["  </g>", "</svg>", ""]
    with open(path, "w") as fh:
        fh.write("\n".join(parts))


def write_fastfetch_logo(path):
    """Terminal logo: $1 = lit digits, $2 = unlit digits, $3 = caption."""
    rng = random.Random("simos-fastfetch")
    rows = wordmark(GLYPHS_5, gap=1)
    blank = "." * len(rows[0])
    lines = []
    for line in [blank] + rows + [blank]:
        out, colour = "", None
        for chv in line:
            want = "$1" if chv == "#" else "$2"
            if want != colour:
                out += want
                colour = want
            out += "11" if chv == "#" else rng.choice(["00", "01", "10", "00"])
        lines.append(out)
    lines.append("$3" + NAME_BITS)
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def save(img, rel, **kw):
    path = os.path.join(REPO, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True, **kw)
    print(f"wrote {rel} ({os.path.getsize(path) // 1024} KiB, {img.size[0]}x{img.size[1]})")


def main():
    only = set(sys.argv[1:])
    for name in SCENES:
        if only and name not in only:
            continue
        save(render_wallpaper(name), f"airootfs/usr/share/backgrounds/simulationos/simos-{name}.png")
    if only and "marks" not in only:
        return

    bg, on, off = (11, 14, 19, 255), (96, 214, 255, 255), (30, 42, 56, 255)
    word = wordmark(GLYPHS_7, gap=2)
    brand = "airootfs/usr/share/simulationos/calamares/branding/simulationos"
    save(render_mark(word, 22, (0, 0, 0, 0), on, off, 18), f"{brand}/logo.png")
    # The installer's welcome page has a light background: darker "on" digits
    # and barely-there "off" digits keep the word readable there.
    save(render_mark(word, 22, (0, 0, 0, 0), (14, 108, 168, 255), (206, 214, 222, 255), 18), f"{brand}/welcome.png")
    save(render_mark(GLYPHS_7["S"], 30, bg, on, off, 34, caption=False, radius=44).resize((256, 256), Image.LANCZOS),
         f"{brand}/icon.png")

    # BIOS boot-menu splash: syslinux wants exactly 640x480.
    splash = Image.new("RGB", (640, 480), (11, 14, 19))
    mark = render_mark(word, 12, (0, 0, 0, 0), on, off, 8)
    splash.paste(mark, ((640 - mark.size[0]) // 2, 40), mark)
    save(splash, "syslinux/splash.png")

    for rel, writer in (("airootfs/usr/share/pixmaps/simulationos.svg", write_icon_svg),
                        ("airootfs/usr/share/simulationos/fastfetch/logo.txt", write_fastfetch_logo)):
        path = os.path.join(REPO, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        writer(path)
        print(f"wrote {rel}")


if __name__ == "__main__":
    main()
