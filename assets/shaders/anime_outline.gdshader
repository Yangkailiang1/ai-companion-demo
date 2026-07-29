// Roadmap: C8.3, S1.2
// Responsibility: Draw a scale-correct, unlit silhouette shell for character
// materials only; color and local-space width are supplied by the adapter.
// Collaborators: AnimeRenderAdapter
// Tests: scripts/debug/anime_character_rendering_check.gd

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.055, 0.045, 0.075, 1.0);
uniform float outline_width = 0.007;
uniform sampler2D alpha_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_alpha_texture = false;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	if (use_alpha_texture && texture(alpha_texture, UV).a < 0.12) {
		discard;
	}
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
