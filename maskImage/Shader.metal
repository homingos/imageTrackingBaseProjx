//
//  Shader.metal
//  RndMetal
//
//  Created by Vishwas Prakash on 17/12/24.
//
#include <metal_stdlib>
using namespace metal;

//rect
struct VertexInput {
    float3 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float2 texCoords;
    float layerZ;
};

vertex VertexOutput vertexShaderWithSineWave(VertexInput input [[stage_in]],
                                         constant float& time [[buffer(1)]],
                                         uint vertexID [[vertex_id]]) {
    VertexOutput output;
    
    // Sine wave animation on x-axis
    float xOffset = sin(time * 2.0) * 0.5;
    
    // Apply sine wave offset to x position
    float3 animatedPosition = input.position;
    animatedPosition.z += time;
    
    // Preserve z coordinate for depth ordering
    output.position = float4(animatedPosition.xy, animatedPosition.z, 1.0);
    output.texCoords = input.texCoords;
    output.layerZ = input.position.z;  // Store z value for depth testing
    
    return output;
}

fragment float4 fragmentShader(VertexOutput input [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    // High-quality texture sampling configuration
    constexpr sampler textureSampler(
        mag_filter::linear,      // Linear magnification filtering
        min_filter::linear,      // Linear minification filtering
        mip_filter::linear,      // Linear mipmap filtering
        max_anisotropy(16),      // Maximum anisotropic filtering
        s_address::clamp_to_edge,
        t_address::clamp_to_edge
    );
    
    // Sample texture with high-quality settings
    float4 color = texture.sample(textureSampler, input.texCoords, bias(0.0));
    
    // Optional: Add edge detection to prevent pixelation at texture edges
    float2 textureSize = float2(texture.get_width(), texture.get_height());
    float2 texelSize = 1.0 / textureSize;
    
    // Sample neighboring pixels for edge smoothing
    float4 center = texture.sample(textureSampler, input.texCoords);
    float4 left = texture.sample(textureSampler, input.texCoords - float2(texelSize.x, 0));
    float4 right = texture.sample(textureSampler, input.texCoords + float2(texelSize.x, 0));
    float4 top = texture.sample(textureSampler, input.texCoords - float2(0, texelSize.y));
    float4 bottom = texture.sample(textureSampler, input.texCoords + float2(0, texelSize.y));
    
    // Average the samples for smoother edges
    color = (center + left + right + top + bottom) / 5.0;
    
    // Ensure proper alpha handling
    if (color.a < 0.01) {
        discard_fragment();
    }
    
    return color;
}
