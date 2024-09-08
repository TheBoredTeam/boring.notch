//
//  visualizer.metal
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 28/08/24.
//

#include <metal_stdlib>
using namespace metal;

vertex float4 vertexShader(uint vertexID [[vertex_id]],
                           constant float2 *vertices [[buffer(0)]]) {
    return float4(vertices[vertexID], 0, 1);
}

fragment float4 fragmentShader(constant float4 &color [[buffer(0)]]) {
    return color;
}
