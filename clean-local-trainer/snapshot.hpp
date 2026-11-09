#pragma once
#include "projection.hpp"
#include <cmath>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

struct Player { int team; Vec3 origin; double bottom, top; };
struct Snapshot { Camera camera{}; std::vector<Player> players; };

inline bool parse_snapshot(const std::string &text, Snapshot &snapshot) {
    std::istringstream in(text);
    std::string line, kind;
    if (!std::getline(in, line) || (line != "LT1" && line != "LT1\r")) return false;
    if (!std::getline(in, line)) return false;
    std::istringstream cam(line);
    Snapshot next;
    if (!(cam >> kind >> next.camera.eye.x >> next.camera.eye.y >> next.camera.eye.z
              >> next.camera.pitch >> next.camera.yaw >> next.camera.fov) || kind != "CAM") return false;
    const auto &c = next.camera;
    if (!std::isfinite(c.eye.x) || !std::isfinite(c.eye.y) || !std::isfinite(c.eye.z)
        || !std::isfinite(c.pitch) || !std::isfinite(c.yaw) || !std::isfinite(c.fov)
        || c.fov < 10 || c.fov > 160) return false;
    bool end = false;
    while (std::getline(in, line)) {
        if (line == "END" || line == "END\r") { end = true; break; }
        std::istringstream row(line);
        Player p{};
        if (!(row >> kind >> p.team >> p.origin.x >> p.origin.y >> p.origin.z >> p.bottom >> p.top)
            || kind != "P" || (p.team != 1 && p.team != 2) || next.players.size() >= 32
            || !std::isfinite(p.origin.x) || !std::isfinite(p.origin.y) || !std::isfinite(p.origin.z)
            || !std::isfinite(p.bottom) || !std::isfinite(p.top)
            || p.bottom < -100 || p.top > 100 || p.top <= p.bottom) return false;
        next.players.push_back(p);
    }
    if (!end) return false;
    snapshot = std::move(next);
    return true;
}
