-- env-io.lua — Environment-driven file I/O for Pandoc filters
--
-- Filters receive output paths from publish.sh via environment variables
-- (KEYSTONE_CSS_FONTS, KEYSTONE_CSS_DIVS, KEYSTONE_FONT_SCAN_OUTPUT).
-- This module centralizes the env-var-to-file-write contract:
--   1. Read the path from an env var (error if unset)
--   2. Write content to that path (error on failure — never silently skip)

local lib = {}

-- Seams for testing — override to control env/IO in busted specs
lib._getenv = os.getenv
lib._open = io.open

--- Read the output path from an environment variable.
--- Errors if the variable is not set.
---@param var_name string environment variable name
---@return string value
function lib.require_env(var_name)
  local val = lib._getenv(var_name)
  if not val then
    error(var_name .. " not set — this filter must be called by publish.sh")
  end
  return val
end

--- Write content to the path in an environment variable.
--- Returns the resolved path so callers can append it to meta.css.
--- Errors if the env var is missing or any I/O step fails.
---@param env_var string environment variable holding the output path
---@param content string data to write
---@return string path resolved file path
function lib.write_file(env_var, content)
  local path = lib.require_env(env_var)
  local f, open_err = lib._open(path, "w")
  if not f then
    error("failed to open " .. path .. ": " .. (open_err or "unknown error"))
  end
  local _, write_err = f:write(content)
  if write_err then
    f:close()
    error("failed to write to " .. path .. ": " .. write_err)
  end
  local _, close_err = f:close()
  if close_err then
    error("failed to close " .. path .. ": " .. close_err)
  end
  return path
end

return lib
