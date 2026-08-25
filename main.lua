-- Encounter Radar: what the ground you are standing on can actually produce.
--
-- Gen 1 had one wild table per map, so "what lives here" was one answer.  Gen 2
-- has up to seven for the same tile: grass splits three ways on the clock
-- (JohtoGrassWildMons carries a morn/day/nite slot set per map), surf is its
-- own table, and each of the three rods reads its own row list out of the map's
-- FISHGROUP.  This reads the merged tables and pages through every one of them.
--
-- Odds are the slot share within an encounter -- the cumulative bucket tables
-- the roll compares a rand(0,255) against, summed per species.  The bottom line
-- carries the other half of the story: the per-step rate for grass and surf, the
-- group's bite chance for a rod.  Both are the raw /256 the engine rolls, not a
-- rounded percentage, because that is the number the cartridge actually uses.
return function(mod)
  mod.options:define({
    { key = "enabled", label = "ENABLED", type = "toggle", default = true },
    { key = "owned", label = "MARK OWNED", type = "toggle", default = true },
  })

  -- GrassMonProbTable / WaterMonProbTable: cumulative thresholds out of 256.
  -- Imported tables carry their own copy, so these are only the safety net for
  -- a record that arrived without one.
  local GRASS_BUCKETS = { 77, 154, 205, 230, 243, 253, 256 }
  local WATER_BUCKETS = { 154, 230, 256 }

  local RODS = {
    { key = "old", label = "OLD ROD" },
    { key = "good", label = "GOOD ROD" },
    { key = "super", label = "SUPER ROD" },
  }

  local function percent(weight)
    if not weight or weight <= 0 then return nil end
    local n = math.floor(weight * 100 / 256 + 0.5)
    if n < 1 then n = 1 end
    return n
  end

  local function speciesName(id)
    local ok, def = pcall(function() return mod.content.pokemon:get(id) end)
    if ok and type(def) == "table" and type(def.name) == "string"
        and def.name ~= "" then
      return def.name
    end
    return (tostring(id):gsub("^SPECIES_", ""))
  end

  -- One species can hold several slots; the radar wants one row per species
  -- with the shares added up and the levels collapsed into a range.
  local function newTally()
    return { byId = {}, order = {} }
  end

  local function tallyAdd(tally, species, level, weight)
    if not species then return end
    local row = tally.byId[species]
    if not row then
      row = { species = species, min = level, max = level, weight = 0 }
      tally.byId[species] = row
      tally.order[#tally.order + 1] = row
    end
    row.weight = row.weight + (weight or 0)
    if level then
      if not row.min or level < row.min then row.min = level end
      if not row.max or level > row.max then row.max = level end
    end
  end

  local function tallyRows(tally)
    if #tally.order == 0 then return nil end
    table.sort(tally.order, function(a, b)
      if a.weight ~= b.weight then return a.weight > b.weight end
      return tostring(a.species) < tostring(b.species)
    end)
    return tally.order
  end

  local function terrainRows(def, fallbackBuckets)
    if type(def) ~= "table" or type(def.slots) ~= "table" then return nil end
    local buckets = def.buckets
    if type(buckets) ~= "table" or #buckets ~= #def.slots then
      buckets = (#def.slots == #fallbackBuckets) and fallbackBuckets or nil
    end
    local tally, previous = newTally(), 0
    for i, slot in ipairs(def.slots) do
      local top = buckets and buckets[i]
      local weight = top and (top - previous) or 0
      if top then previous = top end
      if type(slot) == "table" then
        tallyAdd(tally, slot.species, slot.level, weight)
      end
    end
    return tallyRows(tally)
  end

  -- A rod's rows are walked until the rolled byte is <= the row's chance, so a
  -- row owns the gap between its own threshold and the one before it.  A row
  -- with no species names a TimeFishGroups index and resolves to a day or nite
  -- pair instead (engine/events/fish.asm `Fish`).
  local function rodRows(rows, field, tod)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local tally, previous = newTally(), -1
    for _, row in ipairs(rows) do
      local chance = tonumber(row.chance) or 0
      local weight = chance - previous
      if weight < 0 then weight = 0 end
      previous = chance
      local species, level = row.species, row.level
      if row.timeGroup then
        local pairs_ = field and field.timeFishGroups
          and field.timeFishGroups[row.timeGroup]
        local slot = pairs_ and ((tod == "NITE") and pairs_.nite or pairs_.day)
        species = slot and slot.species
        level = slot and slot.level
      end
      tallyAdd(tally, species, level, weight)
    end
    return tallyRows(tally)
  end

  local function buildPages(game, mapId, mapDef, tod)
    local pages = {}

    local function terrainPage(title, def, fallback, todTag)
      if type(def) ~= "table" then return end
      local rows = terrainRows(def, fallback)
      if not rows then return end
      local rate = tonumber(def.rate) or 0
      pages[#pages + 1] = {
        title = title,
        tod = todTag,
        -- rate 0 is a table the engine can never roll; say so rather than
        -- listing mons that cannot appear
        rows = (rate > 0) and rows or {},
        note = (rate > 0) and ("STEP " .. rate .. "/256") or "NEVER HERE",
      }
    end

    local ok, encounters = pcall(function()
      return mod.content.encounters:get(mapId)
    end)
    local encounter = ok and encounters or nil
    local grass = encounter and encounter.grass
    if type(grass) == "table" then
      local byTime = grass.byTime
      if type(byTime) == "table" and (byTime.morn or byTime.nite) then
        terrainPage("GRASS MORN", byTime.morn or grass, GRASS_BUCKETS, "MORNING")
        terrainPage("GRASS DAY", grass, GRASS_BUCKETS, "DAY")
        terrainPage("GRASS NITE", byTime.nite or grass, GRASS_BUCKETS, "NITE")
      else
        terrainPage("GRASS", grass, GRASS_BUCKETS)
      end
    end
    terrainPage("SURF", encounter and encounter.water, WATER_BUCKETS)

    local field = game.data and game.data.field
    local groups = field and field.fishGroups
    local group = groups and mapDef and mapDef.fishGroup
      and groups[mapDef.fishGroup]
    if type(group) == "table" and type(group.rods) == "table" then
      for _, rod in ipairs(RODS) do
        local rows = rodRows(group.rods[rod.key], field, tod)
        if rows then
          pages[#pages + 1] = {
            title = rod.label,
            rows = rows,
            note = "BITE " .. (tonumber(group.chance) or 0) .. "/256",
          }
        end
      end
    end

    if #pages == 0 then
      pages[1] = { title = "NO WILD DATA", rows = {}, note = "" }
    end
    return pages
  end

  -- The cached period the overworld already keeps; asking it to recompute can
  -- rebuild the tile atlases when the clock has just rolled over, which is not
  -- something a menu should trigger.
  local function timeOfDay(overworld)
    local tod = overworld and overworld.tod
    if type(tod) == "string" and tod ~= "" then return tod end
    if overworld and overworld.timeOfDay then
      local ok, value = pcall(overworld.timeOfDay, overworld)
      if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "DAY"
  end

  -- The landmark name the map-name sign uses, flattened out of its two-line
  -- form; a map with no landmark falls back to its own id.
  local function placeName(game, mapId, mapDef)
    local field = game.data and game.data.field
    local landmarks = field and field.townMap and field.townMap.landmarks
    local entry = landmarks and mapDef and mapDef.landmark
      and landmarks[mapDef.landmark]
    local name = entry and entry.name
    if type(name) == "string" and name ~= "" then
      return (name:gsub("[\n\f\v]", " "))
    end
    return (tostring(mapId):gsub("_", " "))
  end

  local function levelText(row)
    if not row.min then return nil end
    if row.max and row.max ~= row.min then
      return "LV " .. row.min .. "-" .. row.max
    end
    return "LV " .. row.min
  end

  local function itemsFor(game, page)
    local dex = (game.save and game.save.pokedex) or {}
    local owned = dex.owned or {}
    local mark = mod.options:get("owned") ~= false
    local items = {}
    for _, row in ipairs(page.rows) do
      local odds = percent(row.weight)
      items[#items + 1] = {
        label = speciesName(row.species),
        right = odds and (odds .. "/100") or nil,
        sub = levelText(row),
        ball = (mark and owned[row.species]) and true or nil,
      }
    end
    return items
  end

  -- Published so a companion mod -- or a test -- can read the same table the
  -- screen draws without going through the UI.  mapDef is an argument because
  -- the live map carries the def the engine's own fishing roll reads, which is
  -- not necessarily the registry's copy.
  mod.exports.report = function(mapId, tod, mapDef)
    local game = mod.game
    if not (game and mapId) then return nil end
    if mapDef == nil then
      local ok, def = pcall(function() return mod.content.maps:get(mapId) end)
      mapDef = ok and def or nil
    end
    return buildPages(game, mapId, mapDef, tod or "DAY")
  end

  local ROWS = 5

  local function open(game)
    local overworld = mod.world and mod.world:overworld()
    local map = overworld and overworld.map
    local mapId = map and map.id
    if not mapId then return end
    local mapDef = map.def
    local tod = timeOfDay(overworld)
    local pages = mod.exports.report(mapId, tod, mapDef)
    if not pages then return end
    local place = placeName(game, mapId, mapDef)

    -- open on the page the clock is on, so the first thing shown is the one
    -- that answers "what will I run into if I step into that grass now"
    local index = 1
    for i, page in ipairs(pages) do
      if page.tod == tod then
        index = i
        break
      end
    end

    local list
    local function applyPage()
      local page = pages[index]
      list.title = page.title .. ((page.tod == tod) and " NOW" or "")
      list.items = itemsFor(game, page)
      list.index = 1
      list.scroll = 0
    end

    list = mod.ui.ListMenu.new(game, "", {}, {
      kind = "radar",
      rows = ROWS,
      -- the START menu pops itself when a row is selected, so B has to put it
      -- back the way every vanilla submenu does
      onCancel = function() mod.ui.push(game, "StartMenu") end,
      onPocketSwitch = (#pages > 1) and function(_, delta)
        index = ((index - 1 + delta) % #pages) + 1
        applyPage()
      end or nil,
    })
    applyPage()

    -- ListMenu draws one line per row; the level range rides underneath it in
    -- the row's second half, the way the Gen 2 pack hangs a quantity there.
    local baseDraw = list.draw
    list.draw = function(self)
      baseDraw(self)
      local Font = mod.ui.Font
      love.graphics.setColor(0, 0, 0, 1)
      for row = 1, self.rows do
        local item = self.items[self.scroll + row]
        if not item then break end
        if item.sub then Font.draw(item.sub, 24, 8 + row * 16 + 8) end
      end
      Font.draw(place, 8, 120)
      local page = pages[index]
      if page.note ~= "" then Font.draw(page.note, 8, 136) end
      if #pages > 1 then
        local tag = index .. "/" .. #pages
        Font.draw(tag, 152 - Font.width(tag), 136)
        -- the GB font has no side arrows, so the page markers are drawn the
        -- way the pack draws its pocket ones
        love.graphics.polygon("fill", 138, 8, 144, 4, 144, 12)
        love.graphics.polygon("fill", 158, 8, 152, 4, 152, 12)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end

    game.stack:push(list)
  end

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" then return out end
    if mod.options:get("enabled") == false then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = "RADAR",
      onSelect = function() open(game) end,
    })
  end)
end
