---@param signal SignalFilter.0
---@param value int32
---@return LogisticFilter
local function signal_value(signal, value)
  local quality = "normal"
  if script.active_mods["quality"] and signal.quality then
      quality = signal.quality
  end

  return {
    value = {
      type       = signal.type or "item",
      name       = signal.name,
      quality    = quality,
      comparator = "=",
    },
    min = math.min(math.max(value, -0x80000000), 0x7fffffff),
  }
end

---@param target UCControl
---@param filters LogisticFilter[]
---@return boolean
local function write_control(target, filters)
  local entity = target.entity
  if not entity.valid then return false end

  local control = target.control
  if not (control and control.valid) then
    control = entity.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    target.control = control
  end

  --TODO: check/force exactly one unnamed section
  control.enabled = true
  control.sections[1].filters = filters or {}
  return true
end

local function UpdateBonuses()
  for _, force in pairs(game.forces) do
    storage.bonus_log_filter[force.index] = {
      signal_value({name="lab"                 , type="item"   }, force.laboratory_productivity_bonus),
      signal_value({name="logistic-robot"      , type="item"   }, force.worker_robots_storage_bonus),
      signal_value({name="fast-inserter"       , type="item"   }, force.inserter_stack_size_bonus),
      signal_value({name="bulk-inserter"       , type="item"   }, force.bulk_inserter_capacity_bonus),
      signal_value({name="turbo-transport-belt", type="item"   }, force.belt_stack_size_bonus),
      signal_value({name="toolbelt-equipment"  , type="item"   }, force.character_inventory_slots_bonus),
      signal_value({name="big-mining-drill"    , type="item"   }, force.mining_drill_productivity_bonus * 100),
      signal_value({name="locomotive"          , type="item"   }, force.train_braking_force_bonus),
      signal_value({name="signal-heart"        , type="virtual"}, force.character_health_bonus),
      signal_value({name="signal-B"            , type="virtual"}, force.character_build_distance_bonus),
      signal_value({name="signal-D"            , type="virtual"}, force.character_item_drop_distance_bonus),
      signal_value({name="signal-R"            , type="virtual"}, force.character_resource_reach_distance_bonus),
      signal_value({name="signal-I"            , type="virtual"}, force.character_item_pickup_distance_bonus),
      signal_value({name="signal-L"            , type="virtual"}, force.character_loot_pickup_distance_bonus),
      signal_value({name="signal-F"            , type="virtual"}, force.maximum_following_robot_count)
    }
  end
end

local function UpdateResearch()
  ---@type {[integer]:LogisticFilter[]}
  local log_filters = {}
  for _, force in pairs(game.forces) do

    if force.current_research then
      ---@type LogisticFilter[]
      local log_filter = {
        signal_value({name="signal-info"      , type="virtual"}, math.floor(game.forces[force.index].research_progress * 100)),
        signal_value({name="signal-stack-size", type="virtual"}, force.current_research.research_unit_count),
        signal_value({name="signal-T"         , type="virtual"}, force.current_research.research_unit_energy)
      }

      for _, item in pairs(force.current_research.research_unit_ingredients) do
        -- Normal quality
        log_filter[#log_filter+1] = signal_value(item--[[@as SignalFilter.0]], item.amount)

        -- Loop through all higher qualities
        for quality, _ in pairs(data.raw.quality) do
          local ingredient = table.deepcopy(item)
          ingredient.quality = quality
          log_filter[#log_filter+1] = signal_value(ingredient--[[@as SignalFilter.0]], ingredient.amount)
        end
      end

      log_filters[force.index] = log_filter
    end
  end

  storage.research_log_filter = log_filters
end

script.on_event({
  defines.events.on_research_started,
  defines.events.on_research_finished,
  defines.events.on_research_moved,
  defines.events.on_research_cancelled,
  defines.events.on_research_reversed,
  defines.events.on_force_created,
  defines.events.on_forces_merging
  }, function()
  UpdateBonuses()
  UpdateResearch()

  for n, research_control in pairs(storage.research_control) do
    if not (research_control.entity.valid and write_control(research_control, storage.research_log_filter[research_control.entity.force.index])) then
      storage.research_control[n] = nil
    end
  end
  for n, bonus_control in pairs(storage.bonus_control) do
    if not (bonus_control.entity.valid and write_control(bonus_control, storage.bonus_log_filter[bonus_control.entity.force.index])) then
      storage.bonus_control[n] = nil
    end
  end
end)

---@type {[string]:fun(entity:LuaEntity)}
local onBuilt = {
  ["bonus-combinator"] = function(entity)
    entity.operable = false
    local bonus_control = {entity=entity}
    storage.bonus_control[entity.unit_number] = bonus_control
    write_control(bonus_control, storage.bonus_log_filter[entity.force.index])
  end,
  ["location-combinator"] = function(entity)
    entity.operable=false
    local location_control = {entity=entity}
    write_control(location_control, {
      signal_value({name="signal-X", type="virtual"}, math.floor(entity.position.x)),
      signal_value({name="signal-Y", type="virtual"}, math.floor(entity.position.y)),
      signal_value({name="signal-Z", type="virtual"}, entity.surface.index),
    })
  end,
  ["research-combinator"] = function(entity)
    entity.operable = false
    local research_control = {entity=entity}
    storage.research_control[entity.unit_number] = research_control
    write_control(research_control, storage.research_log_filter[entity.force.index])
  end,
}

---@class (exact) UCControl
---@field entity LuaEntity
---@field control? LuaConstantCombinatorControlBehavior

local function on_init()
  ---@class (exact) UCStorage
  ---@field bonus_control {[integer]:UCControl} unit_number -> entity,control
  ---@field bonus_log_filter {[integer]:LogisticFilter[]} forceid -> data
  ---@field research_control {[integer]:UCControl} unit_number -> entity,control
  ---@field research_log_filter {[integer]:LogisticFilter[]} forceid -> data
  storage.bonus_control       = {}
  storage.bonus_log_filter    = {}
  storage.research_control    = {}
  storage.research_log_filter = {}

  UpdateBonuses()
  UpdateResearch()

  -- index existing combinators (init and config changed to capture from deprecated mods as well)
  -- and re-index the world
  for _, surf in pairs(game.surfaces) do
    for _, entity in pairs(surf.find_entities_filtered{name = {"bonus-combinator", "location-combinator", "research-combinator",}}) do
      local handler = onBuilt[entity.name]
      if handler then
        handler(entity)
      end
    end
  end
end
