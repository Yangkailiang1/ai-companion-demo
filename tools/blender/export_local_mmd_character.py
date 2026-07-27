"""Convert one locally licensed PMX model into a Godot-readable GLB.

Roadmap: C6.1, C6.2, O4
Responsibility: Register a caller-provided MMD Tools checkout, import PMX mesh,
skeleton and morphs, then write a selected-object GLB. This script never
downloads assets and never copies source license files into the project.
Tests: scripts/debug/local_character_import_check.gd
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


def parse_args() -> tuple[Path, Path, Path]:
    """Return MMD Tools source, PMX input and GLB output arguments.

    Roadmap: C6.1
    Side effects: None.
    """
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 3:
        raise SystemExit(
            "usage: blender --python export_local_mmd_character.py -- "
            "MMD_TOOLS_SOURCE INPUT.pmx OUTPUT.glb"
        )
    return tuple(Path(arg).resolve() for arg in args)


def reset_scene() -> None:
    """Remove startup objects before importing the locally licensed model.

    Roadmap: C6.1
    Side effects: Mutates only the in-memory Blender scene.
    """
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def register_mmd_tools(source_root: Path) -> None:
    """Load and register MMD Tools from an explicit temporary checkout.

    Roadmap: C6.1, O4
    Side effects: Registers Blender operators for the current process only.
    """
    source_text = str(source_root)
    if source_text not in sys.path:
        sys.path.insert(0, source_text)
    import mmd_tools

    mmd_tools.register()


def import_pmx(input_path: Path) -> tuple[list[bpy.types.Object], bpy.types.Object]:
    """Import render meshes, armature and morphs while excluding MMD physics.

    Roadmap: C6.1, C3.1
    Side effects: Adds the model to the current Blender scene.
    """
    result = bpy.ops.mmd_tools.import_model(
        filepath=str(input_path),
        types={"MESH", "ARMATURE", "MORPHS"},
        scale=0.08,
        clean_model=True,
        remove_doubles=False,
        rename_bones=True,
        use_underscore=False,
        log_level="WARNING",
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"PMX import failed: {input_path}")
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if not meshes or len(armatures) != 1:
        raise RuntimeError(
            f"expected meshes and one armature, found {len(meshes)} / {len(armatures)}"
        )
    return meshes, armatures[0]


def select_export_objects(
    meshes: list[bpy.types.Object],
    armature: bpy.types.Object,
) -> None:
    """Select only render meshes and their deform skeleton for GLB export.

    Roadmap: C6.1
    Side effects: Replaces the current Blender object selection.
    """
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature


def normalize_materials(meshes: list[bpy.types.Object]) -> None:
    """Rebuild MMD node groups as portable texture-based Principled materials.

    Roadmap: C6.1, C8.1
    Side effects: Replaces imported Blender-only MMD shader node graphs.
    """
    materials = {
        slot.material
        for mesh in meshes
        for slot in mesh.material_slots
        if slot.material is not None
    }
    for material in materials:
        images = [
            node.image
            for node in material.node_tree.nodes
            if node.type == "TEX_IMAGE" and node.image
        ]
        if not images:
            continue
        base_color = material.diffuse_color
        nodes = material.node_tree.nodes
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = images[0]
        shader.inputs["Base Color"].default_value = base_color
        shader.inputs["Roughness"].default_value = 0.72
        shader.inputs["Alpha"].default_value = base_color[3]
        links = material.node_tree.links
        links.new(texture.outputs["Color"], shader.inputs["Base Color"])
        links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
        links.new(shader.outputs["BSDF"], output.inputs["Surface"])
        material.use_backface_culling = False
        if hasattr(material, "surface_render_method"):
            material.surface_render_method = "DITHERED"


def export_glb(output_path: Path) -> None:
    """Export selected MMD render data with embedded textures and morphs.

    Roadmap: C6.1, C3.1, O4
    Side effects: Writes one local-only GLB.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_morph=True,
        export_morph_normal=True,
        export_animations=True,
        export_yup=True,
        export_apply=False,
        export_cameras=False,
        export_lights=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"GLB export failed: {output_path}")


def describe_model(
    meshes: list[bpy.types.Object],
    armature: bpy.types.Object,
) -> None:
    """Print bounded audit metadata for downstream Godot adapter authoring.

    Roadmap: C6.2, C3.1
    Side effects: Writes summary text to stdout.
    """
    morphs = sorted({
        key.name
        for mesh in meshes
        if mesh.data.shape_keys
        for key in mesh.data.shape_keys.key_blocks
        if key.name != "Basis"
    })
    bones = [bone.name for bone in armature.data.bones]
    print(
        "LOCAL_MMD_EXPORT_PASS "
        f"meshes={len(meshes)} bones={len(bones)} morphs={len(morphs)}"
    )
    print(f"LOCAL_MMD_BONES {bones[:80]}")
    print(f"LOCAL_MMD_MORPHS {morphs[:80]}")
    for mesh in meshes:
        for slot in mesh.material_slots:
            material = slot.material
            if material is None or material.node_tree is None:
                continue
            images = [
                str(node.image.filepath)
                for node in material.node_tree.nodes
                if node.type == "TEX_IMAGE" and node.image
            ]
            print(f"LOCAL_MMD_MATERIAL name={material.name!r} images={images}")


def main() -> None:
    """Run deterministic, local-only PMX to GLB conversion.

    Roadmap: C6.1, C6.2, C3.1, O4
    Side effects: Reads caller-owned files and writes one ignored GLB.
    """
    addon_root, input_path, output_path = parse_args()
    reset_scene()
    register_mmd_tools(addon_root)
    meshes, armature = import_pmx(input_path)
    normalize_materials(meshes)
    select_export_objects(meshes, armature)
    export_glb(output_path)
    describe_model(meshes, armature)


if __name__ == "__main__":
    main()
