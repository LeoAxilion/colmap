"""Import an OPENCV COLMAP sparse model into an initialized ODM dataset.

Run inside the existing ODX container, after its dataset/metadata setup.
Only similarity alignment to photo GPS is performed; no bundle adjustment.
"""

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from opensfm import align, dataset, pygeometry, pymap, reconstruction_helpers, types

from colmap_model_io import read_model, qvec2rotmat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model")
    parser.add_argument("opensfm")
    args = parser.parse_args()
    out = Path(args.opensfm)
    if (out / "reconstruction.json").exists():
        raise FileExistsError("Refusing to replace an existing reconstruction")
    if not (out / "image_list.txt").exists() or not (out / "exif").is_dir():
        # Use the container's own dataset loader and GPS/EXIF initialization.
        sys.path.insert(0, "/code")
        from opendm import config
        from opendm.osfm import OSFMContext
        from stages.dataset import ODMLoadDatasetStage

        project = out.parent
        odm_args = config.config([
            "--project-path", str(project.parent), project.name,
            "--fast-orthophoto", "--skip-report", "--camera-lens", "brown",
            "--max-concurrency", "8", "--no-gpu", "--orthophoto-resolution", "1",
        ])
        odm_args.project_path = str(project)
        outputs = {}
        ODMLoadDatasetStage("dataset", odm_args, progress=5.0).process(odm_args, outputs)
        reconstruction = outputs["reconstruction"]
        context = OSFMContext(str(out))
        context.setup(odm_args, str(project / "images"), reconstruction)
        context.photos_to_metadata(reconstruction.photos, False, 0, odm_args.gps_accuracy)
    cameras, images, points = read_model(args.model, ".bin")
    data = dataset.DataSet(str(out))
    rec = types.Reconstruction()
    rec.reference = data.load_reference()
    tracks = pymap.TracksManager()
    for camera in cameras.values():
        if camera.model != "OPENCV":
            raise ValueError(f"Expected OPENCV, got {camera.model}")
        fx, fy, cx, cy, k1, k2, p1, p2 = camera.params
        scale = max(camera.width, camera.height)
        cam = pygeometry.Camera.create_brown(
            fx / scale, fy / fx,
            np.array([(cx - camera.width / 2) / scale,
                      (cy - camera.height / 2) / scale]),
            np.array([k1, k2, 0, p1, p2]),
        )
        cam.id, cam.width, cam.height = str(camera.id), camera.width, camera.height
        rec.add_camera(cam)
    for point in points.values():
        p = rec.create_point(str(point.id), point.xyz)
        p.color = point.rgb
    max_projection_difference = 0.0
    residuals = []
    sample_projections = {}
    for index, im in enumerate(images.values()):
        cam = cameras[im.camera_id]
        scale = max(cam.width, cam.height)
        rot = qvec2rotmat(im.qvec)
        rvec = cv2.Rodrigues(rot)[0].ravel()
        shot = rec.create_shot(im.name, str(im.camera_id), pygeometry.Pose(rvec, im.tvec))
        shot.metadata = reconstruction_helpers.get_image_metadata(data, im.name)
        valid = np.flatnonzero(im.point3D_ids >= 0)
        for j in valid:
            pid = int(im.point3D_ids[j])
            rgb = points[pid].rgb
            xy = (im.xys[j] - np.array([cam.width, cam.height]) / 2) / scale
            obs = pymap.Observation(float(xy[0]), float(xy[1]), 1 / scale,
                                    int(rgb[0]), int(rgb[1]), int(rgb[2]), int(j))
            tracks.add_observation(im.name, str(pid), obs)
        # Independently check camera mapping against OpenCV's OPENCV model.
        sample = valid[::max(1, len(valid) // 40)]
        xyz = np.array([points[int(im.point3D_ids[j])].xyz for j in sample])
        if len(xyz):
            fx, fy, cx, cy, *distortion = cam.params
            K = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]])
            expected = cv2.projectPoints(xyz, rvec, im.tvec, K, np.array(distortion))[0][:, 0]
            actual = shot.project_many(xyz) * scale + np.array([cam.width, cam.height]) / 2
            max_projection_difference = max(max_projection_difference, float(np.max(np.abs(actual - expected))))
            residuals.extend(np.linalg.norm(actual - im.xys[sample], axis=1).tolist())
            sample_projections[im.name] = (str(int(im.point3D_ids[sample[0]])), shot.project(xyz[0]))
        if index % 40 == 0:
            print(f"Imported {index + 1}/{len(images)} images", flush=True)
    assert max_projection_difference < 1e-5, max_projection_difference
    similarity = align.align_reconstruction(rec, [], data.config)
    if similarity is None:
        raise RuntimeError("GPS similarity alignment failed")
    alignment_projection_error = max(
        float(np.linalg.norm(rec.shots[name].project(rec.points[pid].coordinates) - uv))
        for name, (pid, uv) in sample_projections.items()
    )
    assert alignment_projection_error < 1e-7, alignment_projection_error
    gps_errors = np.array([
        np.linalg.norm(s.pose.get_origin() - s.metadata.gps_position.value)
        for s in rec.shots.values() if s.metadata.gps_position.has_value
    ])
    data.save_camera_models(dict(rec.cameras))
    data.save_tracks_manager(tracks)
    data.save_reconstruction([rec])
    # ODM uses these directories as stage markers. The imported tracks and
    # reconstruction replace feature extraction/matching, not their raw files.
    (out / "features").mkdir(exist_ok=True)
    (out / "matches").mkdir(exist_ok=True)
    report = dict(source_model=args.model, images=len(images), points=len(points),
                  camera_projection_max_difference_pixels=max_projection_difference,
                  sampled_reprojection_median_pixels=float(np.median(residuals)),
                  alignment_projection_max_difference=alignment_projection_error,
                  gps_residual_median_m=float(np.median(gps_errors)),
                  gps_residual_p95_m=float(np.percentile(gps_errors, 95)),
                  similarity_scale=float(similarity[0]),
                  note="Imported COLMAP tracks and reconstruction; GPS alignment only; no dense reconstruction.")
    (out / "colmap_import.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
