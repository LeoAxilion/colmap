#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export IMAGES=${IMAGES:-/media/media01/lxiao/DOM/input/field70mm}
export PROJECT_ROOT=${PROJECT_ROOT:-/media/media02/lxiao/DOM/output-odm}
export DATASET=${DATASET:-field70mm-colmap-fast-orthophoto}
export ODM_IMAGE=${ODM_IMAGE:-sha256:6547714ba4cfe1a41a3646de70c502c351c7236791862ee5dac147c66c90f93a}
COLMAP_MODEL=${COLMAP_MODEL:-/media/media01/lxiao/DOM/output-colmap/field70mm/sfm-COLMAP-OPENCV/sparse/0}
mkdir -p "$PROJECT_ROOT/$DATASET/images"
if [[ ! -s "$PROJECT_ROOT/$DATASET/opensfm/reconstruction.json" ]]; then
  docker run --rm --user "$(id -u):$(id -g)" --cpus 4 --memory 12g \
    -e HOME=/tmp -e OPENBLAS_NUM_THREADS=1 -e OMP_NUM_THREADS=1 \
    -v "$REPO:/scripts:ro" -v "$COLMAP_MODEL:/model:ro" \
    -v "$PROJECT_ROOT:/datasets" \
    -v "$IMAGES:/datasets/$DATASET/images:ro" \
    -w /code --entrypoint python3 "$ODM_IMAGE" \
    /scripts/import_colmap_fast_orthophoto.py /model \
    "/datasets/$DATASET/opensfm" \
    2>&1 | tee "$PROJECT_ROOT/$DATASET/import.log"
fi
exec bash "$SCRIPT_DIR/run_field70mm_fast_orthophoto.sh" "$@"
