"""
Export the 晓光忆时 Blender scene to a Godot-friendly GLB preview asset.

Usage:
  Blender --background /path/to/撮影スタジオblender版 配布用.blend \
    --python tools/blender/export_xiaoguang_yishi.py
"""

from __future__ import annotations

import os

import bpy


SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "..", "assets", "environments", "xiaoguang_yishi")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "xiaoguang_yishi.glb")


def remove_unneeded_helpers() -> None:
    removed = 0
    for obj in list(bpy.data.objects):
        if obj.type in {"CAMERA", "LIGHT", "EMPTY"}:
            bpy.data.objects.remove(obj, do_unlink=True)
            removed += 1
    print(f"[export_xiaoguang] Removed helper objects: {removed}")


def fix_materials() -> None:
    for mat in bpy.data.materials:
        if hasattr(mat, "use_nodes") and mat.use_nodes:
            mat.use_backface_culling = False
        if hasattr(mat, "blend_method") and mat.blend_method in {"BLEND", "HASHED", "CLIP"}:
            mat.use_backface_culling = False


def scale_scene() -> None:
    scale_factor = 0.1
    for obj in bpy.data.objects:
        if obj.parent is None:
            obj.scale *= scale_factor
            obj.location *= scale_factor
    print(f"[export_xiaoguang] Applied root scale: {scale_factor}")


def print_summary() -> None:
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    materials = list(bpy.data.materials)
    images = list(bpy.data.images)
    vertices = sum(len(obj.data.vertices) for obj in meshes if obj.data)
    print("\n=== Xiaoguang Yishi Export Summary ===")
    print(f"Mesh objects: {len(meshes)}")
    print(f"Materials: {len(materials)}")
    print(f"Images: {len(images)}")
    print(f"Vertices: {vertices}")
    print("Scale applied: 0.1x")
    print("======================================\n")


def export_glb() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_FILE,
        export_format="GLB",
        use_selection=False,
        export_animations=False,
        export_materials="EXPORT",
        export_keep_originals=False,
        export_apply=False,
        export_yup=True,
    )
    print(f"[export_xiaoguang] Exported: {OUTPUT_FILE}")


def main() -> None:
    print("[export_xiaoguang] Starting")
    fix_materials()
    remove_unneeded_helpers()
    scale_scene()
    print_summary()
    export_glb()
    print("[export_xiaoguang] Done")


if __name__ == "__main__":
    main()
