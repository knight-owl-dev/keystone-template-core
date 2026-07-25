-- handler-classes.lua — Discover handler class names from divs/ subdirectories
--
-- A subdirectory is recognized as a handler type only when it contains
-- handler.lua. This cleanly skips stray files (.DS_Store, READMEs, etc.).
--
-- Returns a set (table with class names as keys, true as values).
--
-- Used by divs.lua (for routing) and shortcuts.lua (for namespace validation).

local lib = {}

--- Scan a directory for handler subdirectories.
---@param divs_dir string          Path to the divs/ directory
---@param list_directory function  pandoc.system.list_directory (injected for testability)
---@param path_join function       pandoc.path.join (injected for testability)
---@return table  { class_name = true, ... }
function lib.discover(divs_dir, list_directory, path_join)
  local classes = {}
  local entries = list_directory(divs_dir)
  table.sort(entries)

  for _, entry in ipairs(entries) do
    local handler_path = path_join({ divs_dir, entry, "handler.lua" })
    local probe = io.open(handler_path, "r")
    if probe then
      probe:close()
      classes[entry] = true
    end
  end

  return classes
end

return lib
