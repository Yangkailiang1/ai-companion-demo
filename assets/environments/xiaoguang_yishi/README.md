# Xiaoguang Yishi Scene

Source archive: `/Users/yangkailiang/Documents/ai_games/scene/晓光忆时.zip`

The source readme says the Blender scene targets Blender 3.6 and is not guaranteed
for Blender 4.0+. Blender 5.0.1 can open it with camera-driver warnings, so this
project imports it as a preview asset only until visual QA is complete.

Current Godot status:

- Blender 5.0.1 export succeeds and produces `xiaoguang_yishi.glb`.
- Godot 4.6.1 imports and instantiates the preview scene.
- The preview hides the giant helper cube (`立方体`), ceiling, and one wall so the
  imported studio can be inspected from the front.
- Visual fidelity is not yet production-ready: the original Blender render uses
  lighting/material effects that do not survive the simple GLB export. To match
  the source preview, re-export from Blender 3.6 and/or bake textures, shadows,
  window light, and volumetric effects for Godot.

Export target:

```text
assets/environments/xiaoguang_yishi/xiaoguang_yishi.glb
```

Run:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background \
  /private/tmp/xiaoguang_yishi_extract/撮影スタジオblender版\ 配布用.blend \
  --python tools/blender/export_xiaoguang_yishi.py
```

Validate:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --log-file /private/tmp/ai_companion_godot_xiaoguang.log \
  --path . \
  --script scripts/debug/xiaoguang_scene_check.gd
```
