#include "game/player.hpp"

namespace ds {

int Player::block_boxes(const World& w, int x, int y, int z, AABB out[2]) {
  BlockId id = w.get_block(x, y, z);
  if (id == 0) return 0;
  const BlockInfo& bi = Blocks::get().info(id);
  if (!bi.solid()) return 0;
  for (int i = 0; i < bi.nbox; i++)
    out[i] = {{x + bi.boxes[i].min[0], y + bi.boxes[i].min[1], z + bi.boxes[i].min[2]},
              {x + bi.boxes[i].max[0], y + bi.boxes[i].max[1], z + bi.boxes[i].max[2]}};
  return bi.nbox;
}

double Player::move_axis(const World& w, int axis, double delta) {
  if (delta == 0) return 0;
  AABB b = box();
  // Region swept by the move.
  int lo[3], hi[3];
  for (int i = 0; i < 3; i++) {
    double a = b.mn[i], c = b.mx[i];
    if (i == axis) { if (delta > 0) c += delta; else a += delta; }
    lo[i] = static_cast<int>(std::floor(a)) - 0;
    hi[i] = static_cast<int>(std::floor(c));
  }
  double d = delta;
  for (int x = lo[0]; x <= hi[0]; x++)
    for (int y = lo[1]; y <= hi[1]; y++)
      for (int z = lo[2]; z <= hi[2]; z++) {
        AABB boxes[2];
        int n = block_boxes(w, x, y, z, boxes);
        for (int k = 0; k < n; k++) {
          const AABB& o = boxes[k];
          bool overlap = true;
          for (int i = 0; i < 3; i++)
            if (i != axis && (b.mx[i] <= o.mn[i] + 1e-9 || b.mn[i] >= o.mx[i] - 1e-9)) overlap = false;
          if (!overlap) continue;
          if (d > 0 && o.mn[axis] >= b.mx[axis] - 1e-9) d = std::min(d, o.mn[axis] - b.mx[axis]);
          else if (d < 0 && o.mx[axis] <= b.mn[axis] + 1e-9) d = std::max(d, o.mx[axis] - b.mn[axis]);
        }
      }
  pos[axis] += d;
  return d;
}

namespace {
double approach(double v, double target, double max_delta) {
  double d = target - v;
  if (d > max_delta) d = max_delta;
  if (d < -max_delta) d = -max_delta;
  return v + d;
}
}  // namespace

void Player::update(double dt, const MoveInput& in, const World& world) {
  // Wait for the terrain under us to exist.
  if (!world.column_loaded({floor_div(ifloor(pos.x()), 16), floor_div(ifloor(pos.z()), 16)})) return;

  sneaking = in.sneak && !flying;
  auto fluid_at = [&](double y) -> int {
    BlockId id = world.get_block(ifloor(pos.x()), ifloor(y), ifloor(pos.z()));
    const BlockInfo& bi = Blocks::get().info(id);
    if (!bi.liquid()) return 0;
    return bi.name.ends_with("lava") ? 2 : 1;
  };
  int f_feet = fluid_at(pos.y() + 0.1), f_body = fluid_at(pos.y() + 0.9);
  in_water = f_feet == 1 || f_body == 1;
  in_lava = f_feet == 2 || f_body == 2;
  eyes_in_water = fluid_at(eye().y()) == 1;
  const bool in_fluid = in_water || in_lava;

  // Horizontal wish direction.
  const double sy = std::sin(yaw), cy = std::cos(yaw);
  Eigen::Vector2d fwd(-sy, cy), right(-cy, -sy);
  Eigen::Vector2d wish = fwd * in.forward + right * in.strafe;
  double wl = wish.norm();
  if (wl > 1) wish /= wl;

  sprinting = in.sprint && in.forward > 0 && !sneaking;
  double speed = 4.317;
  if (sneaking) speed = 1.295;
  else if (sprinting) speed = 5.612;
  if (flying) speed = sprinting ? 21.8 : 10.9;
  if (in_fluid && !flying) speed *= in_lava ? 0.3 : 0.6;

  if (flying) {
    vel.x() = approach(vel.x(), wish.x() * speed, 80 * dt);
    vel.z() = approach(vel.z(), wish.y() * speed, 80 * dt);
    double vy = (in.jump ? 1.0 : 0.0) - (in.sneak ? 1.0 : 0.0);
    vel.y() = approach(vel.y(), vy * (sprinting ? 11.0 : 7.5), 60 * dt);
  } else {
    double accel = on_ground ? 55 : (in_fluid ? 20 : 14);
    vel.x() = approach(vel.x(), wish.x() * speed, accel * dt);
    vel.z() = approach(vel.z(), wish.y() * speed, accel * dt);
    if (in_fluid) {
      vel.y() -= (in_lava ? 4.0 : 8.0) * dt;
      vel.y() *= std::pow(in_lava ? 0.5 : 0.8, dt * 20);
      if (in.jump) vel.y() = approach(vel.y(), in_lava ? 2.5 : 4.0, 30 * dt);
    } else {
      vel.y() -= 32.0 * dt;
      vel.y() *= std::pow(0.98, dt * 20);
      if (vel.y() < -78) vel.y() = -78;
      if (in.jump && on_ground) {
        vel.y() = 8.4;
        if (sprinting) { vel.x() += -sy * 2.0; vel.z() += cy * 2.0; }
      }
    }
  }

  // Sneaking keeps the player on ledges.
  const Eigen::Vector3d start = pos;
  double dx = vel.x() * dt, dy = vel.y() * dt, dz = vel.z() * dt;
  auto supported = [&](double px, double pz) {
    AABB b = box();
    b.mn[0] += px - pos.x(); b.mx[0] += px - pos.x(); b.mn[2] += pz - pos.z(); b.mx[2] += pz - pos.z();
    b.mn[1] -= 0.6; b.mx[1] = pos.y() - 1e-4;
    for (int x = ifloor(b.mn[0]); x <= ifloor(b.mx[0]); x++)
      for (int y = ifloor(b.mn[1]); y <= ifloor(b.mx[1]); y++)
        for (int z = ifloor(b.mn[2]); z <= ifloor(b.mx[2]); z++) {
          AABB boxes[2];
          int n = block_boxes(world, x, y, z, boxes);
          for (int k = 0; k < n; k++)
            if (boxes[k].overlaps(b)) return true;
        }
    return false;
  };
  if (sneaking && on_ground) {
    while (dx != 0 && !supported(pos.x() + dx, pos.z())) dx = std::abs(dx) < 0.05 ? 0 : dx - std::copysign(0.05, dx);
    while (dz != 0 && !supported(pos.x(), pos.z() + dz)) dz = std::abs(dz) < 0.05 ? 0 : dz - std::copysign(0.05, dz);
  }

  const bool was_on_ground = on_ground;
  double my = move_axis(world, 1, dy);
  double mx = move_axis(world, 0, dx);
  double mz = move_axis(world, 2, dz);
  bool hit_h = std::abs(mx - dx) > 1e-9 || std::abs(mz - dz) > 1e-9;

  // Step up small ledges (slabs, stair steps, 0.6 blocks).
  if (hit_h && (was_on_ground || my != dy) && !flying && !in_fluid && vel.y() <= 0.01) {
    const Eigen::Vector3d after = pos;
    pos = start;
    double up = move_axis(world, 1, 0.6);
    double sx = move_axis(world, 0, dx);
    double sz = move_axis(world, 2, dz);
    double down = move_axis(world, 1, -up - 0.001);
    (void)down;
    double gain = std::abs(sx) + std::abs(sz), base = std::abs(mx) + std::abs(mz);
    if (gain <= base + 1e-6) pos = after;
    else { mx = sx; mz = sz; my = dy; }
  }

  on_ground = dy < 0 && std::abs(my - dy) > 1e-9;
  if (std::abs(my - dy) > 1e-9) vel.y() = 0;
  if (std::abs(mx - dx) > 1e-9) vel.x() = 0;
  if (std::abs(mz - dz) > 1e-9) vel.z() = 0;
  if (flying && on_ground) flying = false;
  // Ground check even if standing still.
  if (!on_ground && dy >= -1e-9 && dy <= 1e-9) {
    Eigen::Vector3d p = pos;
    double t = move_axis(world, 1, -0.01);
    pos = p;
    on_ground = t > -0.0099;
  }
}

}  // namespace ds
