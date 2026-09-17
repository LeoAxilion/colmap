# 从 COLMAP 稀疏模型生成正射影像

复用已有结果运行：

```bash
bash /media/media02/lxiao/colmap/scripts/shell/run_colmap_fast_orthophoto.sh
```

默认输入：

- 原图：`/media/media01/lxiao/DOM/input/field70mm`
- OPENCV 稀疏模型：`/media/media01/lxiao/DOM/output-colmap/field70mm/sfm-COLMAP-OPENCV/sparse/0`
- 输出：`/media/media02/lxiao/DOM/output-odm/field70mm-colmap-fast-orthophoto`

最终影像：输出目录中的 `odm_orthophoto/odm_orthophoto.tif`，可用 QGIS 按原始像素查看，无需 MeshLab 截图。

流程：COLMAP 稀疏模型 → 导入 OpenSfM 格式并用照片 GPS 做相似变换对齐 → 原图去畸变 → 稀疏点云过滤 → 2.5D 表面 → 贴图 → GeoTIFF。

保留原命令的 `automatic_reconstructor --sparse 1 --dense 0`。有了 `sparse/0` 后，用上述脚本替代 `patch_match_stereo`、`stereo_fusion`、稠密点云泊松网格、手动 texrecon 和 MeshLab 截图。脚本自行处理去畸变和贴图，不依赖原来的 `dense` 文件夹。

这不是完全跳过几何建模：ODM fast-orthophoto 仍创建供正射投影使用的简化 2.5D 网格。太阳能板倾斜面、板间高差和遮挡处可能错位。高分辨率纹理不能弥补简化表面造成的几何误差。

默认请求 1 cm/像素，ODM 仍按实际 GSD 限制输出，避免把过采样误认为新增细节。无损 DEFLATE GeoTIFF 保留细节，自动构建金字塔方便浏览。运行限制为 8 CPU、28 GiB 内存。

其他数据集：

```bash
IMAGES=/absolute/path/images \
COLMAP_MODEL=/absolute/path/sparse/0 \
DATASET=my-colmap-fast-orthophoto \
ORTHO_CM=1 \
bash /media/media02/lxiao/colmap/scripts/shell/run_colmap_fast_orthophoto.sh
```

需要 OPENCV 相机模型、照片 GPS，且 COLMAP 中的照片名称要与原图一致。转换保留已优化的相机内参与观测轨迹，只做 GPS 相似变换，不重新优化 SfM。转换报告在 `opensfm/colmap_import.json`，包含投影一致性、重投影误差和 GPS 对齐残差。

重跑同一目录会复用已有中间结果。更换输入图像或稀疏模型时使用新的 `DATASET`；导入目录没有重新匹配所需的完整特征数据，不要对它使用 `--rerun-all` 或从 opensfm 阶段强制重算。

如果希望完全由 ODM 自行重建，而不复用 COLMAP：

```bash
DATASET=my-native-odm-fast-orthophoto \
bash /media/media02/lxiao/colmap/scripts/shell/run_field70mm_fast_orthophoto.sh
```

运行使用已安装并固定摘要的 `webodm/nodeodx` 容器（ODX 3.7.6，ODM 系列实现），不修改本地 ODM/COLMAP 核心源码。导入辅助脚本的初始化接口已按该容器版本验证。

该容器内置的浏览金字塔命令缺少参数分隔空格。脚本已改为在 ODM 完成后独立调用 GDAL，生成 6 级无损 DEFLATE 金字塔。

## 2026-09-16 实测

280 张照片、401751 个 COLMAP 稀疏点导入成功。输出 17469×32529 像素，1.0407 cm/像素，EPSG:32650，RGBA 无损 GeoTIFF，含金字塔约 1.23 GB。文件读取及 6 级金字塔检查通过。

输出目录中的 `overview.jpg` 是整体预览，`detail_center_1to1.png` 和 `detail_north_1to1.png` 是未经缩放的局部裁剪。观察到电池片纹理和板框可辨，但有明显板框折弯、接缝错位和局部拉伸。因此这次复用 COLMAP 的稀疏表面方案可以看布局与部分表面细节，不足以作为可靠的精细缺陷判读影像。不能把拼接形变误判成实物损伤。

本次没有完成另一套原生 OpenSfM 重建，也没有生成同条件密集重建对照；结论针对当前 COLMAP 稀疏模型加 ODM fast-orthophoto 的实测结果。提高输出像素数不能解决已观察到的几何错位。
