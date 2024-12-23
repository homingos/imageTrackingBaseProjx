//
//  Shader.metal
//  maskImage
//
//  Created by Vishwas Prakash on 18/12/24.
//

#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOutput vertexShader(VertexInput in [[stage_in]],
                              constant float4x4 *matrices [[buffer(1)]]) {
    VertexOutput out;
    
    // Get matrices
    float4x4 modelMatrix = matrices[0];
    float4x4 viewMatrix = matrices[1];
    float4x4 projectionMatrix = matrices[2];
    
    // Transform vertex
    float4 worldPosition = modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = viewMatrix * worldPosition;
    out.position = projectionMatrix * viewPosition;
    
    return out;
}

fragment float4 fragmentShader(VertexOutput in [[stage_in]]) {
    // Return semi-transparent green
    return float4(0.0, 1.0, 0.0, 0.8);
}

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    uint textureIndex [[attribute(2)]];  // Added to identify which texture to use
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    uint textureIndex;  // Pass the texture index to fragment shader
};

vertex VertexOut vertexShaderDebug(VertexIn in [[stage_in]],
                                constant float4x4 *matrices [[buffer(1)]]) {
    VertexOut out;
    
    float4x4 modelMatrix = matrices[0];
    float4x4 viewMatrix = matrices[1];
    float4x4 projectionMatrix = matrices[2];
    float4x4 modelViewMatrix = viewMatrix * modelMatrix;
    
    out.position = projectionMatrix * modelViewMatrix * float4(in.position, 1.0);
    out.texCoord = in.texCoord;
    out.textureIndex = in.textureIndex;
    
    return out;
}

fragment float4 fragmentShaderDebug(VertexOut in [[stage_in]],
                                  array<texture2d<float>, 8> textures [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]]) {
    
    // Sample from the appropriate texture based on the index
    float4 color = textures[in.textureIndex].sample(textureSampler, in.texCoord);
    
    return color;
}
