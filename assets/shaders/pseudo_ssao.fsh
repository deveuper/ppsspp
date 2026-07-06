#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D sampler0;
uniform sampler2D sampler3;
uniform vec2 u_texelDelta;
uniform vec4 u_setting;

varying vec2 v_texcoord0;

// Pseudo SSAO: approximate ambient occlusion by comparing depth at neighboring pixels.
// Depth texture is accessed via sampler3 (binding 3), color via sampler0 (binding 0).

void main() {
	float intensity = u_setting.x;
	float radius = u_setting.y;
	if (radius < 0.5) radius = 2.0;

	vec4 color = texture2D(sampler0, v_texcoord0);
	float centerDepth = texture2D(sampler3, v_texcoord0).r;

	// Sample neighboring depths in a 4-direction cross pattern.
	float occlusion = 0.0;
	float total = 0.0;

	// 8-sample ring
	vec2 offsets[8];
	offsets[0] = vec2(-1.0, -1.0);
	offsets[1] = vec2( 0.0, -1.0);
	offsets[2] = vec2( 1.0, -1.0);
	offsets[3] = vec2(-1.0,  0.0);
	offsets[4] = vec2( 1.0,  0.0);
	offsets[5] = vec2(-1.0,  1.0);
	offsets[6] = vec2( 0.0,  1.0);
	offsets[7] = vec2( 1.0,  1.0);

	for (int i = 0; i < 8; i++) {
		vec2 uv = v_texcoord0 + offsets[i] * u_texelDelta * radius;
		float sampleDepth = texture2D(sampler3, uv).r;

		// Weight by depth difference: if sample is closer (smaller), it occludes.
		float diff = centerDepth - sampleDepth;
		float rangeCheck = smoothstep(0.0, 0.1, abs(diff));
		occlusion += step(0.0, diff) * rangeCheck;
		total += 1.0;
	}

	float ao = 1.0 - (occlusion / total) * intensity * 0.6;
	ao = clamp(ao, 0.0, 1.0);

	gl_FragColor = vec4(color.rgb * ao, color.a);
}
