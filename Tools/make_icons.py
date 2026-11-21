"""生成 App 图标与启动页图形。

素材：`Design/AppIcon-1024.png`（DeepSeek 官方 App 图标原图，1024×1024，无透明通道）。
只做缩放/加圆角这类内存开销很小的操作 —— 手机上跑 Pillow 画超大图会把宿主 App 顶到内存上限，
所以不要本地执行；CI 里跑一次即可。

没有素材时退回到程序化绘制的蓝色渐变 + 白鲸鱼。
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "DeepSeekChat", "Assets.xcassets")
SOURCE = os.path.join(ROOT, "Design", "AppIcon-1024.png")
SIZE = 1024

TOP = (86, 116, 255)
BOTTOM = (54, 76, 214)


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


def rounded(img, radius_ratio=0.2237):
    """裁成圆角正方形（透明底），用于启动页上的品牌图形。"""
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


def main():
    icon_dir = os.path.join(BASE, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    if os.path.exists(SOURCE):
        art = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
        print("source ->", SOURCE)
    else:
        art = gradient(SIZE, TOP, BOTTOM)
        print("source -> fallback gradient")

    # App Store 要求图标不含 alpha 通道
    art.save(os.path.join(icon_dir, "icon-1024.png"), optimize=True)
    print("icon ->", os.path.join(icon_dir, "icon-1024.png"))

    splash_dir = os.path.join(BASE, "SplashMark.imageset")
    os.makedirs(splash_dir, exist_ok=True)
    mark = rounded(art.resize((512, 512), Image.LANCZOS))
    mark.save(os.path.join(splash_dir, "splash-mark.png"), optimize=True)
    print("splash ->", os.path.join(splash_dir, "splash-mark.png"))


if __name__ == "__main__":
    main()
