local config = require("config")
local curl = require("plenary.curl")
local json = require("json")
local base64 = require'base64'

local M = {}
local actions = {}

-- Function to set search query prefix
actions.set_query_prefix = function(prefix)
  -- If no prefix provided, ask the user
  if not prefix or prefix == "" then
    vim.ui.input({ prompt = "Set search query prefix: ", default = config.QueryPrefix }, function(input)
      if input then -- input can be empty to clear the prefix
        config.QueryPrefix = input
        vim.notify("Search query prefix set to: '" .. input .. "'", vim.log.levels.INFO)
      end
    end)
    return
  end
  
  -- Set the prefix directly if provided
  config.QueryPrefix = prefix
  vim.notify("Search query prefix set to: '" .. prefix .. "'", vim.log.levels.INFO)
end

-- Function to display configuration settings
actions.display_config = function()
  local config_items = {}
  
  for key, value in pairs(config) do
    table.insert(config_items, { key = key, value = tostring(value) })
  end
  
  vim.ui.select(config_items, {
    prompt = "Zoekt Configuration",
    format_item = function(item)
      return item.key .. ": " .. item.value
    end
  }, function(_, _) end)
end

-- Function to perform search and display results
actions.search_code = function(query)
  -- If no query provided, ask the user
  if not query or query == "" then
    vim.ui.input({ prompt = "Search code: " }, function(input)
      if input and input ~= "" then
        actions.search_code(input)
      end
    end)
    return
  end

  -- Apply prefix to query if set
  local full_query = query
  if config.QueryPrefix and config.QueryPrefix ~= "" then
    full_query = config.QueryPrefix .. " " .. query
  end

  -- process '\\' in the query and other special characters
  -- Escape backslashes
  full_query = full_query:gsub("\\", "\\\\")

  -- Show searching indicator
  local notify_id = vim.notify("Searching for: " .. full_query, vim.log.levels.INFO)

  -- Get zoekt server URL from config
  local zoekt_url = config.server_url or "http://localhost:6070"
  local api_endpoint = zoekt_url .. "/api/search"

  -- Prepare POST request data
  local post_data = {
    Q = full_query,
    Opts = {
      ShardMaxMatchCount = config.ShardMaxMatchCount,
      MaxWallTime = config.MaxWallTime,
    }
  }

  -- Perform API request
  curl.post({
    url = api_endpoint,
    body = json.encode(post_data),
    headers = {
      ["Content-Type"] = "application/json",
    },
    callback = function(response)
      -- Schedule to run on the main Neovim thread
      vim.schedule(function()
        -- Clear the searching notification
        vim.notify("Search complete", vim.log.levels.INFO, {
          replace = notify_id
        })
        
        if response.status ~= 200 then
          vim.notify("Error: Could not connect to Zoekt server. Status: " .. 
            (response.status or "unknown"), vim.log.levels.ERROR)
          return
        end

        -- Parse JSON response
        local ok, results = pcall(json.decode, response.body)
        if not ok or not results then
          vim.notify("Error parsing search results", vim.log.levels.ERROR)
          return
        end

        -- Format results for selection UI - flat format with no separate file entries
        local select_items = {}
        
        -- Check if we have file results
        if results.Result and results.Result.Files and #results.Result.Files > 0 then
          local match_count = 0
          
          for _, file in ipairs(results.Result.Files) do
            -- Add line matches if available
            if file.LineMatches then
              for _, match in ipairs(file.LineMatches) do
                match_count = match_count + 1
                local line_num = match.LineNumber or "?"
                
                -- Decode base64 line content if present
                local line_text = match.Line or ""
                local decoded = ""
                
                if line_text ~= "" then
                  decoded = base64.decode(line_text) or "[Failed to decode content]"
                  -- Remove trailing newlines
                  decoded = decoded:gsub("[\r\n]+$", "")
                  -- Replace newlines with spaces for display
                  decoded = decoded:gsub("[\r\n]+", " … ")
                end
                
                local match_entry = {
                  filename = file.FileName,
                  line_number = tonumber(line_num),
                  content = decoded
                }
                
                table.insert(select_items, match_entry)
              end
            end
          end
          
          -- Use vim.ui.select to display and select from search results
          vim.ui.select(select_items, {
            prompt = "Search results for: " .. full_query .. " (" .. match_count .. " matches in " .. #results.Result.Files .. " files)",
            format_item = function(item)
              -- Format as filename:linenum->content
              return item.filename .. ":" .. item.line_number .. "->" .. item.content
            end
          }, function(item)
            -- If a match was selected, navigate to the file and line
            if item then
              -- Open the file and jump to the line
              vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
              vim.api.nvim_win_set_cursor(0, {item.line_number, 0})
              -- Center the view on the line
              vim.cmd("normal! zz")
            end
          end)
        else
          vim.notify("No results found for: " .. full_query, vim.log.levels.INFO)
          return
        end
      end)
    end
  })
end

-- Setup function to initialize the plugin
function M.setup(opts)
  -- Merge user options with defaults
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end

  -- Add Neovim commands
  vim.api.nvim_create_user_command('ZoektConfig', function()
    actions.display_config()
  end, { desc = "Display zoekt.nvim configuration" })
  
  vim.api.nvim_create_user_command('ZoektSearch', function(cmd_opts)
    actions.search_code(cmd_opts.args)
  end, { nargs = "?", desc = "Search code using Zoekt" })

  vim.api.nvim_create_user_command('ZoektSetQueryPrefix', function(cmd_opts)
    actions.set_query_prefix(cmd_opts.args)
  end, { nargs = "?", desc = "Set prefix for all Zoekt search queries" })

end

return setmetatable(M, {
   __index = function(_, f)
      return actions[f]
   end,
})
