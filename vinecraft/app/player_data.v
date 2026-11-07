module app

import vinecraft.blocks
import vinecraft.gameplay
import vinecraft.storage

pub fn initial_hotbar(reg &blocks.Registry, saved ?storage.PlayerData) ([9]blocks.BlockId, int) {
	defaults := ['grass_block', 'dirt', 'stone', 'cobblestone', 'oak_planks', 'oak_log', 'glass',
		'torch', 'sand']!
	mut hotbar := [9]blocks.BlockId{}
	for i, block in defaults { hotbar[i] = reg.find(block) }
	mut selected := 0
	if pd := saved {
		if pd.hotbar.len == 9 {
			for i, slot in pd.hotbar {
				if slot.block != '' {
					id := reg.find(slot.block)
					if id != 0 { hotbar[i] = id }
				}
			}
		}
		selected = if pd.selected < 0 {
			0
		} else if pd.selected > 8 {
			8
		} else {
			pd.selected
		}
	}
	return hotbar, selected
}

pub fn saved_player(player gameplay.Player, hotbar [9]blocks.BlockId, selected int, reg &blocks.Registry) storage.PlayerData {
	mut data := storage.PlayerData{
		pos:      [player.pos.x, player.pos.y, player.pos.z]!
		yaw:      player.yaw * 57.29578
		pitch:    player.pitch * 57.29578
		flying:   player.flying
		selected: selected
	}
	for id in hotbar {
		data.hotbar << storage.InventorySlot{
			block: if id != 0 { reg.info(id).name } else { '' }
			count: if id != 0 {
				1
			} else {
				0
			}
		}
	}
	return data
}
