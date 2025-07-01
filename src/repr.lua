-- Turns things into readable strings
local fmt = string.format

local function tostr(value, seen)
  if type(value) == "string" then
    return fmt("%q", value)
  end
  if type(value) ~= "table" then
    return tostring(value)
  end

  if seen[value] then
    return seen[value]
  end

  if value.tag == "Symbol" then
    return ":" .. value[1]
  end

  if value.tag == "Number" then
    return tostring(value[1])
  end

  local lines = {}
  for k, v in pairs(value) do
    local key = tostr(k, seen)
    local val = tostr(v, seen)

    if type(k) == "number" then
      table.insert(lines, fmt("%s,", val))
    else
      table.insert(lines, fmt("[ %s ] = %s,", key, val))
    end
  end

  return fmt("{ %s }", table.concat(lines, " "))
end

return setmetatable({}, {
  __call = function(_, v)
    return tostr(v, {})
  end,
})
