import "../../../shared/shared.slang";

struct VertRoot {
  float3 *positions;
  float4 *colors;
};

struct VSOut {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VSOut shader_vert(uint vid: SV_VertexID,
                  GraphicsPipelineData<VertRoot, void, void> data) {
  float3 p = data.vert.positions[vid];
  float4 c = data.vert.colors[vid];

  VSOut o;
  o.pos = float4(p, 1.0);
  o.color = c;
  return o;
}

[shader("fragment")]
float4 shader_frag(VSOut input, GraphicsPipelineData<void, void, void> data)
    : SV_Target {
  return input.color;
}
