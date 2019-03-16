//
//  Shaders.metal
//  CubeMapping Shared
//
//  Created by LEE CHUL HYUN on 3/13/19.
//  Copyright © 2019 LEE CHUL HYUN. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

// some common indices of refraction
constant float kEtaAir = 1.000277;
//constant float kEtaWater = 1.333;
constant float kEtaGlass = 1.5;

constant float kEtaRatio = kEtaAir / kEtaGlass;


typedef struct
{
    float3 position [[attribute(0)]];
} EnvironmentVertex;

typedef struct
{
    float4 position [[position]];
    float4 texCoord;
} EnvironmentColorInOut;


vertex EnvironmentColorInOut environmentVertexShader(EnvironmentVertex in [[stage_in]],
                               constant EnvironmentUniforms & uniforms [[ buffer(BufferIndexUniforms) ]]) {
    
    EnvironmentColorInOut out;
    
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    out.texCoord = position;
    
    return out;
}

fragment float4 environmentFragmentShader(EnvironmentColorInOut in [[stage_in]],
                                    constant EnvironmentUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                    texturecube<float> cubeTexture [[texture(0)]],
                                    sampler cubeSampler [[sampler(0)]])
{
    float3 texCoords = float3(in.texCoord.x, in.texCoord.y, in.texCoord.z);
    return cubeTexture.sample(cubeSampler, texCoords);
}


typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float4 texCoord;
} ColorInOut;

//vertex ColorInOut vertexShader(Vertex in [[stage_in]],
//                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]]) {
//
//    ColorInOut out;
//
//    float4 position = float4(in.position, 1.0);
//    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
//    out.texCoord = position;
//
//    return out;
//}
//
//vertex ColorInOut vertexShader(device Vertex* vertices [[buffer(0)]],
//                               constant CubeUniforms & uniforms [[ buffer(1) ]],
//                               uint vid [[vertex_id]])
//{
//    ColorInOut out;
//
//    Vertex in = vertices[vid];
//    float4 position = float4(in.position, 1.0);
//    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
//    out.texCoord = position;
//
//    return out;
//}

vertex ColorInOut vertex_reflect(Vertex inVertex [[stage_in]],
                                      constant CubeUniforms &uniforms [[buffer(1)]],
                                 constant PerInstanceUniforms* perInstanceUniforms [[buffer(2)]],
                                 uint iid [[instance_id]])
{
    float4 modelPosition = float4(inVertex.position, 1);
    float4 modelNormal = float4(inVertex.normal, 0);
    
    float4 worldCameraPosition = uniforms.worldCameraPosition;
    float4 worldPosition = perInstanceUniforms[iid].modelMatrix * modelPosition;
    float4 worldNormal = normalize(perInstanceUniforms[iid].normalMatrix * modelNormal);
    float4 worldEyeDirection = normalize(worldPosition - worldCameraPosition);
    
    ColorInOut outVert;
    outVert.position = uniforms.projectionMatrix * uniforms.viewMatrix * perInstanceUniforms[iid].modelMatrix * modelPosition;
    outVert.texCoord = reflect(worldEyeDirection, worldNormal);
    
    return outVert;
}

vertex ColorInOut vertex_refract(Vertex inVertex             [[stage_in]],
                                      constant CubeUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                 constant PerInstanceUniforms* perInstanceUniforms [[buffer(2)]],
                                 uint iid [[instance_id]])
{
    float4 modelPosition = float4(inVertex.position, 1);
    float4 modelNormal = float4(inVertex.normal, 0);
    
    float4 worldCameraPosition = uniforms.worldCameraPosition;
    float4 worldPosition = perInstanceUniforms[iid].modelMatrix * modelPosition;
    float4 worldNormal = normalize(perInstanceUniforms[iid].normalMatrix * modelNormal);
    float4 worldEyeDirection = normalize(worldPosition - worldCameraPosition);
    
    ColorInOut outVert;
    outVert.position = uniforms.projectionMatrix * uniforms.viewMatrix * perInstanceUniforms[iid].modelMatrix * modelPosition;
    outVert.texCoord = refract(worldEyeDirection, worldNormal, kEtaRatio);
    
    return outVert;
}

fragment float4 fragment_cube_lookup(ColorInOut vert          [[stage_in]],
                                    texturecube<float> cubeTexture [[texture(0)]],
                                    sampler cubeSampler           [[sampler(0)]])
{
    float3 texCoords = float3(vert.texCoord.x, vert.texCoord.y, vert.texCoord.z);
    return cubeTexture.sample(cubeSampler, texCoords);
}
