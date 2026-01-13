---
name: sdcl-mode
description: "Self-Directed Code Loop v3.0 - GitHub Centralized Workflow. Automates the cycle of Task Assignment -> Remote Codex Dev -> GitHub Push -> Local Pull -> Auto-Merge."
version: "3.0"
author: "Claude-User-Optimized"
tags: ["automation", "workflow", "git-ops", "codex"]
---

# SDCL Mode: GitHub-Centralized Workflow

此模式用于自动化执行 `PLAN.md` 中的开发任务。它将 Claude/Codex 视为远程协作开发者，将 GitHub 视为唯一的数据中枢。

## 🏗️ 架构逻辑

1.  **Local (Claude)**: 解析任务，向 Codex 发送指令。
2.  **Remote (Codex)**: 编写代码 -> Commit -> **Push to GitHub**。
3.  **Local (Monitor)**: 轮询 GitHub -> 发现新分支 -> **Pull to Local**。
4.  **Local (Closure)**: 验证代码 -> **Merge to Main** -> **Push Main** -> 更新 PLAN。

---

## 📋 前置准备 (Prerequisites)

1.  项目根目录必须存在 `.codex-env` 文件，包含 `CODEX_ENV_ID=...`。
2.  项目根目录必须存在 `PLAN.md` (包含 `- [ ] TASK-XXX: Description` 格式的任务)。
3.  项目必须是一个 Git 仓库，且已关联远程 Origin。
4.  本地环境需安装 `git`。

---

## 🤖 自动化执行脚本 (run_sdcl_cycle.sh)

你可以将以下脚本保存为 `scripts/run_sdcl_cycle.sh` 并赋予执行权限 (`chmod +x`)。

