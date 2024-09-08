local AH = wesnoth.require "ai/lua/ai_helper.lua"
 
local cfg = {
    ca_score=110000,
    filter_location = { x = '37,30,27,20,30,27,35,16', y = '71,67,70,58,58,64,53,52' },
    enemy_side = 1
}
 
local ca_goto_AH = {}
 
function ca_goto_AH:evaluation(cfg,data)
    -- For convenience, we check for locations here, 
    -- and just pass that to the exec function
    -- This is mostly to make the unique_goals option easier
    local width, height = wesnoth.current.map.playable_width, wesnoth.current.map.playable_height
    local locs = wesnoth.get_locations {
        x = '1-' .. width,
        y = '1-' .. height,
        { "and", cfg.filter_location }
    }
    
    -- No single selected wind rune location
    if (not cfg.filter_location[0]) then return 0 end
 
    -- All non-leader units on the AI side that are not on a goal hex already
    local units = AH.get_units_with_moves {
        side = wesnoth.current.side,
        canrecruit= 'no',
        { "filter_location", {
            { "not", cfg.filter_location }
        } },
    }
    -- Not found even a single unit
    if (not units[0]) then return 0 end
 
    -- This should be impossible to activate since enemy is player. No player = No more game = No more AI
    local enemies = wesnoth.get_units { side = cfg.enemy_side }
    if (not enemies[0]) then return 0 end
 
    local max_rating, best_unit, best_hex, do_full_move = -9e99
    for _,unit in ipairs(units) do
        -- Distance to closest enemy
        local min_distance_enemy, closest_enemy = 9e99
        for _,enemy in ipairs(enemies) do
            local dist_enemy = wesnoth.map.distance_between(unit.x, unit.y, enemy.x, enemy.y)
            if (dist_enemy < min_distance_enemy) then
                min_distance_enemy = dist_enemy
                closest_enemy = enemy
            end
        end
 
        for _,loc in ipairs(locs) do
            -- We only consider this goal if it is "in between" the unit and the enemy
            local dist_goal_enemy = wesnoth.map.distance_between(closest_enemy.x, closest_enemy.y, loc[1], loc[2])
 
            if (dist_goal_enemy <= min_distance_enemy) then
                local path, cost = wesnoth.find_path(unit, loc[1], loc[2])
 
                -- Make all hexes within the unit's current MP equaivalent
                if (cost <= unit.moves) then cost = 0 end
 
                local rating = - cost
 
                -- Add a small penalty for hexes occupied by an allied unit
                local unit_in_way = wesnoth.get_unit(loc[1], loc[2])
                if unit_in_way and (unit_in_way ~= unit) then
                    rating = rating - 0.01
                end
 
                if (rating > max_rating) then
                    -- Now go through the hexes along that path, to find which one the unit can actually get to
                    closest_hex = path[1]
                    for i = 2,#path do
                        local sub_path, sub_cost = wesnoth.find_path(unit, path[i][1], path[i][2])
                        if sub_cost <= unit.moves then
                            local unit_in_way = wesnoth.get_unit(path[i][1], path[i][2])
                            if not unit_in_way then
                                closest_hex = path[i]
                            end
                        else
                            break
                        end
                    end
 
                    -- Only use this if the unit actually moves
                    if (closest_hex[1] ~= unit.x) or (closest_hex[2] ~= unit.y) then
                        -- Full move by default, except if we get to the final hex
                        local full_move = true
                        if (closest_hex[1] == loc[1]) and (closest_hex[2] == loc[2]) then
                            full_move = false
                        end
 
                        max_rating = rating
                        best_unit, best_hex, do_full_move = unit, closest_hex, full_move
                    end
                end
            end
        end
    end
 
    if (not best_unit) then return 0 end
 
    -- Now store units and locs in self.data, so that we don't need to duplicate this in the exec function
    data.GO_unit, data.GO_dst, data.GO_do_full_move = best_unit, best_hex, do_full_move
 
    return cfg.ca_score
end
 
function ca_goto_AH:execution(cfg,data)
    if data.do_full_move then
        --print('  best unit full move:', data.GO_unit.id, data.GO_unit.x, data.GO_unit.y, data.GO_dst[1], data.GO_dst[2])
        AH.checked_move_full(ai, data.GO_unit, data.GO_dst[1], data.GO_dst[2])
    else
        --print('  best unit partial move:', data.GO_unit.id, data.GO_unit.x, data.GO_unit.y, data.GO_dst[1], data.GO_dst[2])
        AH.checked_move(ai, data.GO_unit, data.GO_dst[1], data.GO_dst[2])
    end
 
    data.GO_unit, data.GO_dst, data.GO_do_full_move = nil, nil, nil
end
 
return ca_goto_AH

