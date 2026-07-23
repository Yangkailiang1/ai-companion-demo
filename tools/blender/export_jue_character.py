import argparse
import math
from pathlib import Path

import bpy


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    source = Path(args.source)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    if source.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source))
    else:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()
        bpy.ops.import_scene.fbx(filepath=str(source))

    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type in {"MESH", "ARMATURE"})

    bpy.context.scene.render.fps = 30
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_animations=True,
        export_morph=True,
        export_skins=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    shape_keys = []
    for mesh in meshes:
        if mesh.data.shape_keys:
            shape_keys.extend(key.name for key in mesh.data.shape_keys.key_blocks)
    print(
        "JUE_EXPORT_SUMMARY meshes=%d armatures=%d shape_keys=%d output=%s"
        % (len(meshes), len(armatures), len(shape_keys), output)
    )
    if shape_keys:
        print("JUE_SHAPE_KEYS " + ", ".join(shape_keys[:80]))


if __name__ == "__main__":
    main()
