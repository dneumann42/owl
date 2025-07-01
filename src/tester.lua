local repr = require("src.repr")

local function is_equal(a, b, seen)
  seen = seen or {}
  if seen[a] then
    return seen[a]
  end
  seen[a] = a
  if seen[b] then
    return seen[b]
  end
  seen[b] = b

  if type(a) ~= type(b) then
    return false
  end

  if type(a) == "table" then
    if #a ~= #b then
      return false
    end
    for k, v in pairs(a) do
      if not is_equal(v, b[k], seen) then
        return false
      end
    end
    return true
  else
    return a == b
  end
end

local RED = "\27[31m"
local GREEN = "\27[32m"
local RESET = "\27[0m"

local function string_diff(s1, s2)
  local len1 = #s1
  local len2 = #s2
  local maxlen = math.max(len1, len2)

  local line1 = {} -- original string (deletions)
  local line2 = {} -- new string (additions)

  for i = 1, maxlen do
    local c1 = i <= len1 and s1:sub(i, i) or ""
    local c2 = i <= len2 and s2:sub(i, i) or ""

    if c1 == c2 then
      table.insert(line1, c1)
      table.insert(line2, c2)
    else
      table.insert(line1, c1 ~= "" and (RED .. c1 .. RESET) or " ")
      table.insert(line2, c2 ~= "" and (GREEN .. c2 .. RESET) or " ")
    end
  end

  return table.concat(line1) .. "\n" .. table.concat(line2)
end

local function run_tests(tbl)
  local failed = 0
  local success = 0
  local total = 0
  for k, v in pairs(tbl) do
    local ok, err = pcall(v)
    total = total + 1
    if ok then
      io.write(GREEN, "✔️", k, RESET, '\n')
      success = success + 1
    else
      failed = failed + 1
      io.write(RED, "❌", k, " ", RESET, err, RESET, '\n')
    end
  end

  print(string.format("Total: %d, " .. GREEN .. "✔️" .. RESET .. "Success: %d, " .. RED .. "❌" .. RESET .. "Failed: %d",
    total, success, failed))
end

local function assert_equal(a, b)
  return assert(repr(a) == repr(b),
    string.format("Expected:\n%s\nGot:\n%s\nDIFF:\n%s\n", repr(a), repr(b), string_diff(repr(a), repr(b))))
end

return {
  is_equal = is_equal,
  assert_equal = assert_equal,
  diff = string_diff,
  run_tests = run_tests
}
