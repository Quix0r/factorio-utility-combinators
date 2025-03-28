require("lua/functions")

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
      signal_value({name="signal-X", type="virtual"},math.floor(entity.position.x)),
      signal_value({name="signal-Y", type="virtual"},math.floor(entity.position.y)),
      signal_value({name="signal-Z", type="virtual"},entity.surface.index),
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
  storage = {
    bonus_control = {},
    bonus_log_filter = {},

    research_control = {},
    research_log_filter = {},
  }

  UpdateBonuses()
  UpdateResearch()

  -- index existing combinators (init and config changed to capture from deprecated mods as well)
  -- and re-index the world
  for _,surf in pairs(game.surfaces) do
    for _,entity in pairs(surf.find_entities_filtered{name = {"bonus-combinator", "location-combinator", "research-combinator",}}) do
      local handler = onBuilt[entity.name]
      if handler then
        handler(entity)
      end
    end
  end
end

script.on_init(on_init)
script.on_configuration_changed(function(data)
  if data.mod_changes and data.mod_changes["utility-combinators"] then
    on_init()
  end
end)

script.on_nth_tick(60, function()
  UpdateResearch()
  for n, research_control in pairs(storage.research_control) do
    if not (research_control.entity.valid and write_control(research_control, storage.research_log_filter[research_control.entity.force.index])) then
      storage.research_control[n] = nil
    end
  end
end)

script.on_event(defines.events.on_script_trigger_effect, function (event)
  if event.effect_id == "utility-combinator-created" then
    local entity = event.cause_entity
    if entity then
      local handler = onBuilt[entity.name]
      if handler then
        handler(entity)
      end
    end
  end
end)
