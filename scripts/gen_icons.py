from PIL import Image, ImageDraw
import os

BLUE = (46, 109, 212, 255)
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)

os.makedirs('assets/icon', exist_ok=True)


def draw_stethoscope(draw, cx, cy, color):
    """Stylised stethoscope: chest-piece ring + plus + tube + earpiece."""
    r, lw = 200, 36
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=lw)

    arm, thick = 110, 28
    draw.rectangle([cx - thick, cy - arm, cx + thick, cy + arm], fill=color)
    draw.rectangle([cx - arm, cy - thick, cx + arm, cy + thick], fill=color)

    tube_top = cy - r - 80
    draw.rectangle([cx - 18, tube_top, cx + 18, cy - r], fill=color)

    er = 28
    draw.ellipse([cx - er, tube_top - er * 2, cx + er, tube_top + er], fill=color)


# 1. Full launcher icon (1024x1024) - blue bg, white circle, blue stethoscope
size = 1024
cx = cy = size // 2
img = Image.new('RGBA', (size, size), BLUE)
draw = ImageDraw.Draw(img)
rc = 340
draw.ellipse([cx - rc, cy - rc, cx + rc, cy + rc], fill=WHITE)
draw_stethoscope(draw, cx, cy + 40, BLUE)
img.save('assets/icon/icon.png')
print('assets/icon/icon.png generated')

# 2. Adaptive icon foreground (1024x1024) - transparent bg, white stethoscope
fg = Image.new('RGBA', (size, size), TRANSPARENT)
draw_stethoscope(ImageDraw.Draw(fg), cx, cy + 40, WHITE)
fg.save('assets/icon/icon_foreground.png')
print('assets/icon/icon_foreground.png generated')

# 3. Native splash logo (512x512) - transparent bg, frosted circle + white stethoscope
s = 512
scx = scy = s // 2
splash = Image.new('RGBA', (s, s), TRANSPARENT)
sdraw = ImageDraw.Draw(splash)

# Frosted circle (white at 15% opacity)
sr = 170
sdraw.ellipse([scx - sr, scy - sr, scx + sr, scy + sr], fill=(255, 255, 255, 38))

# Scaled stethoscope
scale = 0.46
r2 = int(200 * scale)
lw2 = max(int(36 * scale), 3)
arm2 = int(110 * scale)
thick2 = max(int(28 * scale), 2)
tube_top2 = scy - r2 - int(80 * scale)
er2 = max(int(28 * scale), 4)
off = int(40 * scale)

sdraw.ellipse([scx - r2, scy + off - r2, scx + r2, scy + off + r2], outline=WHITE, width=lw2)
sdraw.rectangle([scx - thick2, scy + off - arm2, scx + thick2, scy + off + arm2], fill=WHITE)
sdraw.rectangle([scx - arm2, scy + off - thick2, scx + arm2, scy + off + thick2], fill=WHITE)
sdraw.rectangle([scx - int(18 * scale), tube_top2, scx + int(18 * scale), scy + off - r2], fill=WHITE)
sdraw.ellipse([scx - er2, tube_top2 - er2 * 2, scx + er2, tube_top2 + er2], fill=WHITE)

splash.save('assets/icon/splash_logo.png')
print('assets/icon/splash_logo.png generated')

print('\nAll assets generated.')
