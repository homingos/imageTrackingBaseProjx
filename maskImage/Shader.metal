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
    float4 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float2 texCoords;
};

vertex VertexOutput vertexShaderWithSineWave(VertexInput input [[stage_in]],
                                             constant float& time [[buffer(1)]],
                                             uint vertexID [[vertex_id]]) {
    VertexOutput output;
    
    // Sine wave animation on x-axis
    float xOffset = sin(time * 2.0) * 0.5; // Adjust multipliers to change wave characteristics
    
    // Apply sine wave offset to x position
    float4 animatedPosition = input.position;
    animatedPosition.x += xOffset;
    
    output.position = float4(animatedPosition.xy, 1.0);
    output.texCoords = input.texCoords;
    return output;
}

fragment float4 fragmentShader(VertexOutput input [[stage_in]],
                               texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    
    return texture.sample(textureSampler, input.texCoords);
}
