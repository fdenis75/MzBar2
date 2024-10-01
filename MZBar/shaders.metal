#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float2 position;
    float2 size;
    int renderType;
    int padding;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant VertexIn *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    VertexIn vertexIn = vertices[vertexID];
    
    VertexOut out;
    out.position = float4(uniforms.position + vertexIn.position * uniforms.size, 0.0, 1.0);
    out.texCoord = vertexIn.texCoord;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               constant float4 &backgroundColor [[buffer(2)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    switch (uniforms.renderType) {
        case 0: // Background
            return backgroundColor;
        case 1: // Thumbnail
            return tex.sample(textureSampler, in.texCoord);
        case 2: // Metadata
            float4 texColor = tex.sample(textureSampler, in.texCoord);
            // Assuming the metadata texture has a transparent background
            return float4(texColor.rgb, texColor.a * 0.8); // Adjust alpha for semi-transparency
        //efault:
           // return float4(1.0, 0.0, 0.0, 1.0); // Red color for error cases
    }
}
