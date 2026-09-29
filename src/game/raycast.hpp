#pragma once
#include <Eigen/Dense>

#include "world/world.hpp"

namespace ds {

struct RayHit {
  bool hit = false;
  int x = 0, y = 0, z = 0;   // block
  int face = 0;              // face index of the entered side (0 down, 1 up, 2 north, 3 south, 4 west, 5 east)
  double dist = 0;
  Eigen::Vector3d point;     // world position of the hit
  double box_min[3], box_max[3];  // selection box in world space
};

// Selection boxes of a block (block-local). Falls back to plant/torch/cube shapes.
int selection_boxes(const BlockInfo& bi, Box out[2]);

RayHit raycast(const World& world, const Eigen::Vector3d& origin, const Eigen::Vector3d& dir, double reach);

}  // namespace ds
