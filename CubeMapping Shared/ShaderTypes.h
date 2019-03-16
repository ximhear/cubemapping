//
//  ShaderTypes.h
//  CubeMapping Shared
//
//  Created by LEE CHUL HYUN on 3/13/19.
//  Copyright © 2019 LEE CHUL HYUN. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexUniforms  = 1,
    BufferIndexPerInstanceUniforms      = 2
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeNormal  = 1,
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexColor    = 0,
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
} EnvironmentUniforms;

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    vector_float4 worldCameraPosition;
} CubeUniforms;

typedef struct
{
    matrix_float4x4 modelMatrix;
    matrix_float4x4 normalMatrix;
} PerInstanceUniforms;

#endif /* ShaderTypes_h */

