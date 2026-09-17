"""Export undistorted COLMAP PINHOLE cameras to texrecon .cam; no reconstruction."""
import os
import sys
from pathlib import Path
import numpy as np

from colmap_model_io import read_model, qvec2rotmat

def main():
    workspace, output = map(lambda s: Path(s).resolve(), sys.argv[1:])
    cameras, images, _ = read_model(str(workspace / 'sparse'), '.bin')
    records = []
    for im in images.values():
        c = cameras[im.camera_id]
        if c.model != 'PINHOLE':
            raise ValueError('Expected image_undistorter PINHOLE output')
        if Path(im.name).name != im.name:
            raise ValueError('This dataset exporter requires flat image names')
        src = workspace / 'images' / im.name
        if not src.is_file():
            raise FileNotFoundError(src)
        fx, fy, cx, cy = c.params
        aspect = fy / fx
        landscape = c.width * aspect >= c.height
        focal = fx / c.width if landscape else fy / c.height
        recovered = [focal*c.width, focal*c.width*aspect] if landscape else [focal*c.height/aspect, focal*c.height]
        np.testing.assert_allclose(recovered, [fx, fy], rtol=1e-12)
        ext = np.r_[im.tvec, qvec2rotmat(im.qvec).reshape(-1)]
        intr = [focal, 0, 0, aspect, cx/c.width, cy/c.height]
        records.append((src, Path(im.name).with_suffix('.cam').name, ext, intr))
    if len({r[1] for r in records}) != len(records):
        raise ValueError('Duplicate camera filenames')
    output.mkdir(exist_ok=False)
    for src, name, ext, intr in records:
        (output/src.name).symlink_to(os.path.relpath(src, output))
        (output/name).write_text(' '.join(format(v,'.17g') for v in ext)+'\n'+' '.join(format(v,'.17g') for v in intr)+'\n')
    print('Exported',len(records),'cameras; calibration round-trip passed')

if __name__ == '__main__':
    main()
