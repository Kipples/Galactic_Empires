-- We assume that the variable args contains the food and gold value lists, this should be done by the wml [lua] tag
-- local args = ...

-- Make a "food table" matching terrain codes with food values
-- Using gmatch with '([^,]+)' means, split the string up into parts which don't contain commas, (this is a regular expression)
-- In the for loop, s will take the value of each part in sequence.
local food_table = {}

for s in string.gmatch(args.one_food, '([^,]+)') do
	food_table[s] = 1
end

for s in string.gmatch(args.two_food, '([^,]+)') do
	food_table[s] = 2
end

for s in string.gmatch(args.three_food, '([^,]+)') do
	food_table[s] = 3
end

-- Make a "gold table" matching terrain codes with gold values
local gold_table = {}

for s in string.gmatch(args.one_gold, '([^,]+)') do
	gold_table[s] = 1
end

for s in string.gmatch(args.two_gold, '([^,]+)') do
	gold_table[s] = 2
end

for s in string.gmatch(args.three_gold, '([^,]+)') do
	gold_table[s] = 3
end

-- Some color codes:
local colors = { blue = args.ge_blue ,
		 numbers = '#f5e6c1' ,
		 detail_dark = '#a69275' ,
		 red = '#fa8c50' }

----------
-- Terrain Description Food Gold Values
----------

-- Helper function to get food, gold values from table, and handle wildcard terrains
function food_and_gold(terrain_code)
	local food = food_table[terrain_code]				-- Look up food, gold values in tables
	local gold = gold_table[terrain_code]				-- Food and gold are either 1,2,3, or nil (not in table)

	-- This part handles the codes with *'s in them
	if not food or not gold then
		-- Replace the first sequence of letters that are not ^, with the string '*', to get the starred code.
		-- (Do the replacement at most once.) Then try looking that up instead.
		local starred_code = string.gsub(terrain_code, '([^\\^]+)', '*', 1)

		if not food then
			food = food_table[starred_code]
		end
		if not gold then
			gold = gold_table[starred_code]
		end
	end

	return food, gold
end

local old_terrain = wesnoth.theme_items.terrain				-- Store the default terrain report function
function wesnoth.theme_items.terrain()					-- Declare a custom terrain report function
	local r = old_terrain()						-- First run the original, store its result in 'r'

	if #r == 0 or not r[1][2].text then
		return r						-- If there's no terrain_info currently, then stop.
	end

	local x,y = wesnoth.get_mouseover_tile()			-- Get the currently moused over hex and its terrain_code
	local food,gold = food_and_gold(wesnoth.get_terrain(x,y))	-- Get the food and gold values for this terrain. food, gold are 1,2,3 or nil

	if food or gold then						-- If one of them is not nil (so there is a bonus here)
		if not food then food = 0 end				-- If food is nil, report 0 food
		if not gold then gold = 0 end				-- If gold is nil, report 0 gold

		r[1][2].text = r[1][2].text .. "   (" .. food .. "f, " .. gold .. "g) "
									-- To the text of the report, add " ( f food, g good ) "
	end

	return r
end

---------------
-- Unit Weapons
---------------

function plus_text(r, n, desc)
	table.insert(r, { "element", { text = "  " .. "<span color='" .. colors.numbers .. "'>+" ..  n .. "</span>" .. "  " .. "<span color='" .. colors.detail_dark .. "'> " .. desc .. " </span>" .. "\n"} } )	
end

