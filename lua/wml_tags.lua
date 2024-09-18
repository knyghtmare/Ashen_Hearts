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

-- to make code shorter
local wml_actions = wesnoth.wml_actions

-- support for translatable strings, custom textdomain
local _ = wesnoth.textdomain "wesnoth-ah"

-- [loot]: replacement for mainline LOOT macro
-- supported parameters:
-- StandardSideFilter
-- amount, raises error if not number
function wml_actions.loot( cfg )
	local gold_amount = tonumber( cfg.amount ) or wml.error( "Missing or wrong amount= value in [loot]" )
	local sides = wesnoth.sides.find( cfg )
	for index, side in ipairs( sides ) do
		wml_actions.message {
			side_for = side.side,
			speaker = "narrator",
			message = string.format( tostring( _"You retrieve %d pieces of gold." ), gold_amount ),
			image = "wesnoth-icon.png",
			sound = "gold.ogg"
		}
		side.gold = side.gold + gold_amount
	end
end

-- the three tags below are WML/Lua remakes of Javascript's standard dialogs alert(), confirm() and prompt()
function wml_actions.alert( cfg )
	if cfg.title then
		gui.alert(cfg.title, cfg.message)
	else
		gui.alert(cfg.message)
	end
end

function wml_actions.confirm( cfg )
	local variable = cfg.variable or wml.error( "Missing variable= key in [confirm]" )

	local function sync()
		if cfg.title then
			return { return_value = gui.confirm(cfg.title, cfg.message) }
		else
			return { return_value = gui.confirm(cfg.message) }
		end
	end

	local return_table = wesnoth.sync.evaluate_single(sync)
	wml.variables[variable] = return_table.return_value
end

function wml_actions.prompt( cfg )
	local variable = cfg.variable or wml.error( "Missing variable= key in [prompt]" )

	local buttonbox = T.grid {
				T.row {
					T.column {
						T.button {
							label = "OK",
							return_value = 1
						}
					},
					T.column {
						T.spacer {
							width = 10
						}
					},
					T.column {
						T.button {
							label = "Close",
							return_value = 2
						}
					}
				}
			}

	local prompt_dialog = {
		T.helptip { id="tooltip_large" }, -- mandatory field
		T.tooltip { id="tooltip_large" }, -- mandatory field
		maximum_height = 600,
		maximum_width = 800,
		T.grid { -- Title, will be the object name
			T.row {
				T.column {
					horizontal_alignment = "left",
					grow_factor = 1,
					border = "all",
					border_size = 5,
					T.label {
						definition = "title",
						id = "title"
					}
				}
			},
			T.row {
				T.column {
					vertical_alignment = "center",
					horizontal_alignment = "center",
					border = "all",
					border_size = 5,
					T.scroll_label {
						id = "message"
					}
				}
			},
			T.row {
				T.column {
					vertical_alignment = "center",
					horizontal_alignment = "center",
					border = "all",
					border_size = 5,
					T.text_box {
						id = "text"
					}
				}
			},
			-- button box
			T.row {
				T.column {
					vertical_alignment = "center",
					horizontal_alignment = "center",
					border = "all",
					border_size = 5,
					buttonbox
				}
			}
		}
	}

	local function preshow(dialog)
		-- here set all widget starting values
		dialog.message.use_markup = true
		dialog.title.label = cfg.title or ""
		dialog.message.label = cfg.message or ""
		-- in 1.15.x, setting a translatable string as value of a text box
		-- widget raises an error; handle this case
		if cfg.text then
			dialog.text.text = tostring(cfg.text)
		end
	end

	local function sync()
		local input

		local function postshow(dialog)
			-- here get all widget values
			input = dialog.text.text
		end

		local return_value = gui.show_dialog( prompt_dialog, preshow, postshow )
		return { return_value = return_value, input = input }
	end

	local return_table = wesnoth.sync.evaluate_single(sync)
	local return_value = return_table.return_value

	if return_value == 1 or return_value == -1 then -- if used pressed OK or Enter
		wml.variables[variable] = return_table.input
	elseif return_value == 2 or return_value == -2 then -- if user pressed Cancel or Esc
		wml.variables[variable] = "null" -- any better choice?
	else wml.error( ( tostring( _"Prompt" ) .. ": " .. tostring( _"Error, return value :" ) .. tostring( return_value ) ) ) end -- any unhandled case is handled here
end