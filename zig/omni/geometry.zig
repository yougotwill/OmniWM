pub const Rect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};
pub fn clampFloat(value: f64, min_value: f64, max_value: f64) f64 {
    if (value < min_value) return min_value;
    if (value > max_value) return max_value;
    return value;
}
pub fn roundToPhysicalPixel(value: f64, scale: f64) f64 {
    const safe_scale = @max(1.0, scale);
    return @round(value * safe_scale) / safe_scale;
}
pub fn roundRectToPhysicalPixels(rect: Rect, scale: f64) Rect {
    return .{
        .x = roundToPhysicalPixel(rect.x, scale),
        .y = roundToPhysicalPixel(rect.y, scale),
        .width = roundToPhysicalPixel(rect.width, scale),
        .height = roundToPhysicalPixel(rect.height, scale),
    };
}
pub fn pointInRect(point_x: f64, point_y: f64, rect: Rect) bool {
    if (rect.width < 0.0 or rect.height < 0.0) return false;
    const max_x = rect.x + rect.width;
    const max_y = rect.y + rect.height;
    return point_x >= rect.x and point_x <= max_x and point_y >= rect.y and point_y <= max_y;
}
pub fn isSubrangeWithinTotal(total: usize, start: usize, count: usize) bool {
    if (start > total) return false;
    return count <= total - start;
}
pub fn rangeContains(start: usize, count: usize, index: usize) bool {
    if (index < start) return false;
    return index - start < count;
}
