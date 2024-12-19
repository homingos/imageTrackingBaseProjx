//
//  Shader.metal
//  maskImage
//
//  Created by Vishwas Prakash on 18/12/24.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                              constant float4x4 *matrices [[buffer(1)]]) {
    VertexOut out;
    
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

fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    // Return semi-transparent green
    return float4(0.0, 1.0, 0.0, 0.8);
}


vertex VertexOut vertexShaderDebug(VertexIn in [[stage_in]],
                                constant float4x4 *matrices [[buffer(1)]]) {
    VertexOut out;
    
    float4x4 modelMatrix = matrices[0];    // Image anchor transform
    float4x4 viewMatrix = matrices[1];     // Camera transform
    float4x4 projectionMatrix = matrices[2];// Perspective projection
    float4x4 modelViewMatrix = viewMatrix * modelMatrix;
    
    out.position = projectionMatrix * modelViewMatrix * float4(in.position, 1.0);
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 fragmentShaderDebug(VertexOut in [[stage_in]],
                                  texture2d<float> diffuseTexture [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]]) {
    float4 color = diffuseTexture.sample(textureSampler, in.texCoord);
    return float4(color.rgb, color.a); 
}
