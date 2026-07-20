"""
generate_penguin_animations.py — Blender Python script to generate in-place animations
for the penguin character. Run AFTER loading the penguin model.
Usage: Blender --background path/to/penguin.blend --python generate_penguin_animations.py

Generates 7 animations: idle, walk, wave, nod, think, happy, sit.
All animations are in-place (no root motion) — movement is driven by Godot's AgentBase.
Compatible with Godot 4 AnimationPlayer.
"""

import bpy
import math
import mathutils
import os

# === Configuration ===
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "..", "assets", "characters", "penguin")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "penguin.glb")
FPS = 30.0

ANIMATION_SPECS = [
    ("idle",  2.0,  True),
    ("walk",  1.5,  True),
    ("wave",  2.0,  False),
    ("nod",   1.5,  False),
    ("think", 2.5,  False),
    ("happy", 2.0,  False),
    ("sit",   3.0,  False),
]


def get_armature():
    """Find and return the armature object."""
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            return obj
    raise RuntimeError("No armature found in scene. Load the penguin .blend first.")


def find_bone(armature, candidates):
    """Find a bone by trying multiple name candidates."""
    if isinstance(candidates, str):
        candidates = [candidates]
    for name in candidates:
        bone = armature.pose.bones.get(name)
        if bone:
            return bone
    # Try case-insensitive
    pose_bone_names = {b.name.lower(): b for b in armature.pose.bones}
    for name in candidates:
        b = pose_bone_names.get(name.lower())
        if b:
            return b
    return None


def new_action(action_name, duration_sec, loop=False):
    """Create a new Action and return it with frame count."""
    frames = int(duration_sec * FPS)
    action = bpy.data.actions.new(name=action_name)
    action.use_frame_range = True
    action.frame_start = 0
    action.frame_end = frames
    if loop:
        action.use_cyclic = True
    return action, frames


def iter_fcurves(action):
    """Yield FCurves for both legacy Actions and Blender 4.4+/5 layered Actions."""
    if hasattr(action, "fcurves"):
        yield from action.fcurves
        return
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in getattr(strip, "channelbags", []):
                yield from channelbag.fcurves


def reset_to_rest(armature):
    """Reset all pose bones to rest transforms."""
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.rot_clear()
    bpy.ops.pose.loc_clear()
    bpy.ops.object.mode_set(mode="OBJECT")


def key_rot(bone, frame, quat):
    """Keyframe rotation on a pose bone (must be in POSE mode)."""
    if not bone:
        return
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = quat
    bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def key_loc(bone, frame, loc):
    """Keyframe location on a pose bone."""
    if not bone:
        return
    bone.location = loc
    bone.keyframe_insert(data_path="location", frame=frame)


# === Animation generators ===

def gen_idle(armature, action, total_frames):
    """Gentle breathing + swaying idle loop."""
    spine = find_bone(armature, ["spine", "spine.001", "chest", "Chest"])
    head = find_bone(armature, ["head", "Head"])
    arm_l = find_bone(armature, ["upper_arm.L", "UpperArm_L", "shoulder.L", "Shoulder_L"])
    arm_r = find_bone(armature, ["upper_arm.R", "UpperArm_R", "shoulder.R", "Shoulder_R"])

    for frame in range(total_frames + 1):
        t = frame / total_frames * 2.0 * math.pi

        if spine:
            sway = math.sin(t) * 0.03
            key_rot(spine, frame, mathutils.Quaternion((0.0, 0.0, 1.0), sway))

        if head:
            breathe = math.sin(t * 2.0) * 0.015
            key_rot(head, frame, mathutils.Quaternion((1.0, 0.0, 0.0), breathe))

        arm_swing = math.sin(t) * 0.05
        if arm_l:
            key_rot(arm_l, frame, mathutils.Quaternion((0.0, 1.0, 0.0), arm_swing))
        if arm_r:
            key_rot(arm_r, frame, mathutils.Quaternion((0.0, 1.0, 0.0), -arm_swing))


