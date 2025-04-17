local M = {}
M.API = "http://localhost:6070/api/search"
M.ShardMaxMatchCount = 200
M.MaxWallTime = 2000 -- unit seems ms
M.QueryPrefix = "" -- default empty prefix for search queries

return M
