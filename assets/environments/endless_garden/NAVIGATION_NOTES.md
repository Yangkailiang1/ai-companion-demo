# Endless Garden — Navigation Notes

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
