const abi = @import("abi_types.zig");
pub fn omni_axis_solve_impl(
    windows: [*c]const abi.OmniAxisInput,
    window_count: usize,
    available_space: f64,
    gap_size: f64,
    is_tabbed: u8,
    out: [*c]abi.OmniAxisOutput,
    out_count: usize,
) i32 {
    if (out_count < window_count) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_count == 0) return abi.OMNI_OK;
    if (window_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_INVALID_ARGS;
    if (windows == null or out == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (is_tabbed != 0) {
        return omni_axis_solve_tabbed_impl(windows, window_count, available_space, gap_size, out, out_count);
    }
    solveNormal(windows, window_count, available_space, gap_size, out);
    return abi.OMNI_OK;
}
pub fn omni_axis_solve_tabbed_impl(
    windows: [*c]const abi.OmniAxisInput,
    window_count: usize,
    available_space: f64,
    gap_size: f64,
    out: [*c]abi.OmniAxisOutput,
    out_count: usize,
) i32 {
    _ = gap_size;
    if (out_count < window_count) return abi.OMNI_ERR_INVALID_ARGS;
    if (window_count == 0) return abi.OMNI_OK;
    if (windows == null or out == null) return abi.OMNI_ERR_INVALID_ARGS;
    solveTabbedImpl(windows, window_count, available_space, out);
    return abi.OMNI_OK;
}
pub fn solveNormal(
    windows: [*c]const abi.OmniAxisInput,
    window_count: usize,
    available_space: f64,
    gap_size: f64,
    out: [*c]abi.OmniAxisOutput,
) void {
    const n = window_count;
    const gap_count: f64 = @floatFromInt(if (n > 0) n - 1 else 0);
    const total_gaps = gap_size * gap_count;
    const space_for_windows = available_space - total_gaps;
    if (space_for_windows <= 0) {
        for (0..n) |i| {
            out[i] = .{ .value = windows[i].min_constraint, .was_constrained = 1 };
        }
        return;
    }
    var values: [abi.MAX_WINDOWS]f64 = undefined;
    var is_fixed: [abi.MAX_WINDOWS]bool = undefined;
    var used_space: f64 = 0.0;
    for (0..n) |i| {
        values[i] = 0.0;
        is_fixed[i] = false;
    }
    for (0..n) |i| {
        const w = windows[i];
        if (w.has_fixed_value != 0) {
            var clamped = w.fixed_value;
            clamped = @max(clamped, w.min_constraint);
            if (w.has_max_constraint != 0) clamped = @min(clamped, w.max_constraint);
            values[i] = clamped;
            is_fixed[i] = true;
            used_space += clamped;
        } else if (w.is_constraint_fixed != 0) {
            values[i] = w.min_constraint;
            is_fixed[i] = true;
            used_space += values[i];
        }
    }
    const max_iterations = n + 1;
    var iteration: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        const remaining_space = space_for_windows - used_space;
        var total_weight: f64 = 0.0;
        for (0..n) |i| {
            if (!is_fixed[i]) total_weight += windows[i].weight;
        }
        if (total_weight <= 0.0) break;
        var any_violation = false;
        for (0..n) |i| {
            if (is_fixed[i]) continue;
            const proposed = remaining_space * (windows[i].weight / total_weight);
            if (proposed < windows[i].min_constraint) {
                values[i] = windows[i].min_constraint;
                is_fixed[i] = true;
                used_space += windows[i].min_constraint;
                any_violation = true;
                break;
            }
        }
        if (!any_violation) {
            for (0..n) |i| {
                if (!is_fixed[i]) {
                    values[i] = remaining_space * (windows[i].weight / total_weight);
                }
            }
            break;
        }
    }
    while (true) {
        var excess_space: f64 = 0.0;
        var capped_any = false;
        for (0..n) |i| {
            const w = windows[i];
            if (w.has_max_constraint != 0 and values[i] > w.max_constraint) {
                excess_space += values[i] - w.max_constraint;
                values[i] = w.max_constraint;
                is_fixed[i] = true;
                capped_any = true;
            }
        }
        if (!capped_any or excess_space <= 0.0) break;
        var remaining_weight: f64 = 0.0;
        for (0..n) |i| {
            if (!is_fixed[i]) remaining_weight += windows[i].weight;
        }
        if (remaining_weight <= 0.0) break;
        for (0..n) |i| {
            if (!is_fixed[i]) {
                values[i] += excess_space * (windows[i].weight / remaining_weight);
            }
        }
    }
    for (0..n) |i| {
        const w = windows[i];
        const was_constrained = is_fixed[i] and
            (values[i] == w.min_constraint or values[i] == w.max_constraint);
        out[i] = .{
            .value = @max(1.0, values[i]),
            .was_constrained = @intFromBool(was_constrained),
        };
    }
}
pub fn solveTabbedImpl(
    windows: [*c]const abi.OmniAxisInput,
    window_count: usize,
    available_space: f64,
    out: [*c]abi.OmniAxisOutput,
) void {
    const n = window_count;
    var max_min_constraint: f64 = 0.0;
    for (0..n) |i| {
        max_min_constraint = @max(max_min_constraint, windows[i].min_constraint);
    }
    var fixed_value: ?f64 = null;
    for (0..n) |i| {
        if (windows[i].has_fixed_value != 0) {
            fixed_value = windows[i].fixed_value;
            break;
        }
    }
    var shared_value: f64 = if (fixed_value) |fv|
        @max(fv, max_min_constraint)
    else
        @max(available_space, max_min_constraint);
    var min_max_constraint: ?f64 = null;
    for (0..n) |i| {
        const w = windows[i];
        if (w.has_max_constraint != 0) {
            if (min_max_constraint == null or w.max_constraint < min_max_constraint.?) {
                min_max_constraint = w.max_constraint;
            }
        }
    }
    if (min_max_constraint) |mc| {
        shared_value = @min(shared_value, mc);
    }
    shared_value = @max(1.0, shared_value);
    for (0..n) |i| {
        const w = windows[i];
        const was_constrained = shared_value == w.min_constraint or
            (w.has_max_constraint != 0 and shared_value == w.max_constraint);
        out[i] = .{
            .value = shared_value,
            .was_constrained = @intFromBool(was_constrained),
        };
    }
}
