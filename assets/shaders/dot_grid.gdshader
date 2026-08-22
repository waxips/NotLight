// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode unshaded;

uniform vec4 background_color : source_color = vec4(0.9725, 0.9647, 0.9255, 1.0);
uniform vec4 minor_dot_color : source_color = vec4(0.16, 0.27, 0.20, 0.18);
uniform vec4 major_dot_color : source_color = vec4(0.14, 0.35, 0.23, 0.24);
uniform vec4 origin_color : source_color = vec4(0.137, 0.498, 0.322, 0.28);
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 camera_position = vec2(0.0, 0.0);
uniform float zoom = 1.0;
uniform float grid_world_size = 32.0;
uniform float dot_scale = 1.0;

float soft_circle(vec2 delta_pixels, float radius) {
	float distance_to_center = length(delta_pixels);
	float antialias_width = max(fwidth(distance_to_center), 0.65);
	return 1.0 - smoothstep(radius - antialias_width, radius + antialias_width, distance_to_center);
}

float soft_line(float distance_to_line, float half_width) {
	float antialias_width = max(fwidth(distance_to_line), 0.65);
	return 1.0 - smoothstep(half_width - antialias_width, half_width + antialias_width, distance_to_line);
}

void fragment() {
	vec2 safe_viewport = max(viewport_size, vec2(1.0));
	float safe_zoom = max(zoom, 0.001);
	vec2 screen_position = UV * safe_viewport;

	float safe_grid_world_size = max(grid_world_size, 0.001);
	float screen_spacing = safe_grid_world_size * safe_zoom;

	vec2 world_position = camera_position + (screen_position - safe_viewport * 0.5) / safe_zoom;
	vec2 grid_coordinate = world_position / safe_grid_world_size;
	vec2 nearest_grid = floor(grid_coordinate + vec2(0.5));
	vec2 delta_pixels = (grid_coordinate - nearest_grid) * screen_spacing;

	vec2 major_remainder = mod(abs(nearest_grid), vec2(4.0));
	float is_major = step(major_remainder.x, 0.01) * step(major_remainder.y, 0.01);
	float dot_radius = mix(1.22, 1.78, is_major) * max(dot_scale, 0.5);
	float dot_mask = soft_circle(delta_pixels, dot_radius);
	vec4 selected_dot_color = mix(minor_dot_color, major_dot_color, is_major);

	vec3 final_rgb = mix(background_color.rgb, selected_dot_color.rgb, dot_mask * selected_dot_color.a);

	vec2 origin_screen = (-camera_position) * safe_zoom + safe_viewport * 0.5;
	vec2 origin_delta = abs(screen_position - origin_screen);
	float horizontal = soft_line(origin_delta.y, 0.75) * (1.0 - step(7.5, origin_delta.x));
	float vertical = soft_line(origin_delta.x, 0.75) * (1.0 - step(7.5, origin_delta.y));
	float origin_mask = max(horizontal, vertical) * origin_color.a;
	final_rgb = mix(final_rgb, origin_color.rgb, origin_mask);

	COLOR = vec4(final_rgb, background_color.a);
}
