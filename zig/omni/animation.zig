const std = @import("std");

pub const SpringConfig = struct {
    /// Approximate settling duration in seconds.
    response: f64 = 0.35,
    /// Damping ratio where 1.0 is critically damped.
    damping_ratio: f64 = 0.85,
};

pub fn clamp01(value: f64) f64 {
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
}

pub fn cubicEaseInOut(t_raw: f64) f64 {
    const t = clamp01(t_raw);
    if (t < 0.5) {
        return 4.0 * t * t * t;
    }
    const shifted = (-2.0 * t) + 2.0;
    return 1.0 - ((shifted * shifted * shifted) / 2.0);
}

/// Critically/under-damped spring progress from 0->1.
pub fn springProgress(config: SpringConfig, t_raw: f64) f64 {
    const t = if (t_raw < 0.0) 0.0 else t_raw;
    if (t == 0.0) return 0.0;

    const response = @max(config.response, 0.0001);
    const zeta = @max(0.01, config.damping_ratio);
    const omega_n = 2.0 * std.math.pi / response;

    if (zeta >= 1.0) {
        // Over/critically damped approximation.
        const envelope = std.math.exp(-omega_n * t);
        return clamp01(1.0 - envelope * (1.0 + omega_n * t));
    }

    const omega_d = omega_n * std.math.sqrt(1.0 - (zeta * zeta));
    const envelope = std.math.exp(-zeta * omega_n * t);
    const phase = omega_d * t;
    const blend = std.math.cos(phase) + ((zeta / std.math.sqrt(1.0 - (zeta * zeta))) * std.math.sin(phase));
    return clamp01(1.0 - (envelope * blend));
}

test "cubic ease bounds" {
    try std.testing.expectEqual(@as(f64, 0.0), cubicEaseInOut(0.0));
    try std.testing.expectEqual(@as(f64, 1.0), cubicEaseInOut(1.0));
    try std.testing.expect(cubicEaseInOut(0.25) < cubicEaseInOut(0.75));
}

test "spring progress converges" {
    const cfg = SpringConfig{ .response = 0.4, .damping_ratio = 0.85 };
    try std.testing.expectEqual(@as(f64, 0.0), springProgress(cfg, 0.0));
    try std.testing.expect(springProgress(cfg, 2.0) > 0.98);
}
