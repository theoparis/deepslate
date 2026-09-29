#include "game/raycast.hpp"

namespace ds {

int selection_boxes(const BlockInfo& bi, Box out[2]) {
  if (bi.flags & BF_NoTarget) return 0;
  if (bi.nbox > 0) {
    for (int i = 0; i < bi.nbox; i++) out[i] = bi.boxes[i];
    return bi.nbox;
  }
  if (bi.def && bi.def->kind == Kind::Torch) { out[0] = {{0.4375f, 0, 0.4375f}, {0.5625f, 0.625f, 0.5625f}}; return 1; }
  if (bi.flags & BF_Plant) { out[0] = {{0.15f, 0, 0.15f}, {0.85f, 0.8f, 0.85f}}; return 1; }
  out[0] = {{0, 0, 0}, {1, 1, 1}};
  return 1;
}

RayHit raycast(const World& world, const Eigen::Vector3d& o, const Eigen::Vector3d& d, double reach) {
  RayHit best;
  best.dist = reach + 1;
  int x = ifloor(o.x()), y = ifloor(o.y()), z = ifloor(o.z());
  const int sx = d.x() > 0 ? 1 : -1, sy = d.y() > 0 ? 1 : -1, sz = d.z() > 0 ? 1 : -1;
  const double inv[3] = {d.x() != 0 ? 1.0 / d.x() : 1e30, d.y() != 0 ? 1.0 / d.y() : 1e30, d.z() != 0 ? 1.0 / d.z() : 1e30};
  const double dd[3] = {d.x(), d.y(), d.z()};
  double tmax[3] = {((sx > 0 ? x + 1 : x) - o.x()) * inv[0], ((sy > 0 ? y + 1 : y) - o.y()) * inv[1], ((sz > 0 ? z + 1 : z) - o.z()) * inv[2]};
  double tdelta[3] = {std::abs(inv[0]), std::abs(inv[1]), std::abs(inv[2])};
  for (int a = 0; a < 3; a++)
    if (dd[a] == 0) tmax[a] = tdelta[a] = 1e30;  // never step along an axis the ray does not move on

  for (int step = 0; step < 64; step++) {
    BlockId id = world.get_block(x, y, z);
    if (id) {
      Box boxes[2];
      int n = selection_boxes(Blocks::get().info(id), boxes);
      for (int k = 0; k < n; k++) {
        // Ray vs AABB (slab method) in world space.
        double bmin[3] = {x + boxes[k].min[0], y + boxes[k].min[1], z + boxes[k].min[2]};
        double bmax[3] = {x + boxes[k].max[0], y + boxes[k].max[1], z + boxes[k].max[2]};
        double t0 = 0, t1 = reach;
        int face = -1;
        bool ok = true;
        for (int a = 0; a < 3 && ok; a++) {
          double oa = a == 0 ? o.x() : (a == 1 ? o.y() : o.z());
          double da = a == 0 ? d.x() : (a == 1 ? d.y() : d.z());
          if (std::abs(da) < 1e-12) { if (oa < bmin[a] || oa > bmax[a]) ok = false; continue; }
          double ta = (bmin[a] - oa) / da, tb = (bmax[a] - oa) / da;
          int fa = da > 0 ? a * 2 : a * 2 + 1;  // entering through the min side when moving +
          // face index mapping: axis0 -> west(4)/east(5), axis1 -> down(0)/up(1), axis2 -> north(2)/south(3)
          static const int map[3][2] = {{4, 5}, {0, 1}, {2, 3}};
          fa = map[a][da > 0 ? 0 : 1];
          if (ta > tb) std::swap(ta, tb);
          if (ta > t0) { t0 = ta; face = fa; }
          if (tb < t1) t1 = tb;
          if (t0 > t1) ok = false;
        }
        if (!ok || t0 >= best.dist) continue;
        best.hit = true;
        best.x = x; best.y = y; best.z = z;
        best.dist = t0;
        best.face = face < 0 ? 1 : face;
        best.point = o + d * t0;
        for (int a = 0; a < 3; a++) { best.box_min[a] = bmin[a]; best.box_max[a] = bmax[a]; }
      }
      if (best.hit) return best;
    }
    // Advance to the next voxel.
    int a = tmax[0] < tmax[1] ? (tmax[0] < tmax[2] ? 0 : 2) : (tmax[1] < tmax[2] ? 1 : 2);
    if (tmax[a] > reach) break;
    if (a == 0) { x += sx; tmax[0] += tdelta[0]; }
    else if (a == 1) { y += sy; tmax[1] += tdelta[1]; }
    else { z += sz; tmax[2] += tdelta[2]; }
  }
  return best;
}

}  // namespace ds
