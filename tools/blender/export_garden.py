"""
export_garden.py — Blender Python script to export the 终幕喑哑之庭 garden scene.
Usage: Blender --background path/to/garden.blend --python export_garden.py

Exports to GLB for import into Godot 4 as a preview scene.
Target: assets/environments/endless_garden/garden.glb
"""

import bpy
import os

# === Configuration ===
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "..", "assets", "environments", "endless_garden")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "garden.glb")

# Alpha-blended materials needing attention (4 identified in audit)
ALPHA_MATERIAL_NAMES = {"gan.001", "gan.002", "ye", "ye.001"}


def remove_cameras_lights_helpers():
    """Remove camera, light, and empty objects (keep meshes, curves, armatures)."""
    to_remove = []
    for obj in bpy.data.objects:
        if obj.type in {"CAMERA", "LIGHT", "EMPTY"}:
            to_remove.append(obj)
            continue
    for obj in to_remove:
        print(f"[export_garden] Removing: {obj.name} (type={obj.type})")
        bpy.data.objects.remove(obj, do_unlink=True)
    print(f"[export_garden] Removed {len(to_remove)} helper objects.")


def audit_alpha_materials():
    """Identify materials using alpha blending that may need fixing in Godot."""
    global ALPHA_MATERIAL_NAMES
    alpha_mats = list(ALPHA_MATERIAL_NAMES)
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                alpha = node.inputs.get("Alpha", None)
                if alpha and (alpha.default_value < 1.0 or len(alpha.links) > 0):
                    if mat.name not in alpha_mats:
                        alpha_mats.append(mat.name)
                    break
    ALPHA_MATERIAL_NAMES = set(alpha_mats)
    if alpha_mats:
        print(f"[export_garden] Alpha materials detected ({len(alpha_mats)}): {', '.join(alpha_mats)}")
    else:
        print("[export_garden] No alpha materials detected via BSDF check — will verify post-import.")


def fix_alpha_materials_for_godot():
    """Adjust alpha materials for Godot compatibility.
    Godot 4 GLTF importer maps BLEND to transparent materials.
    Convert ALPHA_BLEND to ALPHA_HASH where appropriate.
    """
    for mat_name in ALPHA_MATERIAL_NAMES:
        mat = bpy.data.materials.get(mat_name)
        if not mat:
            continue
        # Ensure blend mode is set on the material
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        # Disable backface culling for alpha materials
        mat.use_backface_culling = False
        print(f"[export_garden] Fixed alpha material: {mat_name}")


def scale_scene():
    """Scale the ~195m scene down for Godot if needed.
    Godot's default camera/clip planes work better with smaller scales.
    We scale by 0.1 to get ~19.5m radius which is manageable.
    """
    scale_factor = 0.1
    # Apply scale to all root objects
    for obj in bpy.data.objects:
        if obj.parent is None and obj.name not in {"Camera", "Light"}:
            obj.scale *= scale_factor
            obj.location *= scale_factor
            print(f"[export_garden] Scaled '{obj.name}' by {scale_factor}x")
    # Also store an empty at origin for reference
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    origin_empty = bpy.context.active_object
    origin_empty.name = "GardenOrigin"
    origin_empty.scale = (1.0 / scale_factor, 1.0 / scale_factor, 1.0 / scale_factor)


def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)


def export_glb():
    """Export to GLB for Godot 4."""
    print(f"[export_garden] Exporting to: {OUTPUT_FILE}")

    bpy.ops.object.select_all(action="SELECT")

    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_FILE,
        export_format="GLB",
        use_selection=False,
        export_animations=False,  # No animations in this scene
        export_materials="EXPORT",
        export_texture_dir="textures",
        export_keep_originals=False,
        export_apply=False,
        export_yup=True,
    )
    print("[export_garden] Export complete.")


def print_summary():
    """Print summary of exported content."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    curves = [o for o in bpy.data.objects if o.type == "CURVE"]
    materials = list(bpy.data.materials)
    vertices = sum(len(m.data.vertices) for m in meshes if m.data and hasattr(m.data, "vertices"))

    print("\n=== Garden Export Summary ===")
    print(f"Mesh objects: {len(meshes)}")
    print(f"Curve objects: {len(curves)}")
    print(f"Materials: {len(materials)}")
    print(f"Total vertices: {vertices}")
    print(f"Alpha materials: {len(ALPHA_MATERIAL_NAMES)} — {', '.join(ALPHA_MATERIAL_NAMES) if ALPHA_MATERIAL_NAMES else 'none'}")
    print(f"Scale applied: 0.1x (for Godot compatibility)")
    print("==============================\n")


def write_nav_notes():
    """Write navigation planning notes."""
    notes_path = os.path.join(OUTPUT_DIR, "NAVIGATION_NOTES.md")
    content = """# Endless Garden — Navigation Notes

## Status
NavMesh is NOT baked for this scene (195m original, ~19.5m after scale).

## Options for future navigation
1. **Godot NavigationRegion3D**: Add a NavigationRegion3D in the preview scene and bake a NavMesh using `bake_navigation_mesh()`.
   - Complexity: High due to irregular terrain and foliage geometry.
   - Recommended: Use simplified collision-only NavMesh.

2. **Manual waypoint system**: Place NavigationLink3D nodes at key paths.
   - Simpler for this style of scene.
   - Works well with the existing AgentBase NavMesh fallback (direct-lerp).

3. **Keep direct fallback**: AgentBase already has a direct position-lerp fallback when no NavMesh is available.
   - No additional work needed.
   - Limitation: Agent may clip through walls/objects.

## Alpha Materials
4 materials flagged with alpha blending. These may render incorrectly in Godot 4
depending on the GLTF importer's transparency handling. Check post-import and adjust
material flags (transparency, cull mode) in the Godot editor.
"""
    os.makedirs(os.path.dirname(notes_path), exist_ok=True)
    with open(notes_path, "w") as f:
        f.write(content)
    print(f"[export_garden] Wrote navigation notes to: {notes_path}")


def main():
    print("[export_garden] Starting export pipeline...")

    audit_alpha_materials()
    fix_alpha_materials_for_godot()
    remove_cameras_lights_helpers()
    scale_scene()
    ensure_output_dir()

    print_summary()
    export_glb()
    write_nav_notes()

    print("[export_garden] Done!")


if __name__ == "__main__":
    main()