```bash
#!/bin/bash
set -e # 遇到错误立即停止

# ========================================================
# 🟢 STEP 0: 环境预检与同步 (Pre-flight)
# ========================================================
echo "========================================="
echo "🔄 [Step 0] 环境预检与同步"
echo "========================================="

if [ ! -f .codex-env ]; then
    echo "❌ 错误: 找不到 .codex-env 配置文件"
    exit 1
fi
source .codex-env

# 确保本地 Main 是最新的，且工作区干净
git checkout main --quiet
git pull origin main --quiet

if ! git diff-index --quiet HEAD --; then
    echo "❌ 错误: 本地有未提交的修改。请先 Commit 或 Stash。"
    exit 1
fi
echo "✅ 本地环境干净且已同步"


# ========================================================
# 🔵 STEP 1: 领取任务 (Pick Task)
# ========================================================
echo ""
echo "========================================="
echo "📋 [Step 1] 读取 PLAN.md"
echo "========================================="

# 查找第一个未完成的任务
NEXT_TASK=$(grep -n "^- \[ \]" PLAN.md | head -1)

if [ -z "$NEXT_TASK" ]; then
    echo "🎉 所有任务已完成！流程结束。"
    exit 0
fi

# 解析任务数据
LINE_NUMBER=$(echo "$NEXT_TASK" | cut -d: -f1)
TASK_LINE=$(echo "$NEXT_TASK" | cut -d: -f2-)
TASK_ID=$(echo "$TASK_LINE" | grep -oE 'TASK-[0-9]+' | grep -oE '[0-9]+')
TASK_DESC=$(echo "$TASK_LINE" | sed 's/.*TASK-[0-9]*: //')

echo "🎯 锁定任务: TASK-$TASK_ID"
echo "📝 任务描述: $TASK_DESC"


# ========================================================
# 🟠 STEP 2: 构建指令与分发 (Dispatch)
# ========================================================
echo ""
echo "========================================="
echo "🚀 [Step 2] 发送指令给 Codex"
echo "========================================="

BRANCH_NAME="feature/task-${TASK_ID}"

# 构建 Prompt
cat > /tmp/sdcl_prompt.txt << EOF
🚨 CRITICAL INSTRUCTION: REMOTE GIT COLLABORATION 🚨

你现在的角色是远程高级工程师。必须严格遵守以下 Git 协作流程。

【任务目标】
ID: TASK-${TASK_ID}
需求: ${TASK_DESC}

【必须执行的操作步骤】
1. 基于当前代码库创建分支: git checkout -b ${BRANCH_NAME}
2. 完成代码编写。
3. 提交代码: git commit -am "feat: implement TASK-${TASK_ID}"
4. 🚀 关键步骤: 必须推送到远程仓库: git push -u origin ${BRANCH_NAME}

【注意】
- 不要合并到 main，只要 push 分支即可。
- 只有 Push 成功，我的本地流程才能继续。
EOF

# 如果有 SPEC.md，附加上去
if [ -f SPEC.md ]; then
    echo "" >> /tmp/sdcl_prompt.txt
    echo "【项目规范】" >> /tmp/sdcl_prompt.txt
    cat SPEC.md >> /tmp/sdcl_prompt.txt
fi

echo "📡 正在请求 Codex 执行任务..."
# 注意：这里假设你使用了 codex cli 工具，请根据实际情况替换命令
codex cloud exec --env "$CODEX_ENV_ID" "$(cat /tmp/sdcl_prompt.txt)" > /tmp/codex_exec.log 2>&1 &
PID=$!

echo "✅ 指令已发送 (PID: $PID)，等待 Codex 响应..."
wait $PID


# ========================================================
# 🟡 STEP 3: 监控 GitHub 中枢 (Monitor Origin)
# ========================================================
echo ""
echo "========================================="
echo "📡 [Step 3] 监控 GitHub 远程仓库"
echo "========================================="
echo "目标分支: origin/$BRANCH_NAME"

MAX_WAIT=900 # 15分钟超时
ELAPSED=0
CHECK_INTERVAL=15

while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    
    printf "\r⏳ 等待远程分支出现... (%3d秒)" $ELAPSED

    # 刷新远程数据
    git fetch origin --quiet

    # 检查远程分支是否存在
    if git rev-parse --verify "origin/$BRANCH_NAME" > /dev/null 2>&1; then
        echo ""
        echo "✅ 捕获到远程分支！Codex 已完成推送。"
        break
    fi
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo ""
    echo "❌ 错误: 等待超时。Codex 未能将代码推送到 GitHub。"
    exit 1
fi


# ========================================================
# 🟣 STEP 4: 拉取与同步 (Pull)
# ========================================================
echo ""
echo "========================================="
echo "📥 [Step 4] 同步代码到本地"
echo "========================================="

# 切换到该分支并追踪远程
if git rev-parse --verify "$BRANCH_NAME" > /dev/null 2>&1; then
    # 如果本地已有脏分支，先切过去拉取
    git checkout "$BRANCH_NAME"
    git pull origin "$BRANCH_NAME"
else
    # 建立新分支追踪远程
    git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME"
fi

echo "✅ 代码已同步到本地工作区"


# ========================================================
# ⚪ STEP 5: 验证 (Validate) - 可选
# ========================================================
if [ -f "scripts/validator.sh" ]; then
    echo ""
    echo "🧪 [Step 5] 执行自动化验证"
    if ! ./scripts/validator.sh; then
        echo "❌ 验证脚本执行失败，流程暂停。"
        echo "请人工检查分支 $BRANCH_NAME"
        exit 1
    fi
    echo "✅ 验证通过"
fi


# ========================================================
# 🔹 STEP 6: 闭环合并 (Merge & Loop)
# ========================================================
echo ""
echo "========================================="
echo "🔀 [Step 6] 合并闭环 (Merge Loop)"
echo "========================================="

# 切回主分支
git checkout main --quiet

# 合并
echo "正在合并 $BRANCH_NAME -> main ..."
if git merge "$BRANCH_NAME"; then
    echo "✅ 本地合并成功"
    
    # 推送到远程 Main
    # 这一步至关重要：它确保了下一个任务开始时，Codex 能 Pull 到包含当前任务代码的 Main
    git push origin main
    echo "🚀 Main 分支已推送到 GitHub"
    
    # 可选：清理远程分支
    # git push origin --delete "$BRANCH_NAME" --quiet
else
    echo "❌ 合并冲突！请人工解决冲突后提交。"
    exit 1
fi


# ========================================================
# 🟢 STEP 7: 更新任务状态 (Update Plan)
# ========================================================
echo ""
echo "========================================="
echo "📝 [Step 7] 更新 PLAN.md"
echo "========================================="

# 更新 Markdown 复选框 (兼容 macOS/Linux sed)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "${LINE_NUMBER}s/- \[ \]/- [x]/" PLAN.md
else
    sed -i "${LINE_NUMBER}s/- \[ \]/- [x]/" PLAN.md
fi

git add PLAN.md
git commit -m "docs: mark TASK-${TASK_ID} as completed"
git push origin main

echo ""
echo "🎉 任务 TASK-${TASK_ID} 完整闭环结束！"
echo "👉 您可以再次运行脚本以执行下一个任务。"