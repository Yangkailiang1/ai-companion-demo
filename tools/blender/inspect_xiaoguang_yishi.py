"""Print source object transforms for Xiaoguang Yishi scene inspection."""

import bpy


def fmt_vec(vector) -> str:
    return "(" + ", ".join(f"{value:.4f}" for value in vector) + ")"


print("CAMERAS")
for obj in bpy.context.scene.objects:
    if obj.type == "CAMERA":
        print(
            f"name={obj.name} loc={fmt_vec(obj.location)} rot={fmt_vec(obj.rotation_euler)} "
            f"lens={obj.data.lens:.2f} angle={obj.data.angle:.4f}"
        )

print("MESHES")
rows = []
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        rows.append((max(obj.dimensions), obj.name, obj.dimensions, obj.location, obj.rotation_euler, obj.scale))

for max_dim, name, dims, loc, rot, scale in sorted(rows, reverse=True)[:40]:
    print(
        f"name={name} max={max_dim:.4f} dims={fmt_vec(dims)} loc={fmt_vec(loc)} "
        f"rot={fmt_vec(rot)} scale={fmt_vec(scale)}"
    )
