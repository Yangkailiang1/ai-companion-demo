"""
Bake a retarget package from motion_lab into the penguin GLB.

Usage:
  Blender --background --python tools/blender/bake_retarget_package.py -- \
    --input-glb assets/characters/penguin/penguin.glb \
    --package motion_lab/generated/library/smoke_walk \
    --output-glb assets/characters/penguin/penguin.glb \
    --action-name offline_smoke_walk
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
import mathutils
import numpy as np


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-glb", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--output-glb", required=True)
    parser.add_argument("--action-name", default="offline_smoke_walk")
    parser.add_argument("--rotation-scale", type=float, default=1.35)
    return parser.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def get_armature() -> bpy.types.Object:
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            return obj
    raise RuntimeError("No armature found after GLB import")


def find_bone(armature: bpy.types.Object, name: str):
    bone = armature.pose.bones.get(name)
    if bone:
        return bone
    lower = name.lower()
    for candidate in armature.pose.bones:
        if candidate.name.lower() == lower:
            return candidate
    return None


def iter_fcurves(action):
    if hasattr(action, "fcurves"):
        yield from action.fcurves
        return
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in getattr(strip, "channelbags", []):
                yield from channelbag.fcurves


def scaled_quat(quat_wxyz: np.ndarray, scale: float) -> mathutils.Quaternion:
    quat = mathutils.Quaternion((float(quat_wxyz[0]), float(quat_wxyz[1]), float(quat_wxyz[2]), float(quat_wxyz[3])))
    quat.normalize()
    if abs(scale - 1.0) < 1e-4:
        return quat
    axis, angle = quat.to_axis_angle()
    if not math.isfinite(angle):
        return mathutils.Quaternion()
    return mathutils.Quaternion(axis, angle * scale)


def bake_action(armature: bpy.types.Object, package_dir: str, action_name: str, rotation_scale: float) -> None:
    metadata_path = os.path.join(package_dir, "motion_package.json")
    with open(metadata_path, "r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    arrays = metadata["arrays"]
    rotations = np.load(os.path.join(package_dir, arrays["target_rotations"]), allow_pickle=False)
    root_motion = np.load(os.path.join(package_dir, arrays["root_motion"]), allow_pickle=False)
    bone_order = metadata["runtime_contract"]["bone_name_order"]
    fps = float(metadata.get("fps", 20.0))
    frames = int(metadata["frame_count"])

    bpy.context.scene.render.fps = int(round(fps))
    bpy.context.scene.render.fps_base = 1.0
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = frames - 1
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.rot_clear()
    bpy.ops.pose.loc_clear()

    old_action = bpy.data.actions.get(action_name)
    if old_action:
        bpy.data.actions.remove(old_action)
    action = bpy.data.actions.new(action_name)
    action.use_frame_range = True
    action.frame_start = 0
    action.frame_end = frames - 1
    armature.animation_data_create()
    armature.animation_data.action = action

    missing = []
    pose_tracks = []
    for bone_name in bone_order:
        bone = find_bone(armature, bone_name)
        if not bone:
            missing.append(bone_name)
        pose_tracks.append(bone)
    if missing:
        raise RuntimeError(f"Missing target bones: {missing}")

    root = find_bone(armature, "hips") or find_bone(armature, "root")
    root_start = mathutils.Vector((float(root_motion[0, 0]), float(root_motion[0, 1]), float(root_motion[0, 2])))

    for frame in range(frames):
        bpy.context.scene.frame_set(frame)
        for track_index, bone in enumerate(pose_tracks):
            if bone is None:
                continue
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = scaled_quat(rotations[frame, track_index], rotation_scale)
            bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if root:
            current = mathutils.Vector((float(root_motion[frame, 0]), float(root_motion[frame, 1]), float(root_motion[frame, 2])))
            delta = current - root_start
            root.location = mathutils.Vector((0.0, delta.y * 0.18, 0.0))
            root.keyframe_insert(data_path="location", frame=frame)

    for fcurve in iter_fcurves(action):
        for point in fcurve.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
    armature.animation_data.action = action
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"[bake_retarget] Baked action {action_name}: frames={frames} bones={len(bone_order)}")


def export_glb(output_glb: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(output_glb)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_glb,
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_materials="EXPORT",
        export_keep_originals=False,
        export_apply=False,
        export_yup=True,
    )
    print(f"[bake_retarget] Exported {output_glb}")


def main() -> None:
    args = parse_args()
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=args.input_glb)
    armature = get_armature()
    bake_action(armature, args.package, args.action_name, args.rotation_scale)
    export_glb(args.output_glb)


if __name__ == "__main__":
    main()
