const std = @import("std");
const common = @import("common");
const resources = @import("resources.zig");
const stb_image = @import("stb_image");

pub const BuildOptions = struct {
    intensity: f32 = 1.0,
    diffuse_strength: f32 = 1.0,
    specular_strength: f32 = 1.0,
    dominant_threshold_scale: f32 = 4.0,
};

pub fn buildEnvironmentLightFromHdrBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: BuildOptions,
) !resources.EnvironmentLight {
    const image = try decodeHdrFromBytes(allocator, bytes);
    defer allocator.free(image.data);
    return buildEnvironmentLight(image.width, image.height, image.data, options);
}

const HdrImage = struct {
    width: u32,
    height: u32,
    data: []f32,
};

fn decodeHdrFromBytes(allocator: std.mem.Allocator, bytes: []const u8) !HdrImage {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    const data_ptr = stb_image.c.stbi_loadf_from_memory(
        bytes.ptr,
        @intCast(bytes.len),
        &width,
        &height,
        &channels,
        4,
    );
    if (data_ptr == null) return error.ImageLoadFailed;
    defer stb_image.c.stbi_image_free(data_ptr);

    const pixel_count: usize = @intCast(width * height);
    const data = try allocator.alloc(f32, pixel_count * 4);
    const src: [*]const f32 = @ptrCast(@alignCast(data_ptr));
    @memcpy(data, src[0 .. pixel_count * 4]);

    return .{
        .width = @intCast(width),
        .height = @intCast(height),
        .data = data,
    };
}

fn buildEnvironmentLight(
    width: u32,
    height: u32,
    rgba: []const f32,
    options: BuildOptions,
) resources.EnvironmentLight {
    var sh = [_][3]f32{[_]f32{ 0.0, 0.0, 0.0 }} ** 9;
    var total_luminance: f64 = 0.0;
    var total_weight: f64 = 0.0;
    const width_f = @as(f64, @floatFromInt(width));
    const height_f = @as(f64, @floatFromInt(height));
    const dphi = (2.0 * std.math.pi) / width_f;
    const dtheta = std.math.pi / height_f;

    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const v = (@as(f64, @floatFromInt(y)) + 0.5) / height_f;
        const latitude = (0.5 - v) * std.math.pi;
        const cos_lat = std.math.cos(latitude);
        const solid_angle = cos_lat * dphi * dtheta;
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const u = (@as(f64, @floatFromInt(x)) + 0.5) / width_f;
            const longitude = (u - 0.5) * 2.0 * std.math.pi;
            const dir = directionFromSpherical(longitude, latitude);
            const basis = shBasis(dir);
            const pixel_index: usize = @intCast((y * width + x) * 4);
            const rgb = [3]f64{
                rgba[pixel_index + 0],
                rgba[pixel_index + 1],
                rgba[pixel_index + 2],
            };
            const weight = solid_angle;
            const luminance = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
            total_luminance += luminance * weight;
            total_weight += weight;
            var i: usize = 0;
            while (i < sh.len) : (i += 1) {
                const weighted_basis = basis[i] * weight;
                sh[i][0] += @floatCast(rgb[0] * weighted_basis);
                sh[i][1] += @floatCast(rgb[1] * weighted_basis);
                sh[i][2] += @floatCast(rgb[2] * weighted_basis);
            }
        }
    }

    const avg_luminance = if (total_weight > 0.0) total_luminance / total_weight else 0.0;
    const dominant_threshold = avg_luminance * options.dominant_threshold_scale;
    var dominant_dir_accum = common.Vec3{};
    var dominant_color_accum = [3]f64{ 0.0, 0.0, 0.0 };
    var dominant_weight: f64 = 0.0;

    y = 0;
    while (y < height) : (y += 1) {
        const v = (@as(f64, @floatFromInt(y)) + 0.5) / height_f;
        const latitude = (0.5 - v) * std.math.pi;
        const cos_lat = std.math.cos(latitude);
        const solid_angle = cos_lat * dphi * dtheta;
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const u = (@as(f64, @floatFromInt(x)) + 0.5) / width_f;
            const longitude = (u - 0.5) * 2.0 * std.math.pi;
            const dir = directionFromSpherical(longitude, latitude);
            const pixel_index: usize = @intCast((y * width + x) * 4);
            const r = @as(f64, rgba[pixel_index + 0]);
            const g = @as(f64, rgba[pixel_index + 1]);
            const b = @as(f64, rgba[pixel_index + 2]);
            const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            const excess = @max(0.0, luminance - dominant_threshold);
            if (excess <= 0.0) continue;
            const weight = excess * solid_angle;
            dominant_dir_accum = dominant_dir_accum.add(dir.scale(@floatCast(weight)));
            dominant_color_accum[0] += r * weight;
            dominant_color_accum[1] += g * weight;
            dominant_color_accum[2] += b * weight;
            dominant_weight += weight;
        }
    }

    if (dominant_weight <= 0.0) {
        dominant_dir_accum = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
        dominant_color_accum = .{ avg_luminance, avg_luminance, avg_luminance };
        dominant_weight = 1.0;
    }

    var irradiance_sh = [_][4]f32{[_]f32{ 0.0, 0.0, 0.0, 0.0 }} ** 9;
    const convolution = [_]f32{
        @floatCast(std.math.pi),
        @floatCast((2.0 * std.math.pi) / 3.0),
        @floatCast((2.0 * std.math.pi) / 3.0),
        @floatCast((2.0 * std.math.pi) / 3.0),
        @floatCast(std.math.pi / 4.0),
        @floatCast(std.math.pi / 4.0),
        @floatCast(std.math.pi / 4.0),
        @floatCast(std.math.pi / 4.0),
        @floatCast(std.math.pi / 4.0),
    };
    var i: usize = 0;
    while (i < sh.len) : (i += 1) {
        irradiance_sh[i] = .{
            sh[i][0] * convolution[i],
            sh[i][1] * convolution[i],
            sh[i][2] * convolution[i],
            0.0,
        };
    }

    return .{
        .enabled = true,
        .intensity = options.intensity,
        .diffuse_strength = options.diffuse_strength,
        .specular_strength = options.specular_strength,
        .dominant_direction = dominant_dir_accum.normalize(),
        .dominant_color = .{
            .r = @floatCast(dominant_color_accum[0] / dominant_weight),
            .g = @floatCast(dominant_color_accum[1] / dominant_weight),
            .b = @floatCast(dominant_color_accum[2] / dominant_weight),
            .a = 1.0,
        },
        .irradiance_sh = irradiance_sh,
    };
}

fn directionFromSpherical(longitude: f64, latitude: f64) common.Vec3 {
    const cos_lat = std.math.cos(latitude);
    return .{
        .x = @floatCast(std.math.sin(longitude) * cos_lat),
        .y = @floatCast(std.math.sin(latitude)),
        .z = @floatCast(std.math.cos(longitude) * cos_lat),
    };
}

fn shBasis(direction: common.Vec3) [9]f64 {
    const x = @as(f64, direction.x);
    const y = @as(f64, direction.y);
    const z = @as(f64, direction.z);
    return .{
        0.282095,
        0.488603 * y,
        0.488603 * z,
        0.488603 * x,
        1.092548 * x * y,
        1.092548 * y * z,
        0.315392 * (3.0 * z * z - 1.0),
        1.092548 * x * z,
        0.546274 * (x * x - y * y),
    };
}
