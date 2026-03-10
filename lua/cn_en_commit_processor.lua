--[[
中文候选英文上屏处理器（轻量）
功能：在候选菜单中按 Shift+space，直接上屏当前候选的英文映射。

使用：
在 schema 的 engine/processors 中添加：
  - lua_processor@*cn_en_commit_processor

可选配置：
cn_en_commit_processor:
  enable: true
  commit_english_key: Shift+space
--]]

local cn_en_mapping = require("cn_en_mapping")

local M = {}

function M.init(env)
    local config = env.engine.schema.config
    local name_space = env.name_space:gsub("^%*", "")

    env.enable = config:get_bool(name_space .. "/enable")
    if env.enable == nil then
        env.enable = true
    end

    env.commit_english_key = config:get_string(name_space .. "/commit_english_key") or "Shift+space"
    env.mapping = cn_en_mapping.mapping or {}
end

function M.func(key, env)
    if not env.enable then
        return 2
    end

    if key:release() then
        return 2
    end

    if key:repr() ~= env.commit_english_key then
        return 2
    end

    local engine = env.engine
    local context = engine.context
    if not context:has_menu() then
        return 2
    end

    local cand = context:get_selected_candidate()
    if not cand or not cand.text or cand.text == "" then
        return 2
    end

    local english = env.mapping[cand.text]
    if not english or english == "" then
        return 2
    end

    engine:commit_text(english)
    context:clear()
    return 1
end

function M.fini(env)
    env.mapping = nil
end

return M
