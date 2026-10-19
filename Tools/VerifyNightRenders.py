"""Check real SceneKit output; requires Pillow. Run after --render-lights."""
from pathlib import Path
import sys
from PIL import Image, ImageChops
root = Path(sys.argv[1])
for area in ('asia', 'americas'):
    counts = {}
    for time in ('day', 'night'):
        on = Image.open(root / f'{area}-{time}.png').convert('RGB')
        off = Image.open(root / f'{area}-{time}-off.png').convert('RGB')
        pixels = list(ImageChops.difference(on, off).get_flattened_data())
        changed = [(i % on.width, i // on.width) for i, pixel in enumerate(pixels) if max(pixel) > 10]
        counts[time] = len(changed)
        central = sum((x-on.width/2)**2 + (y-on.height/2)**2 < (on.width/4)**2 for x,y in changed)
        if time == 'day':
            # These fixture views face local noon. The central disk is fully sunlit;
            # a thin night rim is correctly visible because camera and sun aren't aligned.
            assert central == 0, f'{area}: lights in sunlit center / through rear hemisphere'
        else:
            assert central > 100, f'{area}: no lights in the dark central disk'
    print(area, counts)
    assert counts['night'] > 100, f'{area}: no visible night lights'
    assert counts['day'] < max(30, counts['night'] * 0.15), f'{area}: lights leaked into daylight / through rear hemisphere'
print('Day/night rendered-pixel checks passed.')
