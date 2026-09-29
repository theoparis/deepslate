#pragma once
#include <Eigen/Dense>

#include "world/world.hpp"

namespace ds {

struct AABB {
  double mn[3], mx[3];
  bool overlaps(const AABB& o) const {
    for (int i = 0; i < 3; i++)
      if (mx[i] <= o.mn[i] || mn[i] >= o.mx[i]) return false;
    return true;
  }
};

struct MoveInput {
  float forward = 0, strafe = 0;  // -1..1
  bool jump = false, sneak = false, sprint = false;
};

class Player {
 public:
  static constexpr double WIDTH = 0.6, HEIGHT = 1.8, SNEAK_HEIGHT = 1.5;

  Eigen::Vector3d pos{0, 100, 0};  // feet
  Eigen::Vector3d vel{0, 0, 0};
  float yaw = 0, pitch = 0;        // radians (Minecraft convention)
  bool on_ground = false, flying = false, sprinting = false, sneaking = false;
  bool in_water = false, eyes_in_water = false, in_lava = false;
  bool creative = true;

  double eye_height() const { return sneaking ? 1.27 : 1.62; }
  Eigen::Vector3d eye() const { return pos + Eigen::Vector3d(0, eye_height(), 0); }
  AABB box() const {
    double h = sneaking ? SNEAK_HEIGHT : HEIGHT, r = WIDTH / 2;
    return {{pos.x() - r, pos.y(), pos.z() - r}, {pos.x() + r, pos.y() + h, pos.z() + r}};
  }

  void update(double dt, const MoveInput& in, const World& world);

  // Collision boxes of the block at (x,y,z) in world space.
  static int block_boxes(const World& w, int x, int y, int z, AABB out[2]);

 private:
  // Moves along one axis, stopping at obstacles. Returns the distance actually travelled.
  double move_axis(const World& w, int axis, double delta);
};

}  // namespace ds
