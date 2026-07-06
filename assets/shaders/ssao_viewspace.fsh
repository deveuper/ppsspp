#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform sampler2D sampler0;
uniform sampler2D sampler3;
uniform vec2 u_texelDelta;
uniform vec4 u_setting;
uniform mat4 u_invProjection;

varying vec2 v_texcoord0;

// Reconstruct view-space position from depth buffer value.
// u_invProjection already bakes the NDC correction (OpenGL z [-1,1] vs D3D/Vulkan [0,1]).
vec3 viewPosFromDepth(float depth, vec2 uv) {
	// Clip-space coordinates from texture coords and depth.
	// We assume NDC xy ranges [-1, 1] with origin at center.
	float x = uv.x * 2.0 - 1.0;
	float y = uv.y * 2.0 - 1.0;
	// ndcZ = depth (zero branch — correction baked into u_invProjection)
	vec4 clipPos = vec4(x, y, depth, 1.0);
	vec4 viewPos = u_invProjection * clipPos;
	return viewPos.xyz / viewPos.w;
}

// Pseudo-random noise in [0, 1].
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
	float intensity = u_setting.x;
	float radius = u_setting.y;
	if (radius < 0.001) radius = 0.5;

	// Apply intensity to the radius so the user has meaningful control.
	radius *= 0.01;

	vec4 color = texture2D(sampler0, v_texcoord0);
	float centerDepth = texture2D(sampler3, v_texcoord0).r;
	vec3 viewPos = viewPosFromDepth(centerDepth, v_texcoord0);

	// Hemisphere kernel samples (random rotations per pixel).
	// This is a small fixed set of 3D vectors roughly distributed on a hemisphere.
	// In a production implementation, these would be in a uniform buffer.
	vec3 kernel[8];
	kernel[0] = vec3( 0.0,  0.0,  1.0);
	kernel[1] = vec3( 0.6,  0.2,  0.8);
	kernel[2] = vec3(-0.4,  0.5,  0.7);
	kernel[3] = vec3( 0.3, -0.6,  0.7);
	kernel[4] = vec3(-0.5, -0.3,  0.8);
	kernel[5] = vec3( 0.7, -0.1,  0.6);
	kernel[6] = vec3(-0.2,  0.7,  0.6);
	kernel[7] = vec3( 0.1, -0.8,  0.5);

	// Random rotation per pixel to reduce banding.
	float angle = hash(v_texcoord0) * 6.2831853;
	float c = cos(angle);
	float s = sin(angle);
	mat2 rot = mat2(c, s, -s, c);

	float occlusion = 0.0;

	for (int i = 0; i < 8; i++) {
		vec3 sampleDir = kernel[i];
		// Jitter the sample direction.
		vec2 offset = rot * sampleDir.xy * radius;
		vec2 sampleUV = v_texcoord0 + offset;

		// Edge-tap: clamp to edge.
		sampleUV = clamp(sampleUV, 0.0, 1.0);

		float sampleDepth = texture2D(sampler3, sampleUV).r;
		vec3 samplePos = viewPosFromDepth(sampleDepth, sampleUV);

		// Compute occlusion: if the sample point is in front of the tangent plane
		// (relative to viewPos), it contributes to occlusion.
		vec3 diff = samplePos - viewPos;
		float dist = length(diff);
		float rangeCheck = smoothstep(radius * 2.0, 0.0, dist);
		// Dot product: if sample is in the same direction as normal (which we approximate
		// as towards the camera for simplicity), it's occluding.
		float dotNV = max(dot(normalize(diff), vec3(0.0, 0.0, 1.0)), 0.0);
		occlusion += dotNV * rangeCheck;
	}

	float ao = 1.0 - (occlusion / 8.0) * intensity * 0.5;
	ao = clamp(ao, 0.0, 1.0);

	gl_FragColor = vec4(color.rgb * ao, color.a);
}

// === SSR (Screen-Space Reflections) skeleton ===
// To implement SSR, extend this shader with:
// 1. For each pixel, compute the reflected view ray: reflect(normalize(viewPos), normal).
// 2. March the reflected ray in screen space, re-projecting each step to UV.
// 3. At each step, compare the reprojected depth to the stored depth buffer value.
// 4. If they match within a tolerance, return the color from sampler0 at that UV.
// 5. Fall back to SSAO or environment map when no intersection is found.
//
// Uniforms needed:
//   u_invProjection  (already provided)
//   u_projMatrix     (forward projection, for reprojection)
//   u_resolution     (screen size for ray stepping)
//
// Key constants to tune:
//   MAX_STEPS = 64       — number of ray march steps
//   THICKNESS = 0.1      — depth buffer thickness tolerance
//   BINARY_SEARCH = 4    — refinement steps after initial hit