def gen_walk(armature, action, total_frames):
    """In-place walk cycle (no root motion)."""
    uleg_l = find_bone(armature, ["upper_leg.L", "UpperLeg_L", "thigh.L", "Thigh_L"])
    uleg_r = find_bone(armature, ["upper_leg.R", "UpperLeg_R", "thigh.R", "Thigh_R"])
    lleg_l = find_bone(armature, ["lower_leg.L", "LowerLeg_L", "calf.L", "Calf_L"])
    lleg_r = find_bone(armature, ["lower_leg.R", "LowerLeg_R", "calf.R", "Calf_R"])
    arm_l = find_bone(armature, ["upper_arm.L", "UpperArm_L", "shoulder.L", "Shoulder_L"])
    arm_r = find_bone(armature, ["upper_arm.R", "UpperArm_R", "shoulder.R", "Shoulder_R"])

    for frame in range(total_frames + 1):
        t = frame / total_frames * 2.0 * math.pi

        leg_angle = math.sin(t) * 0.4
        knee_bend = abs(math.sin(t)) * 0.15 + 0.05

        if uleg_l:
            key_rot(uleg_l, frame, mathutils.Quaternion((1.0, 0.0, 0.0), leg_angle))
        if uleg_r:
            key_rot(uleg_r, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -leg_angle))
        if lleg_l:
            key_rot(lleg_l, frame, mathutils.Quaternion((1.0, 0.0, 0.0), knee_bend))
        if lleg_r:
            key_rot(lleg_r, frame, mathutils.Quaternion((1.0, 0.0, 0.0), knee_bend))
        if arm_l:
            key_rot(arm_l, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -leg_angle * 0.6))
        if arm_r:
            key_rot(arm_r, frame, mathutils.Quaternion((1.0, 0.0, 0.0), leg_angle * 0.6))


def gen_wave(armature, action, total_frames):
    """Wave right hand."""
    uarm_r = find_bone(armature, ["upper_arm.R", "UpperArm_R", "shoulder.R", "Shoulder_R"])
    larm_r = find_bone(armature, ["lower_arm.R", "LowerArm_R", "forearm.R", "Forearm_R"])
    hand_r = find_bone(armature, ["hand.R", "Hand_R"])

    for frame in range(total_frames + 1):
        t = frame / total_frames

        if t < 0.3:
            # raise arm
            p = t / 0.3
            if uarm_r:
                key_rot(uarm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), -p * 1.2))
            if larm_r:
                key_rot(larm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), p * 0.3))
        elif t < 0.7:
            # wave side to side
            wp = math.sin((t - 0.3) / 0.4 * 4.0 * math.pi) * 0.4
            if uarm_r:
                key_rot(uarm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), -1.2 + wp * 0.15))
            if hand_r:
                key_rot(hand_r, frame, mathutils.Quaternion((0.0, 1.0, 0.0), wp))
        else:
            # lower arm
            p = (t - 0.7) / 0.3
            if uarm_r:
                key_rot(uarm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), -1.2 * (1.0 - p)))
            if larm_r:
                key_rot(larm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), 0.3 * (1.0 - p)))


def gen_nod(armature, action, total_frames):
    """Nod head twice."""
    neck = find_bone(armature, ["neck", "Neck"])
    head = find_bone(armature, ["head", "Head"])

    for frame in range(total_frames + 1):
        t = frame / total_frames
        angle = 0.0
        if t < 0.15:
            angle = (t / 0.15) * 0.35
        elif t < 0.3:
            angle = 0.35 * (1.0 - (t - 0.15) / 0.15)
        elif t < 0.45:
            angle = ((t - 0.3) / 0.15) * 0.3
        elif t < 0.6:
            angle = 0.3 * (1.0 - (t - 0.45) / 0.15)

        if neck:
            key_rot(neck, frame, mathutils.Quaternion((1.0, 0.0, 0.0), angle))
        if head:
            key_rot(head, frame, mathutils.Quaternion((1.0, 0.0, 0.0), angle * 1.2))


