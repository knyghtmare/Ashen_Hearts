-- This AI is written specifically for scenario 'Aragan the Iron' of campaign
-- Ashen Hearts. As such, some characteristics are hard-coded and might not
-- work right out of the box in another scenario. However, most parts are
-- reasonably general, so it should not be too hard to adapt the AI. The most
-- difficult part is likely the fact that northward movement is assumed.
-- I have tried to mark all that code by 'xxx' markers in comments.

local AH = wesnoth.require "ai/lua/ai_helper.lua"


-- xxx Hard-coded settings for now; can be turned into parameters if needed
local advance_per_turn = 2

local wall_width = 4  -- the width of the shieldwall and minimum unit needed in row 1

local min_units_row2 = 1  -- minimum units needed in row 2
local goal_hex = { 22, 9 }
local type_row1 = 'Dwarvish Guardsman,Dwarvish Stalwart,Dwarvish Sentinel'
local type_row2 = 'Dwarvish Thunderer,Dwarvish Thunderguard,Dwarvish Dragonguard'

-- Other parameters which are different for the two shieldwalls (passed in @cfg):
-- goal_x: x value of vertical line along which (roughly) to advance
-- start_min_x: starting x coordinate of the leftern most unit of the wall
-- y_max: maximum y coordinate at which to consider builindg the wall


