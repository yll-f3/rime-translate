--[[
中英文映射词典（分片按需加载版）

原理：
1. 将 50 万+ 映射拆成按首字分片的小文件：lua/cn_en_shards/*.lua
2. 查询时按首字定位分片，只加载命中的分片
3. 用完即释放：每次查询后清理 package.loaded，避免分片常驻
--]]

local M = {}

local shard_index = require("cn_en_shards_index").shards

local function shard_key(text)
    if not text or text == "" then
        return "_empty"
    end

    local first_char = text:sub(1, 3)
    local bytes = {first_char:byte(1, #first_char)}
    local parts = {}
    for _, byte in ipairs(bytes) do
        parts[#parts + 1] = string.format("%02x", byte)
    end
    return "u" .. table.concat(parts, "_")
end

local function load_shard(key)
    if not shard_index[key] then
        return false
    end

    local module_name = "cn_en_shards." .. key

    package.loaded[module_name] = nil

    local ok, module = pcall(require, module_name)
    if not ok or not module or not module.mapping then
        package.loaded[module_name] = nil
        return false
    end

    local mapping = module.mapping
    package.loaded[module_name] = nil
    return mapping
end

-- 通过元表按需查询：每次访问按需加载分片，用完即释放
M.mapping = setmetatable({}, {
    __index = function(_, chinese_text)
        local key = shard_key(chinese_text)
        local shard = load_shard(key)
        if not shard then
            return nil
        end
        return shard[chinese_text]
    end,
})

function M.get_translation(chinese_text)
    return M.mapping[chinese_text]
end

return M
