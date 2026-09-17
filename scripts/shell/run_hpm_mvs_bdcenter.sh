#!/usr/bin/env bash
# Reuse COLMAP SfM, replace depth estimation AND fusion with HPM-MVS++.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
colmap="$repo/build/src/colmap/exe/colmap"
hpm_root=${HPM_ROOT:-/media/media02/lxiao/HPM-MVS_plusplus}
sfm=${SFM_PATH:-/media/media01/lxiao/DOM/output-colmap/bdcenter/sparse/0}
images=${IMAGE_PATH:-/media/media01/lxiao/DOM/input/bdcenter}
output=${OUTPUT_PATH:-"$repo/outputs/bdcenter-hpm-3200"}
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-8}
export OPENBLAS_NUM_THREADS=1
mkdir -p "$output/logs"
stage=setup
trap 'code=$?; echo "$(date -Is) FAILED stage=$stage exit=$code" | tee "$output/status.txt" >&2; exit "$code"' ERR

if [[ -z "${HPM_EXECUTABLE:-}" ]]; then
    cmake -S "$hpm_root" -B "$output/hpm-build-release" \
        -DCMAKE_BUILD_TYPE=Release 2>&1 | tee "$output/logs/build.log"
    cmake --build "$output/hpm-build-release" -j 4 \
        2>&1 | tee -a "$output/logs/build.log"
    hpm_executable="$output/hpm-build-release/HPM-MVS_plusplus"
else
    hpm_executable="$HPM_EXECUTABLE"
fi

if [[ ! -f "$output/undistort.done" ]]; then
    "$colmap" image_undistorter --image_path "$images" \
        --input_path "$sfm" --output_path "$output/colmap" \
        --output_type COLMAP --max_image_size 3200 --num_threads 8 \
        2>&1 | tee "$output/logs/undistort.log"
    touch "$output/undistort.done"
fi

if [[ ! -f "$output/convert.done" ]]; then
    python "$hpm_root/colmap2mvsnet_acm.py" \
        --dense_folder "$output/colmap" --save_folder "$output/hpm" \
        --model_ext .bin 2>&1 | tee "$output/logs/convert.log"
    touch "$output/convert.done"
fi

if [[ ! -f "$output/hpm.done" ]]; then
    # The HPM executable restarts all scales after an interrupted HPM stage.
    "$hpm_executable" "$output/hpm" false \
        2>&1 | tee "$output/logs/hpm.log"
    test -s "$output/hpm/HPM_MVS_plusplus/fused.ply"
    touch "$output/hpm.done"
fi

if [[ ! -e "$output/colmap/fused.ply" ]]; then
    ln -s ../hpm/HPM_MVS_plusplus/fused.ply "$output/colmap/fused.ply"
fi

if [[ ! -f "$output/mesh.done" ]]; then
    stage=mesh
    echo "$(date -Is) RUNNING stage=$stage depth=${POISSON_DEPTH:-11}" | tee "$output/status.txt"
    /usr/bin/time -v "$colmap" poisson_mesher \
        --input_path "$output/hpm/HPM_MVS_plusplus/fused.ply" \
        --output_path "$output/colmap/meshed-poisson.ply" \
        --PoissonMeshing.depth "${POISSON_DEPTH:-11}" \
        --PoissonMeshing.num_threads 8 2>&1 | tee "$output/logs/mesh.log"
    touch "$output/mesh.done"
fi

if [[ ! -f "$output/texture.done" ]]; then
    stage=texture
    echo "$(date -Is) RUNNING stage=$stage" | tee "$output/status.txt"
    /usr/bin/time -v "$colmap" mesh_texturer --workspace_path "$output/colmap" \
        --input_path "$output/colmap/meshed-poisson.ply" \
        --output_path "$output/colmap/textured" \
        --MeshTextureMapping.num_threads 8 \
        2>&1 | tee "$output/logs/texture.log"
    touch "$output/texture.done"
fi
echo "$(date -Is) COMPLETED: $output" | tee "$output/status.txt"