def gen_think(armature, action, total_frames):
    """Think: head tilt + hand to chin."""
    neck = find_bone(armature, ["neck", "Neck"])
    head = find_bone(armature, ["head", "Head"])
    uarm_r = find_bone(armature, ["upper_arm.R", "UpperArm_R", "shoulder.R", "Shoulder_R"])
    larm_r = find_bone(armature, ["lower_arm.R", "LowerArm_R", "forearm.R", "Forearm_R"])

    for frame in range(total_frames + 1):
        t = frame / total_frames
        p_head = min(t / 0.3, 1.0)
        p_arm = min(t / 0.5, 1.0)

        if neck:
            key_rot(neck, frame, mathutils.Quaternion((0.0, 0.0, 1.0), p_head * 0.2))
        if head:
            key_rot(head, frame, mathutils.Quaternion((0.0, 0.0, 1.0), p_head * 0.3))
        if uarm_r:
            key_rot(uarm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), -p_arm * 1.5))
        if larm_r:
            key_rot(larm_r, frame, mathutils.Quaternion((0.0, 0.0, 1.0), p_arm * 1.8))


def gen_happy(armature, action, total_frames):
    """Happy: bounce + arms up."""
    arm_l = find_bone(armature, ["upper_arm.L", "UpperArm_L", "shoulder.L", "Shoulder_L"])
    arm_r = find_bone(armature, ["upper_arm.R", "UpperArm_R", "shoulder.R", "Shoulder_R"])
    spine = find_bone(armature, ["spine", "spine.001", "chest", "Chest"])
    head = find_bone(armature, ["head", "Head"])

    for frame in range(total_frames + 1):
        t = frame / total_frames
        bounce = math.sin(t * 2.0 * math.pi) * 0.05
        raise_p = min(t * 2.0, 0.6)

        if arm_l:
            key_rot(arm_l, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -raise_p * 0.8 + bounce))
        if arm_r:
            key_rot(arm_r, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -raise_p * 0.8 + bounce))
        if spine:
            key_rot(spine, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -0.05 + bounce * 0.3))
        if head:
            key_rot(head, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -0.15))


def gen_sit(armature, action, total_frames):
    """Sit down: fold legs."""
    uleg_l = find_bone(armature, ["upper_leg.L", "UpperLeg_L", "thigh.L", "Thigh_L"])
    uleg_r = find_bone(armature, ["upper_leg.R", "UpperLeg_R", "thigh.R", "Thigh_R"])
    lleg_l = find_bone(armature, ["lower_leg.L", "LowerLeg_L", "calf.L", "Calf_L"])
    lleg_r = find_bone(armature, ["lower_leg.R", "LowerLeg_R", "calf.R", "Calf_R"])
    spine = find_bone(armature, ["spine", "spine.001", "chest", "Chest"])

    for frame in range(total_frames + 1):
        t = frame / total_frames
        p = min(t / 0.4, 1.0)
        # smoothstep ease
        eased = p * p * (3.0 - 2.0 * p)

        if uleg_l:
            key_rot(uleg_l, frame, mathutils.Quaternion((1.0, 0.0, 0.0), eased * 1.5))
        if uleg_r:
            key_rot(uleg_r, frame, mathutils.Quaternion((1.0, 0.0, 0.0), eased * 1.5))
        if lleg_l:
            key_rot(lleg_l, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -eased * 1.6))
        if lleg_r:
            key_rot(lleg_r, frame, mathutils.Quaternion((1.0, 0.0, 0.0), -eased * 1.6))
        if spine:
            key_rot(spine, frame, mathutils.Quaternion((1.0, 0.0, 0.0), eased * 0.15))


