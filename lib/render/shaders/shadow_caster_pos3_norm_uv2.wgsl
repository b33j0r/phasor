struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) clip0: vec4<f32>,
    @location(4) clip1: vec4<f32>,
    @location(5) clip2: vec4<f32>,
    @location(6) clip3: vec4<f32>,
};

@vertex
fn vs_main(input: VertexIn) -> @builtin(position) vec4<f32> {
    let clip_model = mat4x4<f32>(input.clip0, input.clip1, input.clip2, input.clip3);
    return clip_model * vec4<f32>(input.position, 1.0);
}
