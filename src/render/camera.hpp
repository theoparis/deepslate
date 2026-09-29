#pragma once
#include <Eigen/Dense>
#include <array>

#include "util/common.hpp"

namespace ds {

// Minecraft conventions: yaw 0 looks toward +Z (south), yaw 90 toward -X (west);
// positive pitch looks down.
struct Camera {
  Eigen::Vector3d pos{0, 80, 0};
  float yaw = 0, pitch = 0;   // radians
  float fovy = 1.2217f;       // 70 degrees
  float aspect = 16.0f / 9.0f;
  float znear = 0.05f, zfar = 600.0f;

  Eigen::Vector3f forward() const {
    return {-std::sin(yaw) * std::cos(pitch), -std::sin(pitch), std::cos(yaw) * std::cos(pitch)};
  }
  // View matrix without translation (the world is drawn camera-relative).
  Eigen::Matrix4f view_rot() const {
    Eigen::Vector3f f = forward();
    Eigen::Vector3f r = f.cross(Eigen::Vector3f::UnitY()).normalized();
    Eigen::Vector3f u = r.cross(f);
    Eigen::Matrix4f m = Eigen::Matrix4f::Identity();
    m.block<1, 3>(0, 0) = r.transpose();
    m.block<1, 3>(1, 0) = u.transpose();
    m.block<1, 3>(2, 0) = -f.transpose();
    return m;
  }
  Eigen::Matrix4f proj() const {
    float t = 1.0f / std::tan(fovy * 0.5f);
    Eigen::Matrix4f p = Eigen::Matrix4f::Zero();
    p(0, 0) = t / aspect;
    p(1, 1) = t;
    p(2, 2) = (zfar + znear) / (znear - zfar);
    p(2, 3) = 2 * zfar * znear / (znear - zfar);
    p(3, 2) = -1;
    return p;
  }
  Eigen::Matrix4f view_proj() const { return proj() * view_rot(); }

  struct Frustum {
    std::array<Eigen::Vector4f, 6> planes;
    // Box given in camera-relative coordinates.
    bool intersects(const Eigen::Vector3f& mn, const Eigen::Vector3f& mx) const {
      for (auto& p : planes) {
        Eigen::Vector3f v(p.x() > 0 ? mx.x() : mn.x(), p.y() > 0 ? mx.y() : mn.y(), p.z() > 0 ? mx.z() : mn.z());
        if (p.x() * v.x() + p.y() * v.y() + p.z() * v.z() + p.w() < 0) return false;
      }
      return true;
    }
  };
  Frustum frustum() const {
    Eigen::Matrix4f m = view_proj();
    Frustum f;
    Eigen::Vector4f r0 = m.row(0), r1 = m.row(1), r2 = m.row(2), r3 = m.row(3);
    f.planes = {r3 + r0, r3 - r0, r3 + r1, r3 - r1, r3 + r2, r3 - r2};
    for (auto& p : f.planes) p /= p.head<3>().norm();
    return f;
  }
};

}  // namespace ds
