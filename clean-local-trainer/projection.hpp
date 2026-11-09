#pragma once
#include <cmath>

struct Vec3 { double x, y, z; };
struct Camera { Vec3 eye; double pitch, yaw, fov; };
struct Point2 { double x, y, depth; };

inline bool project(const Camera &c, const Vec3 &p, int width, int height, Point2 &out) {
    if (width <= 0 || height <= 0 || c.fov < 10 || c.fov > 160) return false;
    constexpr double pi = 3.14159265358979323846;
    const double pitch = c.pitch * pi / 180.0, yaw = c.yaw * pi / 180.0;
    const double cp = std::cos(pitch), sp = std::sin(pitch);
    const double cy = std::cos(yaw), sy = std::sin(yaw);
    const Vec3 d{p.x - c.eye.x, p.y - c.eye.y, p.z - c.eye.z};
    const double depth = d.x * cp * cy + d.y * cp * sy - d.z * sp;
    if (!std::isfinite(depth) || depth <= 1.0) return false;
    const double right = d.x * sy - d.y * cy;
    const double up = d.x * sp * cy + d.y * sp * sy + d.z * cp;
    const double focal = width / (2.0 * std::tan(c.fov * pi / 360.0));
    out = {width * 0.5 + focal * right / depth,
           height * 0.5 - focal * up / depth, depth};
    return std::isfinite(out.x) && std::isfinite(out.y);
}
