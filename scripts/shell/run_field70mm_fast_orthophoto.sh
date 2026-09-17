#!/usr/bin/env bash
set -euo pipefail

# Native ODM/ODX sparse SfM -> 2.5D mesh -> texture -> GeoTIFF.
# This replaces the COLMAP dense/fusion/Poisson/MeshLab screenshot workflow.
IMAGES=${IMAGES:-/media/media01/lxiao/DOM/input/field70mm}
PROJECT_ROOT=${PROJECT_ROOT:-/media/media02/lxiao/DOM/output-odm}
DATASET=${DATASET:-field70mm-fast-orthophoto}
ODM_IMAGE=${ODM_IMAGE:-sha256:6547714ba4cfe1a41a3646de70c502c351c7236791862ee5dac147c66c90f93a}
CONCURRENCY=${CONCURRENCY:-8}
ORTHO_CM=${ORTHO_CM:-1}

mkdir -p "$PROJECT_ROOT/$DATASET/images"
docker run --rm --name "odm-$DATASET" \
  --user "$(id -u):$(id -g)" --cpus "$CONCURRENCY" --memory 28g \
  -e HOME=/tmp -e PYTHONUNBUFFERED=1 -e OMP_NUM_THREADS="$CONCURRENCY" \
  -v "$PROJECT_ROOT:/datasets" \
  -v "$IMAGES:/datasets/$DATASET/images:ro" \
  -w /code --entrypoint /code/run.sh "$ODM_IMAGE" \
  --project-path /datasets "$DATASET" \
  --fast-orthophoto --skip-3dmodel --skip-report \
  --camera-lens brown --feature-quality high \
  --max-concurrency "$CONCURRENCY" --no-gpu \
  --orthophoto-resolution "$ORTHO_CM" \
  --orthophoto-compression DEFLATE \
  --end-with odm_postprocess "$@" \
  2>&1 | tee "$PROJECT_ROOT/$DATASET/run.log"

# ODX 3.7.6 has a missing space in its built-in gdaladdo command.
# Build lossless RGBA-compatible overviews with separate arguments instead.
if [[ -s "$PROJECT_ROOT/$DATASET/odm_orthophoto/odm_orthophoto.tif" ]]; then
  docker run --rm --user "$(id -u):$(id -g)" --cpus 4 --memory 8g \
    -v "$PROJECT_ROOT/$DATASET:/work" --entrypoint gdaladdo "$ODM_IMAGE" \
    --config GDAL_CACHEMAX 1024 --config COMPRESS_OVERVIEW DEFLATE \
    --config BIGTIFF_OVERVIEW IF_SAFER -r average \
    /work/odm_orthophoto/odm_orthophoto.tif 2 4 8 16 32 64 \
    2>&1 | tee "$PROJECT_ROOT/$DATASET/overviews.log"
fi
