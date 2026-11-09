#include "projection.hpp"
#include <cassert>
#include <cmath>
int main() {
    Camera c{{0, 0, 0}, 0, 0, 90};
    Point2 p{};
    assert(project(c, {100, 0, 0}, 800, 600, p));
    assert(std::abs(p.x - 400) < 0.001 && std::abs(p.y - 300) < 0.001);
    assert(project(c, {100, -50, 0}, 800, 600, p) && p.x > 400);
    assert(project(c, {100, 0, 50}, 800, 600, p) && p.y < 300);
    assert(!project(c, {-1, 0, 0}, 800, 600, p));
    c.yaw = 90;
    assert(project(c, {0, 100, 0}, 800, 600, p) && std::abs(p.x - 400) < 0.001);
    c.pitch = -45; c.yaw = 0;
    assert(project(c, {100, 0, 100}, 800, 600, p) && std::abs(p.y - 300) < 0.001);
    c.fov = 0;
    assert(!project(c, {100, 0, 0}, 800, 600, p));
}
