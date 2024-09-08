-- original code credits to fluffbeast
-- modified by Lord-Knightmare to accomodate lvl 1 and lvl 0 units

function wesnoth.wml_actions.adjust_recall_costs(cfg)
    -- currently revised recall costs
    -- | Unit Level | Recall Cost |
    -- | ---------- | ----------- |
    -- |     0      |     10      |
    -- |     1      |     15      |
    -- |     2      |     20      |
    -- |     3      |     30      |
    -- |     4      |     40      |
    -- |     5+     |     50      |
    -- | ---------- | ----------- |
    for _, unit in ipairs(wesnoth.units.find_on_recall {}) do
        if unit.level == 0 then
            unit.recall_cost = 10
        elseif unit.level == 1 then
            unit.recall_cost = 15
        elseif unit.level == 2 then
            unit.recall_cost = 20
        elseif unit.level == 3 then
            unit.recall_cost = 30
        elseif unit.level == 4 then
            unit.recall_cost = 40
        else 
            unit.recall_cost = 50
        end
    end
end

function wesnoth.wml_actions.give_experience(cfg)
    -- get the XP amount
    local amount = tonumber(cfg.amount) or wml.error("Missing or wrong amount= value in [give_experience]")

    -- get the receiving unit(s)
    for index, unit in ipairs(wesnoth.units.find_on_map(cfg)) do
        if unit.valid then
            wesnoth.interface.float_label( unit.x, unit.y, string.format("<span color='cyan'>+%s XP</span>", tostring(amount) ) )
            unit.experience = unit.experience + amount
        end
    end    
end