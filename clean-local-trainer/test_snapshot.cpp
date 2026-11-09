#include "snapshot.hpp"
#include <cassert>
#include <string>
int main() {
    Snapshot s;
    const std::string header = "LT1\r\nCAM 0 0 28 -1 90 90\r\n";
    assert(parse_snapshot(header + "P 1 10 20 30 -36 36\r\nP 2 1 2 3 -18 18\r\nEND\r\n", s));
    assert(s.players.size() == 2 && s.players[0].team == 1 && s.players[1].team == 2);
    assert(!parse_snapshot(header + "P 1 10 20 30 -36 36\n", s));
    assert(!parse_snapshot(header + "P 4 10 20 30 -36 36\nEND\n", s));
    assert(!parse_snapshot("LT1\nCAM 0 0 0 0 0 0\nEND\n", s));
    assert(!parse_snapshot(header + "P 1 1 2 3 -101 36\nEND\n", s));
    std::string many = header;
    for (int i = 0; i < 33; ++i) many += "P 1 0 0 0 -36 36\n";
    assert(!parse_snapshot(many + "END\n", s));
}
