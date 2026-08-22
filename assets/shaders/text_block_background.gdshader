// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode unshaded;

// MultiMesh custom data stores the original block size in world pixels.
varying vec4 block_data;

void vertex() {
	block_data = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 block_size = max(block_data.rg, vec2(1.0));
	float corner_radius = min(14.0, min(block_size.x, block_size.y) * 0.22);
	vec2 local_point = (UV - vec2(0.5)) * block_size;
	vec2 half_extents = max(block_size * 0.5 - vec2(corner_radius), vec2(0.0));
	vec2 distance_axis = abs(local_point) - half_extents;
	float sdf_value = length(max(distance_axis, vec2(0.0))) + min(max(distance_axis.x, distance_axis.y), 0.0) - corner_radius;

	// A fixed one-pixel transition is intentionally used instead of derivative
	// functions here. The renderer targets Godot's GL Compatibility path too.
	float edge_softness = 1.0;
	float shape_alpha = 1.0 - smoothstep(-edge_softness, edge_softness, sdf_value);
	float inner_alpha = 1.0 - smoothstep(-edge_softness, edge_softness, sdf_value + 1.25);
	vec4 block_color = COLOR;
	vec3 border_color = mix(block_color.rgb, vec3(0.18, 0.25, 0.20), 0.16);
	vec3 final_color = mix(border_color, block_color.rgb, inner_alpha);
	COLOR = vec4(final_color, block_color.a * shape_alpha);
}