GENERATORS = {
    "idle": gen_idle,
    "walk": gen_walk,
    "wave": gen_wave,
    "nod": gen_nod,
    "think": gen_think,
    "happy": gen_happy,
    "sit": gen_sit,
}


def generate_all(armature):
    """Generate all animations on the armature."""
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")

    if not armature.animation_data:
        armature.animation_data_create()

    for name, duration, loop in ANIMATION_SPECS:
        print(f"[anim] Generating '{name}' ({duration}s, loop={loop})...")
        action, total_frames = new_action(name, duration, loop)
        armature.animation_data.action = action

        # Reset all bones to rest pose before each animation
        bpy.ops.pose.select_all(action="SELECT")
        bpy.ops.pose.rot_clear()
        bpy.ops.pose.loc_clear()

        # Generate keyframes
        gen = GENERATORS[name]
        gen(armature, action, total_frames)

        # Update f-curve handles for smooth interpolation
        for fcurve in iter_fcurves(action):
            for kp in fcurve.keyframe_points:
                kp.interpolation = "BEZIER"
                kp.handle_left_type = "AUTO_CLAMPED"
                kp.handle_right_type = "AUTO_CLAMPED"

        # Reset to rest
        bpy.ops.pose.select_all(action="SELECT")
        bpy.ops.pose.rot_clear()
        bpy.ops.pose.loc_clear()

        armature.animation_data.action = None
        print(f"  → {total_frames + 1} frames, {len(list(iter_fcurves(action)))} fcurves")

    bpy.ops.object.mode_set(mode="OBJECT")


def export_glb():
    """Export the scene as GLB for Godot."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"[anim] Exporting to: {OUTPUT_FILE}")

    armature = get_armature()
    character_meshes = []
    for obj in list(bpy.data.objects):
        is_character_mesh = obj.type == "MESH" and (
            obj.parent == armature or any(
            modifier.type == "ARMATURE" and modifier.object == armature
            for modifier in obj.modifiers
            )
        )
        if is_character_mesh:
            character_meshes.append(obj)
        elif obj != armature:
            # Work on the in-memory copy only. Removing source-scene helpers makes
            # the exported hierarchy deterministic and avoids Blender 5 selection
            # filtering dropping the armature/skin.
            bpy.data.objects.remove(obj, do_unlink=True)

    armature.hide_set(False)
    armature.hide_render = False
    if armature.animation_data:
        armature.animation_data.action = bpy.data.actions.get("idle")

    print(f"[anim] Export hierarchy: armature + {len(character_meshes)} skinned meshes")
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_FILE,
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_materials="EXPORT",
        export_keep_originals=False,
        export_apply=False,
        export_yup=True,
    )
    print("[anim] Export complete.")


def print_summary():
    """Print a summary of all generated animations."""
    print("\n=== Generated Animations ===")
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        bones = set()
        fcurves = list(iter_fcurves(action))
        for fc in fcurves:
            dp = fc.data_path
            if 'bones[' in dp:
                start = dp.index('bones[') + 7
                end = dp.index('"]', start)
                bones.add(dp[start:end])
        print(f"  {action.name}: frames={action.frame_start}–{action.frame_end}, "
              f"bones={len(bones)}, fcurves={len(fcurves)}, cyclic={action.use_cyclic}")
        if bones:
            print(f"    bones: {', '.join(sorted(bones))}")
    print("============================\n")


def main():
    print("[generate_animations] Starting...")
    bpy.context.scene.render.fps = int(FPS)
    bpy.context.scene.render.fps_base = 1.0
    armature = get_armature()
    print(f"[generate_animations] Found armature: '{armature.name}' ({len(armature.data.bones)} bones)")

    # The source .blend contains unrelated pose-library actions. Keeping them would
    # make Godot import dozens of unusable clips and could cause name collisions.
    if armature.animation_data:
        armature.animation_data.action = None
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    generate_all(armature)
    print_summary()
    export_glb()
    print("[generate_animations] Done!")


if __name__ == "__main__":
    main()
