"""
export_penguin.py — Blender Python script to export penguin character for Godot 4.6.
Usage: Blender --background path/to/penguin.blend --python export_penguin.py

Cleans camera/light/helper nodes, then exports armature + skinned meshes
+ materials + textures + Shape Keys to GLB format.

Target: assets/characters/penguin/penguin.glb
"""

import bpy
import os
import sys

# === Configuration ===
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "assets", "characters", "penguin")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "penguin.glb")

# Shape Keys to export (facial expressions)
SHAPE_KEYS_TO_KEEP = {
    "eye", "blink", "happy", "sad", "angry", "surprised",
    "A", "E", "I", "O", "U",  # vowel visemes
}

# Nodes to remove (cameras, lights, helpers)
PREFIXES_TO_REMOVE = {"Camera", "Light", "Empty", "Helper", "Armature_Helper"}

# === Cleanup helpers ===
def remove_unwanted_objects():
    """Remove camera, light, and helper objects from the scene."""
    to_remove = []
    for obj in bpy.data.objects:
        if obj.type in {"CAMERA", "LIGHT", "EMPTY"}:
            to_remove.append(obj)
            continue
        name_lower = obj.name.lower()
        for prefix in PREFIXES_TO_REMOVE:
            if name_lower.startswith(prefix.lower()):
                to_remove.append(obj)
                break

    for obj in to_remove:
        print(f"[export_penguin] Removing: {obj.name} (type={obj.type})")
        bpy.data.objects.remove(obj, do_unlink=True)

    print(f"[export_penguin] Removed {len(to_remove)} helper objects.")


def remove_unwanted_shape_keys():
    """Remove Shape Keys that are not needed for gameplay."""
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        if not mesh.shape_keys or not mesh.shape_keys.key_blocks:
            continue
        # Iterate backwards to safely remove
        key_blocks = mesh.shape_keys.key_blocks
        removed = 0
        for kb in list(key_blocks):
            if kb.name.lower() not in {k.lower() for k in SHAPE_KEYS_TO_KEEP} and kb.name != "Basis":
                # Try partial match
                name_lower = kb.name.lower()
                keep = False
                for keep_key in SHAPE_KEYS_TO_KEEP:
                    if keep_key.lower() in name_lower:
                        keep = True
                        break
                if not keep:
                    obj.shape_key_remove(kb)
                    removed += 1
        if removed > 0:
            print(f"[export_penguin] Removed {removed} shape keys from '{obj.name}'")


def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)


def clear_existing_actions():
    """Remove existing single-pose actions to avoid exporting non-playable animations."""
    for action in list(bpy.data.actions):
        print(f"[export_penguin] Removing existing action: {action.name}")
        bpy.data.actions.remove(action)


def export_to_glb():
    """Export the scene as GLB for Godot."""
    print(f"[export_penguin] Exporting to: {OUTPUT_FILE}")

    bpy.ops.object.select_all(action="SELECT")

    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_FILE,
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_materials="EXPORT",
        export_texture_dir="textures",
        export_keep_originals=True,
        export_apply=False,
        export_yup=True,  # Godot uses Y-up
    )

    print("[export_penguin] Export complete!")


def print_summary():
    """Print a summary of exported content."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    materials = list(bpy.data.materials)
    actions = list(bpy.data.actions)

    print("\n=== Export Summary ===")
    print(f"Meshes: {len(meshes)} — {[m.name for m in meshes]}")
    print(f"Armatures: {len(armatures)} — {[a.name for a in armatures]}")
    print(f"Materials: {len(materials)} — {[m.name for m in materials]}")
    print(f"Actions/Animations: {len(actions)} — {[a.name for a in actions]}")

    for arm in armatures:
        bones = [b.name for b in arm.data.bones]
        print(f"\nArmature '{arm.name}' bones ({len(bones)}):")
        print(f"  {', '.join(bones[:20])}" + ("..." if len(bones) > 20 else ""))

    for obj in meshes:
        mesh = obj.data
        if mesh.shape_keys and mesh.shape_keys.key_blocks:
            sks = [kb.name for kb in mesh.shape_keys.key_blocks]
            print(f"\nMesh '{obj.name}' Shape Keys ({len(sks)}):")
            print(f"  {', '.join(sks)}")

    print("=====================\n")


# === Main ===
def main():
    print("[export_penguin] Starting export pipeline...")

    clear_existing_actions()
    remove_unwanted_objects()
    remove_unwanted_shape_keys()
    ensure_output_dir()

    # Unpack textures if they are packed
    for image in bpy.data.images:
        if image.packed_file:
            try:
                image.unpack(method="USE_LOCAL")
            except Exception as e:
                print(f"[export_penguin] Warning: could not unpack {image.name}: {e}")

    print_summary()
    export_to_glb()


if __name__ == "__main__":
    main()