local function get_unit_hex_combos(dst_src)
    -- This is a function which recursively finds all combinations of distributing
    -- units on hexes. The number of units and hexes does not have to be the same.
    -- @dst_src lists all units which can reach each hex in format:
    --  [1] = {
    --      [1] = { src = 17028 },
    --      [2] = { src = 16027 },
    --      [3] = { src = 15027 },
    --      dst = 18025
    --  },
    --  [2] = {
    --      [1] = { src = 17028 },
    --      [2] = { src = 16027 },
    --      dst = 20026
    --  },

    local all_combos, combo = {}, {}
    local num_hexes = #dst_src
    local hex = 0

    -- This is the recursive function adding units to each hex
    -- It is defined here so that we can use the variables above by closure
    local function add_combos()
        hex = hex + 1

        for _,ds in ipairs(dst_src[hex]) do
            if (not combo[ds.src]) then  -- If that unit has not been used yet, add it
                combo[ds.src] = dst_src[hex].dst

                if (hex < num_hexes) then
                    add_combos()
                else
                    local new_combo = {}
                    for k,v in pairs(combo) do new_combo[k] = v end
                    table.insert(all_combos, new_combo)
                end

                -- Remove this element from the table again
                combo[ds.src] = nil
            end
        end

        -- We need to call this once more, to account for the "no unit on this hex" case
        -- Yes, this is a code duplication (done so for simplicity and speed reasons)
        if (hex < num_hexes) then
            add_combos()
        else
            local new_combo = {}
            for k,v in pairs(combo) do new_combo[k] = v end
            table.insert(all_combos, new_combo)
        end

        hex = hex - 1
    end

    add_combos()

    -- The last combo is always the empty combo -> remove it
    all_combos[#all_combos] = nil

    return all_combos
end

local function make_dst_src(units, hexes)
    -- This functions determines which @units can reach which @hexes. It returns
    -- and array of the form usable by get_unit_hex_combos(dst_src) [see above]
    --
    -- We could be using location sets here also, but I prefer the 1000-based
    -- indices because they are easily human-readable. I don't think that the
    -- performance hit is noticeable.

    local dst_src_map = {}
    for _,unit in ipairs(units) do
        -- If the AI turns out to be slow, this could be pulled out to a higher
        -- level, to avoid calling it for each combination of hexes:
        local reach = wesnoth.paths.find_reach(unit)

        for _,hex in ipairs(hexes) do
            for _,r in ipairs(reach) do
                if (r[1] == hex[1]) and (r[2] == hex[2]) then
                    --print(unit.id .. ' can reach ' .. r[1] .. ',' .. r[2])

                    dst = hex[1] * 1000 + hex[2]

                    if (not dst_src_map[dst]) then
                        dst_src_map[dst] = {
                            dst = dst,
                            { src = unit.x * 1000 + unit.y }
                        }
                    else
                        table.insert(dst_src_map[dst], { src = unit.x * 1000 + unit.y })
                    end

                    break
                end
            end
        end
    end

    -- Because of the way how the recursive function above works, we want this
    -- to be an array, not a map with dsts as keys
    local dst_src = {}
    for _,dst in pairs(dst_src_map) do
        table.insert(dst_src, dst)
    end

    return dst_src
end

local function get_best_combo(combos, min_units, cfg)
    -- Rate a combination of units on goal hexes (for one row only)
    -- @min_units: minimum number of units needed to count as valid combo

    local hp_map = {}  -- Setting up hitpoint map for speed reasons
    local max_rating, best_combo = -9e99
    for _,combo in ipairs(combos) do
        local n_hexes = 0
        for dst,src in pairs(combo) do
            n_hexes = n_hexes + 1
        end

        if (n_hexes >= min_units) then
            local rating = 0

            -- Find the hexes at the ends of the line; these get an additional
            -- bonus for units with high HP
            local end_hexes = {}
            local max_dst, min_dst = -1, 9e99
            for src,dst in pairs(combo) do
                -- Since dst is 1000*x+y, and we want to sort by x, we can simply
                -- compare the dst values directly. It will even work for vertical
                -- lines. Only requirement is that the line is straight then.
                if (dst > max_dst) then max_dst = dst end
                if (dst < min_dst) then min_dst = dst end
            end

            for src,dst in pairs(combo) do
                local dst_x, dst_y = math.floor(dst / 1000), dst % 1000

                -- Need to ensure a positive rating for each unit, so that combo
                -- with most units is chosen, even if min_units < #hexes
                rating = rating + 1000

                -- Rating is distance from goal hex
                -- and distance from x=goal_x line
                rating = rating - wesnoth.map.distance_between(dst_x, dst_y, goal_hex[1], goal_hex[2])
                rating = rating - math.abs(dst_x - cfg.goal_x)

                -- Also use HP rating; use strongest available units
                if (not hp_map[src]) then
                    local src_x, src_y = math.floor(src / 1000), src % 1000
                    local unit = wesnoth.units.get(src_x, src_y)
                    hp_map[src] = unit.hitpoints
                end

                rating = rating + hp_map[src] / 100.

                -- Additional hp bonus for the edge hexes
                if (dst == min_dst) or (dst == max_dst) then
                    rating = rating + hp_map[src] / 100.
                end
            end
            --print('Combo #' .. _ .. ': ', rating)

            if (rating > max_rating) then
                max_rating = rating
                best_combo = combo
            end
        end
    end

    if best_combo then
        return best_combo, max_rating
    end
end

local function get_best_formation(units_row1, units_row2, y0, cfg)
    -- Find all locations on which a full formation (both ros) can be positioned
    -- and rate the against each other

    local width, height = wesnoth.current.map.playable_width, wesnoth.current.map.playable_height
    local test_unit_row1 = units_row1[1]
    local test_unit_row2 = units_row2[1]
    
    

    -- This is used to figure out in which direction the shieldwall is moving,
    -- as this determines its orientation
    local previous_min_x = wml.variables["AI_shieldwall_S" .. wesnoth.current.side .. "_min_x"] or cfg.start_min_x
    --print('previous_min_x', previous_min_x)

    local max_rating, best_combo = -9e99
    for x0 = 1,width-wall_width+1 do -- xxx hard-coded behavior (scanning through x only)
        local dy = 0  -- horizontal formation
        if (x0 < previous_min_x) then
            dy = -1  -- formation sloping "down" on left
        elseif (x0 > previous_min_x) then
            dy = 1   -- formation sloping "down" on right
        end
        --print(x0, y0, dy)

        -- It's the center of the shieldwall which should determine the northward
        -- extent (approximately, at least), but we're iterating from the left
        local y0_left = y0 - math.floor((wall_width - 1) / 2.) * dy
        --print('  y0, y0_left', y0, y0_left)

        local terrain_possible = true
        local hexes_row1, hexes_row2 = {}, {}
        for dx = 0, wall_width-1 do
            local x1 = x0 + dx
            local y1 = y0_left + math.ceil(0.5 * (dx * dy - x0 % 2))

            -- All hexes need to be passable to the units (assumed to have the same movetype)
            local movecost = wesnoth.units.movement_on(test_unit_row1, wesnoth.current.map[{x1,y1}])

            if (movecost > test_unit_row1.max_moves) then
                terrain_possible = false
                break
            end

            -- Also check that no units are blocking the hex
            local unit_in_way = wesnoth.units.get(x1, y1)
            if unit_in_way then
                if (unit_in_way.side ~= wesnoth.current.side) or (unit_in_way.moves == 0) then
                    terrain_possible = false
                    break
                end
            end

            table.insert(hexes_row1, { x1, y1 })
        end
        --print('  terrain_possible for units_row1', terrain_possible)

        -- Now check the same for the row 2 units just south of that
        if terrain_possible then
            for i = 1, wall_width do
                local x1 = hexes_row1[i][1]
                local y1 = hexes_row1[i][2] + 1 -- one south of row1 (xxx hard-coded behavior)

                local movecost = wesnoth.units.movement_on(test_unit_row2, wesnoth.current.map[{x1,y1}])

                if (movecost > test_unit_row2.max_moves) then
                    terrain_possible = false
                    break
                end

                local unit_in_way = wesnoth.units.get(x1, y1)
                if unit_in_way then
                    if (unit_in_way.side ~= wesnoth.current.side) or (unit_in_way.moves == 0) then
                        terrain_possible = false
                        break
                    end
                end

                table.insert(hexes_row2, { x1, y1 })
            end
            --print('  terrain_possible for units_row2', terrain_possible)
        end

        -- Only consider these hexes if all of them are accessible to the shieldwall units
        if terrain_possible then
            local dst_src_row1 = make_dst_src(units_row1, hexes_row1)

            if (#dst_src_row1 > 0) then
                local rating, combo

                local combos_row1 = get_unit_hex_combos(dst_src_row1)
                local combo_row1, rating_row1 = get_best_combo(combos_row1, wall_width, cfg)

                -- If possible combo was found for row1 units, do the same for row 2 units
                if combo_row1 then
                    --print('  found combo for units_row1')
                    local dst_src_row2 = make_dst_src(units_row2, hexes_row2)

                    if (#dst_src_row2 > 0) then
                        local combos_row2 = get_unit_hex_combos(dst_src_row2)
                        local combo_row2, rating_row2 = get_best_combo(combos_row2, min_units_row2, cfg)

                        if combo_row2 then
                            rating = rating_row1 + rating_row2
                            --print('      rating_row1, rating_row2, rating', rating_row1, rating_row2, rating)
                            combo = { combo_row1, combo_row2 }
                        end
                    end
                end

                if rating and (rating > max_rating) then
                    max_rating = rating
                    best_combo = combo
                end
            end
        end
    end

    return best_combo -- this is nil if none was found
end


local ca_shieldwall = {}

-- old --  (ai, cfg, self) --  new --  (cfg, data)

function ca_shieldwall:evaluation(cfg,data)

    units_row1 = wesnoth.units.find_on_map {
        side = wesnoth.current.side,
        type=type_row1,
        formula = '$this_unit.moves > 0'
    }
    if (not units_row1[1]) then return 0 end

    units_row2 = wesnoth.units.find_on_map {
        side = wesnoth.current.side,
        type=type_row2,
        formula = '$this_unit.moves > 0'
    }
    if (not units_row2[1]) then return 0 end

    -- First, determine how far north to form the line, an
    -- its southern-most extent (xxx hard-coded behavior)
    local y_min = cfg.y_max - wesnoth.current.turn * advance_per_turn

    -- Wrapper loop that lets the AI fall back if the forward-most hexes
    -- do not allow for a full shieldwall formation
    for y0 = y_min,cfg.y_max do
        local best_combo = get_best_formation(units_row1, units_row2, y0, cfg)

        if best_combo then
            -- Need to reorganize the combo a bit, as units might be moved out
            -- of the way by the AI itself -> identify them by id, rather than src
            local moves = {}
            for src,dst in pairs(best_combo[1]) do
                local dst_x, dst_y = math.floor(dst / 1000), dst % 1000
                local src_x, src_y = math.floor(src / 1000), src % 1000

                local unit = wesnoth.units.get(src_x, src_y)
                table.insert(moves, { id = unit.id, loc = { dst_x, dst_y } })
            end
            for src,dst in pairs(best_combo[2]) do
                local dst_x, dst_y = math.floor(dst / 1000), dst % 1000
                local src_x, src_y = math.floor(src / 1000), src % 1000

                local unit = wesnoth.units.get(src_x, src_y)
                table.insert(moves, { id = unit.id, loc = { dst_x, dst_y } })
            end
            data.SW_moves = moves
           
            return 110000
        end
    end



    return 0
end

-- old -- (ai, _, self)   --    new -- (cfg,data)

function ca_shieldwall:execution(cfg,data)
    -- Move units out of the way preferentially toward north (xxx hard-coded behavior)
    local cfg_oow = { dx = 0, dy = -1 }

    local min_x, min_y = 9e99, 9e99
    for _,move in ipairs(data.SW_moves) do
        if (move.loc[1] < min_x) then min_x = move.loc[1] end
        if (move.loc[2] < min_y) then min_y = move.loc[2] end

        local unit = wesnoth.units.find_on_map { id = move.id }[1]
        AH.movefull_outofway_stopunit(ai, unit, move.loc[1], move.loc[2], cfg_oow)
    end

    -- These are needed both by the AI, and by the accompanying simple_attack MAI
    -- If current side = 3, below will be AI_shieldwall_S3_min_x = min_x
    wml.variables['AI_shieldwall_S' .. wesnoth.current.side .. '_min_x'] = min_x
    wml.variables['AI_shieldwall_S' .. wesnoth.current.side .. '_min_y'] = min_y

    data.SW_moves = nil
end

return ca_shieldwall
