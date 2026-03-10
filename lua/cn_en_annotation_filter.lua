--[[
中文候选项英文注释过滤器
功能：为中文候选项自动添加英文翻译注释

使用方法：
在 schema 文件的 engine/filters 中添加：
  - lua_filter@*cn_en_annotation_filter

配置选项（在 schema 文件中）：
cn_en_annotation_filter:
  enable: true                    # 是否启用，默认 true
  show_for_single_char: false     # 是否为单字显示，默认 false（只为词组显示）
  format: " / {english}"          # 显示格式，{english} 为占位符
  only_for_types: []              # 只对特定类型生效，默认为空数组（对所有类型生效）
                                  # 可选值：["table", "completion", "sentence", "reverse_lookup"]
--]]

local cn_en_mapping = require("cn_en_mapping")

local M = {}

-- 初始化函数
function M.init(env)
    local config = env.engine.schema.config
    local name_space = env.name_space:gsub("^%*", "")
    
    -- 读取配置
    env.enable = config:get_bool(name_space .. "/enable")
    if env.enable == nil then
        env.enable = true  -- 默认启用
    end
    
    env.show_for_single_char = config:get_bool(name_space .. "/show_for_single_char")
    if env.show_for_single_char == nil then
        env.show_for_single_char = false  -- 默认不为单字显示
    end
    
    env.format = config:get_string(name_space .. "/format") or " / {english}"

    -- 读取只对特定类型生效的配置
    env.only_for_types = {}
    local types_list = config:get_list(name_space .. "/only_for_types")
    if types_list then
        for i = 0, types_list.size - 1 do
            local type_value = types_list:get_value_at(i).value
            env.only_for_types[type_value] = true
        end
    end
    
    -- 加载映射表
    env.mapping = cn_en_mapping.mapping
    
    -- 缓存：存储已处理过的候选项
    env.cache = {}
    
    -- 预编译占位符匹配
    env.format_has_placeholder = env.format:find("{english}", 1, true) ~= nil
    
    -- 输出调试信息
    local log_msg = string.format(
        "cn_en_annotation_filter initialized: enable=%s, show_for_single_char=%s, mappings=%d",
        tostring(env.enable),
        tostring(env.show_for_single_char),
        #env.mapping
    )
    -- print(log_msg)  -- 可选：启用调试日志
end

-- 判断是否为纯中文文本（优化版）
local function is_chinese_text(text)
    -- 检查第一个字符是否为中文（改进的判断方法）
    -- UTF-8 中文范围：U+4E00 ~ U+9FFF
    -- 对应 UTF-8 字节：E4 B8 80 ~ E9 BE BF
    if text:len() < 3 then return false end
    
    local byte1 = text:byte(1)
    if byte1 >= 224 and byte1 <= 233 then  -- E4-E9
        return true
    end
    return false
end

-- 计算文本中的字符数（支持多字节字符）- 优化版本
local function utf8_len(text)
    -- 快速路径：只检查是否为单字
    if text:len() <= 3 then return 1 end
    
    local len = 0
    local i = 1
    while i <= #text do
        local c = text:byte(i)
        if c < 128 then
            i = i + 1
        elseif c < 224 then
            i = i + 2
        elseif c < 240 then
            i = i + 3
        else
            i = i + 4
        end
        len = len + 1
    end
    return len
end

-- 过滤函数（优化版）
function M.func(input, env)
    if not env.enable then
        -- 如果未启用，直接返回所有候选项
        for cand in input:iter() do
            yield(cand)
        end
        return
    end
    
    for cand in input:iter() do
        local text = cand.text
        
        -- 快速路径：检查基本条件（避免不必要的处理）
        local should_process = true
        
        -- 要点改进：将检查顺序改为从快到慢
        
        -- 1. 先检查是否为中文文本（快速检查）
        if should_process and not is_chinese_text(text) then
            should_process = false
        end
        
        -- 2. 再检查类型限制
        if should_process and next(env.only_for_types) ~= nil then
            should_process = env.only_for_types[cand.type] ~= nil
        end
        
        -- 3. 最后检查是否为单字（如需要）
        if should_process and not env.show_for_single_char then
            -- 只对多字符候选项处理
            if text:len() <= 3 then
                should_process = false
            end
        end
        
        -- 如果应该处理，查找翻译并添加注释
        if should_process then
            local english = env.mapping[text]
            if english then
                local annotation
                if env.format_has_placeholder then
                    annotation = env.format:gsub("{english}", english)
                else
                    annotation = env.format .. english
                end
                
                -- 创建新的候选项
                if cand.comment and cand.comment ~= "" then
                    -- 如果已有 comment，追加
                    cand = cand:to_shadow_candidate(
                        cand.type,
                        cand.text,
                        cand.comment .. annotation
                    )
                else
                    -- 如果没有 comment，直接设置
                    cand = cand:to_shadow_candidate(
                        cand.type,
                        cand.text,
                        annotation
                    )
                end
            end
        end
        
        yield(cand)
    end
end

-- 清理函数
function M.fini(env)
    -- 清理资源（如果需要）
end

return M
