"""生成 App 图标与启动页图形。

注意：只在 CI（macOS runner）里跑。手机上跑 Pillow 画大图很容易把宿主 App 顶到内存上限，
所以本地不要执行这个脚本。这里也不做超采样，直接按目标尺寸画，内存占用只有几 MB。
"""
import os
from PIL import Image, ImageDraw

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "DeepSeekChat", "Assets.xcassets")
SIZE = 1024
TOP = (86, 116, 255)
BOTTOM = (54, 76, 214)
BLUE = (77, 107, 254)


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size), bottom)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        draw.line([(0, y), (size, y)], fill=(
            int(top[0] + (bottom[0] - top[0]) * t),
            int(top[1] + (bottom[1] - top[1]) * t),
            int(top[2] + (bottom[2] - top[2]) * t),
        ))
    return img


def draw_whale(size, color):
    """白色鲸鱼剪影，画在透明层上。"""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = size * 0.48, size * 0.52
    w, h = size * 0.56, size * 0.34

    d.ellipse([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], fill=color)

    tail = cx + w * 0.44
    d.polygon([(tail, cy - size * 0.01),
               (tail + size * 0.17, cy - size * 0.15),
               (tail + size * 0.06, cy - size * 0.02)], fill=color)
    d.polygon([(tail, cy + size * 0.02),
               (tail + size * 0.17, cy + size * 0.16),
               (tail + size * 0.06, cy + size * 0.03)], fill=color)

    d.polygon([(cx - w * 0.06, cy + h * 0.30),
               (cx - w * 0.20, cy + h * 0.58),
               (cx + w * 0.09, cy + h * 0.34)], fill=color)

    # 眼睛
    er = size * 0.022
    ex, ey = cx - w * 0.28, cy - h * 0.20
    d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(0, 0, 0, 0))

    # 嘴线
    d.arc([cx - w * 0.44, cy - h * 0.05, cx + w * 0.02, cy + h * 0.66],
          start=40, end=100, fill=(0, 0, 0, 0), width=max(2, int(size * 0.014)))
    return layer


def main():
    icon_dir = os.path.join(BASE, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)
    icon = gradient(SIZE, TOP, BOTTOM).convert("RGBA")
    icon.alpha_composite(draw_whale(SIZE, (255, 255, 255, 255)))
    icon.convert("RGB").save(os.path.join(icon_dir, "icon-1024.png"), optimize=True)
    print("icon ->", os.path.join(icon_dir, "icon-1024.png"))

    splash_dir = os.path.join(BASE, "SplashMark.imageset")
    os.makedirs(splash_dir, exist_ok=True)
    mark = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    mark.alpha_composite(draw_whale(512, (255, 255, 255, 255)))
    mark.save(os.path.join(splash_dir, "splash-mark.png"), optimize=True)
    print("splash ->", os.path.join(splash_dir, "splash-mark.png"))


if __name__ == "__main__":
    main()
