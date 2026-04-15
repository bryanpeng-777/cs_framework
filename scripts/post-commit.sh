#!/bin/bash
# cs_framework post-commit hook
# 监测框架核心文件变更，自动更新 cs-stack-onboarding SKILL.md

SKILL_PATH="/Users/bryanpeng/.claude/skills/cs-stack-onboarding/SKILL.md"
WATCH_PATTERNS="pubspec\.yaml|lib/network/|lib/storage/|lib/utils/app_logger|main\.dart"

# 获取本次 commit 变更的文件列表
CHANGED=$(git show --name-only --format="" HEAD 2>/dev/null)
RELEVANT=$(echo "$CHANGED" | grep -E "$WATCH_PATTERNS" || true)

if [ -z "$RELEVANT" ]; then
  exit 0
fi

echo "🔄 框架文件变更，正在更新 cs-stack-onboarding 技能..."
echo "   变更文件：$(echo $RELEVANT | tr '\n' ' ')"

# 收集 diff 摘要
DIFF_SUMMARY=$(git show HEAD -- $RELEVANT 2>/dev/null)

# 调用 claude CLI 更新 SKILL.md
claude --print \
  "以下是 cs_framework 仓库的最新代码变更（只包含框架核心文件）。
请根据变更内容更新 cs-stack-onboarding 的 SKILL.md（路径：$SKILL_PATH），
重点更新：版本号、代码模板、CLAUDE.md 生成模板中的代码示例。
保持 SKILL.md 整体结构不变，只修改受影响的部分。

变更文件：
$RELEVANT

Diff：
$DIFF_SUMMARY" \
  --allowedTools "Read,Write,Glob,Grep" 2>/dev/null \
  && echo "✅ cs-stack-onboarding SKILL.md 已更新" \
  || echo "⚠️  claude CLI 不可用，已跳过自动更新。如需手动更新，请在 Cursor 中运行 evolve 技能"
