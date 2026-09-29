#include "world/chunk.hpp"

namespace ds::Biome {

Climate climate(u8 b) {
  switch (b) {
    case Ocean: case DeepOcean: return {0.5f, 0.5f};
    case Plains: return {0.8f, 0.4f};
    case Desert: return {2.0f, 0.0f};
    case Hills: return {0.2f, 0.3f};
    case Forest: return {0.7f, 0.8f};
    case Taiga: return {0.25f, 0.8f};
    case Swamp: return {0.8f, 0.9f};
    case FrozenOcean: case SnowyPlains: return {0.0f, 0.5f};
    case Beach: return {0.8f, 0.4f};
    case BirchForest: return {0.6f, 0.6f};
    case ColdTaiga: return {-0.5f, 0.4f};
    case Savanna: return {1.2f, 0.0f};
    case Jungle: return {0.95f, 0.9f};
    case DarkForest: return {0.7f, 0.8f};
    default: return {0.8f, 0.4f};
  }
}

}  // namespace ds::Biome