local old_unit_weapons = wesnoth.theme_items.unit_weapons	-- Here we store the default "unit_weapons" function
function wesnoth.theme_items.unit_weapons()			-- Now we are defining the custom replacement.
	local u = wesnoth.get_displayed_unit()
	if not u then
		return {}					-- If there is no unit selected, this thing is blank.
	end

	-- Check if the unit is a transporter or an hq or a worker or scientist
	local is_transporter = false
	local is_worker = false
	local is_scientist = false
	local is_hq = false
	local food_cfg = {}					-- food_cfg holds the food config, for convenience, in case of hq

	local abilities = {}					-- Holds the abilities config if and when it is found
	local passengers_cfg = {}				-- Holds the config for the "passengers" attack if found
	local cfg = u.__cfg					-- Hold the current unit config

	for i = 1, #cfg do
		if cfg[i][1] == "abilities" then
			abilities = cfg[i][2]

			for j = 1, #abilities do
				if abilities[j][2].id == "transport" then
					is_transporter = true
					break
				end
				if abilities[j][2].id == "work" then
					is_worker = true
					break
				end
				if abilities[j][2].id == "science" then
					is_scientist = true
					break
				end
			end
		end

		if cfg[i][1] == "attack" then
			if cfg[i][2].name == "passengers" then
				is_transporter = true
				passengers_cfg = cfg[i][2]
			end
			if cfg[i][2].name == "food" then
				is_hq = true
				food_cfg = cfg[i][2]
			end
		end
	end

	if is_transporter then			    		-- If the selected unit is a transporter,
		local r = old_unit_weapons()			-- Get the old weapons description.

		-- If either passengers damage or number is nil, then something is screwy
		if not passengers_cfg.damage or not passengers_cfg.number then
			table.insert(r, { "element" , { text = "\n" .. "Warning: I didn't seem to find the 'passengers' attack, falling back to default display" } })
			return r
		end

		table.remove(r,1)				-- Remove the first line (it is always e.g. "x-5 passengers" )
		table.remove(r,1)				-- Remove the second line (it is always e.g. "none-none" )

		table.insert(r, 1, { "element" , { text = "\n" .. "Passengers: " .. passengers_cfg.damage .. " / " .. passengers_cfg.number .. "\n\n"} } )


		return r
	elseif is_hq then
		-- Table to hold the return value
		local r = {}

		table.insert(r, { "element", { text = "\n" .. "Producing: \n" } })
		table.insert(r, { "element", { text = "  " .. "<span color='" .. colors.blue .. "'>"  .. u.variables.population_preference .. "</span>" .. "\n" } } )

		table.insert(r, { "element", { text = "\n" .. "Food Stores: \n" } })
		table.insert(r, { "element", { text = "  " .. "<span color='" .. colors.numbers .. "'>"  .. food_cfg.damage .. " / " .. food_cfg.number .. "</span>" .. "\n"} } )

		local worker_food = 0
		local worker_gold = 0

		local workers = wesnoth.get_units( { ability = "work" ,
							side = u.side ,
							role = u.role ,
							{ "filter_wml" , { hitpoints = "$this_unit.max_hitpoints" } }
						} )

		local replicator_bonus = 0
		local has_replicator = u.variables.replicator

		local nanomine_bonus = 0
		local nanomine_factor = 0

		if u.variables.nanomine then
			if u.variables.nanomine == "basic" then
				nanomine_factor = 1
			elseif u.variables.nanomine == "advanced" then
				nanomine_factor = 2
			end
		end

		local has_food_processor = false
		local has_mineral_processor = false

		for index, worker in ipairs(workers) do
			local terrain_code = wesnoth.get_terrain(worker.x, worker.y)
			local food, gold = food_and_gold(terrain_code)

			if food then
				worker_food = worker_food + food
				if has_replicator then replicator_bonus = replicator_bonus + 1 end
			end

			if gold then
				worker_gold = worker_gold + gold
				if nanomine_factor > 0 then nanomine_bonus = nanomine_bonus + nanomine_factor end
			end
		end

		for j = 1, #abilities do
			if abilities[j][2].id == "foodprocessor" then
				has_food_processor = true
			end
			if abilities[j][2].id == "mineralprocessor" then
				has_mineral_processor = true
			end
		end

		local some_food = false
		table.insert(r, { "element", { text = "\n" .. "Food Production: \n" } })
		plus_text(r, 2, "HQ")
		
		if worker_food > 0 then
			plus_text(r, worker_food, "workers")
			some_food = true
		end
		if has_food_processor then
			plus_text(r, 1, "food processor")
			some_food = true
		end
		if replicator_bonus > 0 then
			plus_text(r, replicator_bonus, "replicator")
			some_food = true
		end


		table.insert(r, { "element", { text = "\n" .. "Gold Production: \n" } })
		plus_text(r, 2, "HQ")

		if worker_gold > 0 then
			plus_text(r, worker_gold, "workers")
		end
		if has_mineral_processor then
			plus_text(r, 1, "mineral processor")
		end
		if nanomine_bonus > 0 then
			plus_text(r, nanomine_bonus, "nanomine")
		end

		return r
	elseif ((is_worker or is_scientist) and cfg.hitpoints < cfg.max_hitpoints) then		-- Add a note when a worker or scientist is injured
		local r = old_unit_weapons()
		table.insert(r, { "element", { text = "\n" .. "<span color='" .. colors.red .. "'>Injured, can't work!</span>\n" } } )
		return r
	else
		return old_unit_weapons()
	end
end

-------------
-- Unit Moves
-------------

local old_unit_moves = wesnoth.theme_items.unit_moves
function wesnoth.theme_items.unit_moves()

	local u = wesnoth.get_displayed_unit()
	if not u then
		return {}					-- If there is no unit selected, this thing is blank.
	end

	-- Check if the unit is a planet

	if u.role == "planet" then
		return {}					-- Planets can't move
	end

	-- Check if the unit is an hq
	local is_hq = false

	local cfg = u.__cfg					-- Hold the current unit config

	for i = 1, #cfg do
		if cfg[i][1] == "attack" then
			if cfg[i][2].name == "food" then
				is_hq = true
			end
		end
	end

	if is_hq then
		return {}					-- HQ's can't move
	else
		return old_unit_moves()
	end
end
