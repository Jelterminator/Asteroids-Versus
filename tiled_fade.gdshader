shader_type canvas_item;

void fragment() {
    // 1. Continuous linear mapping to expand the world to a 3x3 layout.
    // Maps UV [0, 1] to [-1, 2] world units.
    vec2 world_uv = (UV * 3.0) - 1.0;
    
    // 2. Sample with explicit wrapping. 
    // This is required because ViewportTextures do not natively repeat in shaders.
    vec4 tex = texture(TEXTURE, fract(world_uv));
    
    // 3. Distance from the central tile (the Main Screen).
    // The central tile is UV [1/3, 2/3], so it's 1/6 away from the center (0.5).
    vec2 center_dist = abs(UV - 0.5);
    vec2 box_dist = max(center_dist - 0.1666667, 0.0);
    float dist = length(box_dist);
    
    // 4. Sharpened fade for selective visibility.
    // This keeps the central tile 100% opaque (dist == 0) and only shows 
    // enough of the neighbors (up to 0.1 units) to allow entities to 
    // 'bleed' across boundaries without being duplicated on the far side.
    float fade = 1.0 - smoothstep(0.0, 0.1, dist);
    
    // Preserve texture alpha while applying the spatial fade.
    COLOR = vec4(tex.rgb, tex.a * fade);
}

