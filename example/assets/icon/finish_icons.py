"""Copies the iOS icons from the masters and losslessly shrinks every icon PNG.

Run from example/ after make_icons.swift and flutter_launcher_icons:
    python3 assets/icon/finish_icons.py
Needs Pillow (pip install pillow).
"""
import os
from PIL import Image, ImageChops

BRAND = (0x00, 0x89, 0x7B)  # teal
IOS = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'


def save_ios_icons():
    # Light and tinted icons must be opaque (the App Store rejects alpha).
    Image.open('assets/icon/icon.png').convert('RGB').save(f'{IOS}/Icon-App-1024x1024@1x.png')
    Image.open('assets/icon/icon_tinted.png').convert('RGB').save(f'{IOS}/Icon-App-Tinted-1024x1024@1x.png')
    # Dark icon: teal at varying opacity. Using exactly one RGB value keeps it
    # under 256 colours, so it can be stored losslessly as a palette PNG.
    alpha = Image.open('assets/icon/icon_dark.png').convert('RGBA').getchannel('A')
    Image.merge('RGBA', (*Image.new('RGB', alpha.size, BRAND).split(), alpha)).save(
        f'{IOS}/Icon-App-Dark-1024x1024@1x.png')


def shrink(path):
    """Stores [path] as a palette PNG if that's exact and smaller."""
    src = Image.open(path)
    rgba = src.convert('RGBA')
    colors = rgba.getcolors(256)
    if colors is None:
        return f'kept (over 256 colours)   {path}'
    palette = [c for _, c in colors]
    index = {c: i for i, c in enumerate(palette)}
    p = Image.new('P', rgba.size)
    p.putdata([index[c] for c in rgba.getdata()])
    p.putpalette([v for c in palette for v in c[:3]])
    opaque = all(c[3] == 255 for c in palette)
    tmp = path + '.tmp.png'
    if opaque:
        p.save(tmp, optimize=True)
    else:
        p.save(tmp, optimize=True, transparency=bytes(c[3] for c in palette))
    same = ImageChops.difference(rgba, Image.open(tmp).convert('RGBA')).getbbox() is None
    before, after = os.path.getsize(path), os.path.getsize(tmp)
    if same and after < before:
        os.replace(tmp, path)
        return f'{before / 1024:5.1f} -> {after / 1024:5.1f} KB  {path}'
    os.remove(tmp)
    return f'kept                      {path}'


if __name__ == '__main__':
    save_ios_icons()
    targets = [f'{IOS}/{f}' for f in sorted(os.listdir(IOS)) if f.endswith('.png')]
    targets += ['web/favicon.png'] + [f'web/icons/{f}' for f in sorted(os.listdir('web/icons'))]
    res = 'android/app/src/main/res'
    targets += [f'{res}/{d}/ic_launcher.png' for d in sorted(os.listdir(res)) if d.startswith('mipmap-') and os.path.exists(f'{res}/{d}/ic_launcher.png')]
    for t in targets:
        print(shrink(t))
