local M = {}
M.API = "http://localhost:6070/api/search"
M.QueryPrefix = "" -- default empty prefix for search queries
M.DebugMode = false -- debug mode to print server responses
M.curl_timeout = 8000 -- timeout for curl requests

return M
