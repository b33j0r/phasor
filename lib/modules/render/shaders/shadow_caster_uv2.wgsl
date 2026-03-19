struct VertexIn {
    @location(0) position: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) clip0: vec4<f32>,
    @location(3) clip1: vec4<f32>,
    @location(4) clip2: vec4<f32>,
    @location(5) clip3: vec4<f32>,
};

@vertex
fn vs_main(input: VertexIn) -> @builtin(position) vec4<f32> {
    let clip_model = mat4x4<f32>(input.clip0, input.clip1, input.clip2, input.clip3);
    return clip_model * vec4<f32>(input.position, 0.0, 1.0);
}
