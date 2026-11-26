"""Writes the example's Android adaptive-icon layers as VectorDrawables.

Same geometry as make_icons.swift (a 1024 canvas, shield centred at 512),
with y flipped because Android's y axis points down.
"""
import math, sys

out = sys.argv[1]
W = 1024
def P(x, y): return (x, W - y)                     # CG (y-up) -> Android (y-down)
def f(v): return f'{v:.1f}'.rstrip('0').rstrip('.')
def pt(p): return f'{f(p[0])},{f(p[1])}'

# Shield (scale 1, 640 tall), as in make_icons.swift.
w, h, cx = 520, 640, 512
top, bottom = 512 + h/2, 512 - h/2
segs = [
  ('M', [P(cx, top)]),
  ('C', [P(cx + w*.18, top - h*.06), P(cx + w*.36, top - h*.12), P(cx + w/2, top - h*.14)]),
  ('L', [P(cx + w/2, 512 + h*.02)]),
  ('C', [P(cx + w/2, 512 - h*.28), P(cx + w*.22, bottom + h*.1), P(cx, bottom)]),
  ('C', [P(cx - w*.22, bottom + h*.1), P(cx - w/2, 512 - h*.28), P(cx - w/2, 512 + h*.02)]),
  ('L', [P(cx - w/2, top - h*.14)]),
  ('C', [P(cx - w*.36, top - h*.12), P(cx - w*.18, top - h*.06), P(cx, top)]),
]
shield = ''.join(c + ' '.join(pt(p) for p in ps) for c, ps in segs) + 'Z'

# Check mark: a polyline with width 70, round caps and a round join.
pts = [P(392, 522), P(482, 432), P(652, 622)]
r = 35
check_stroke = 'M' + pt(pts[0]) + 'L' + pt(pts[1]) + 'L' + pt(pts[2])

def unit(a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]; l = math.hypot(dx, dy); return dx/l, dy/l
def add(p, v, s): return (p[0] + v[0]*s, p[1] + v[1]*s)
d1, d2 = unit(pts[0], pts[1]), unit(pts[1], pts[2])
n1, n2 = (-d1[1], d1[0]), (-d2[1], d2[0])
cross = d1[0]*d2[1] - d1[1]*d2[0]
# The +n side is the outer side of the bend when cross < 0 (y-down axes).
def miter(sign):
    # Intersection of the two offset lines on side `sign`.
    a, b = add(pts[1], n1, sign*r), add(pts[1], n2, sign*r)
    # a + t*d1 = b + u*d2  -> solve for t
    det = d1[0]*(-d2[1]) - d1[1]*(-d2[0])
    t = ((b[0]-a[0])*(-d2[1]) - (b[1]-a[1])*(-d2[0])) / det
    return add(a, d1, t)
arc = lambda p, sweep: f'A{r},{r} 0 0,{1 - sweep} {pt(p)}'
outer = 1 if cross < 0 else -1
parts = ['M' + pt(add(pts[0], n1, r))]
if outer == 1:
    parts += ['L' + pt(add(pts[1], n1, r)), arc(add(pts[1], n2, r), 1)]
else:
    parts += ['L' + pt(miter(1))]
parts += ['L' + pt(add(pts[2], n2, r)), arc(add(pts[2], n2, -r), 1)]
if outer == -1:
    parts += ['L' + pt(add(pts[1], n2, -r)), arc(add(pts[1], n1, -r), 1)]
else:
    parts += ['L' + pt(miter(-1))]
parts += ['L' + pt(add(pts[0], n1, -r)), arc(add(pts[0], n1, r), 1), 'Z']
check_outline = ''.join(parts)

head = ('<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated from the example\'s icon geometry; see pubspec.yaml. -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp" android:height="108dp"\n'
        f'    android:viewportWidth="{W}" android:viewportHeight="{W}">\n')
open(f'{out}/ic_launcher_foreground.xml', 'w').write(head +
  f'    <path android:fillColor="#FFFFFF" android:pathData="{shield}"/>\n'
  f'    <path android:strokeColor="#00897B" android:strokeWidth="70"\n'
  f'        android:strokeLineCap="round" android:strokeLineJoin="round"\n'
  f'        android:pathData="{check_stroke}"/>\n</vector>\n')
open(f'{out}/ic_launcher_monochrome.xml', 'w').write(head +
  f'    <path android:fillColor="#FFFFFF" android:fillType="evenOdd"\n'
  f'        android:pathData="{shield}{check_outline}"/>\n</vector>\n')
print('cross', cross)
