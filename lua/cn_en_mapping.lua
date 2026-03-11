--[[
中英文映射词典（分片按需加载版）

原理：
1. 将 50 万+ 映射拆成按首字分片的小文件：lua/cn_en_shards/*.lua
2. 查询时按首字定位分片，只加载命中的分片
3. 使用 LRU 缓存分片，限制常驻内存

效果：
- 避免一次性加载 21MB 大表
- 输入中途只会触发“单分片”加载（通常几十 KB）
- 常用分片常驻缓存，后续查询稳定
--]]

local M = {}

local shard_index = require("cn_en_shards_index").shards

local shard_cache = {}
local cache_order = {}
local max_cache_shards = 5000

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

local function touch_cache(key)
    for i, value in ipairs(cache_order) do
        if value == key then
            table.remove(cache_order, i)
            break
        end
    end
    cache_order[#cache_order + 1] = key

    if #cache_order > max_cache_shards then
        local old = table.remove(cache_order, 1)
        shard_cache[old] = nil
    end
end

local function load_shard(key)
    if shard_cache[key] then
        touch_cache(key)
        return shard_cache[key]
    end

    if not shard_index[key] then
        shard_cache[key] = false
        touch_cache(key)
        return false
    end

    local ok, module = pcall(require, "cn_en_shards." .. key)
    if not ok or not module or not module.mapping then
        shard_cache[key] = false
        touch_cache(key)
        return false
    end

    shard_cache[key] = module.mapping
    touch_cache(key)
    return module.mapping
end

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
