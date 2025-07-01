-- Turns things into readable strings
local fmt = string.format
local lua_tostring = tostring
local function tostring(value, seen, indent)
  if type(value) ~= "table" then
    return lua_tostring(value)
  end

  if seen[value] then
    return seen[value]
  end

  local pad = string.rep(' ', indent)

  local lines = {}
  for k, v in pairs(value) do
    local key = tostring(k, seen, 0)
    local val = tostring(v, seen, 0)
    if type(k) == 'string' then
      key = fmt('"%s"', key)
    end
    table.insert(lines, fmt("[ %s ] = %s,", key, val))
  end
  for i = 1, #lines do
    lines[i] = pad .. lines[i]
  end
  return fmt("{ %s }", table.concat(lines, "\n"))
end

return setmetatable({

}, {
  __call = function(v)
    return tostring(v, {}, 0)
  end,
})
