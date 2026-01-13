#!/bin/bash
set -e # 遇到错误立即停止

# ========================================================
# 🟢 全局前置检查
# ========================================================
if [ ! -f .codex-env ]; then
    echo "❌ 错误: 找不到 .codex-env 配置文件"
    exit 1
fi
source .codex-env

echo "========================================="
echo "🚀 启动 SDCL 全自动循环模式"
echo "========================================="
echo "按 Ctrl+C 可随时中止流程"
echo ""

# ========================================================
# 🔄 主循环 (Main Loop)
# ========================================================
while true; do

    # --- Step 0: 确保环境同步 (每次循环开始都检查) ---
    # 确保本地 Main 是最新的，且工作区干净
    git checkout main --quiet
    git pull origin main --quiet

    if ! git diff-index --quiet HEAD --; then
        echo "❌ 错误: 本地有未提交的修改。请先 Commit 或 Stash。"
        exit 1
    fi

    # --- Step 1: 扫描 PLAN.md ---
    echo "📋 正在扫描待办任务..."
    
    # 查找第一个未完成的任务
    NEXT_TASK=$(grep -n "^- \[ \]" PLAN.md | head -1)

    if [ -z "$NEXT_TASK" ]; then
        echo ""
        echo "🎉🎉🎉 所有任务已全部完成！PLAN.md 清零。"
        echo "程序退出。"
        break
    fi

    # 解析任务数据
    LINE_NUMBER=$(echo "$NEXT_TASK" | cut -d: -f1)
    TASK_LINE=$(echo "$NEXT_TASK" | cut -d: -f2-)
    TASK_ID=$(echo "$TASK_LINE" | grep -oE 'TASK-[0-9]+' | grep -oE '[0-9]+')
    TASK_DESC=$(echo "$TASK_LINE" | sed 's/.*TASK-[0-9]*: //')

    echo "-----------------------------------------"
    echo "▶️  开始执行: TASK-$TASK_ID"
    echo "📝 描述: $TASK_DESC"
    echo "-----------------------------------------"


    # --- Step 2: 发送指令 (Dispatch) ---
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

    # 附加 SPEC.md
    if [ -f SPEC.md ]; then
        echo "" >> /tmp/sdcl_prompt.txt
        echo "【项目规范】" >> /tmp/sdcl_prompt.txt
        cat SPEC.md >> /tmp/sdcl_prompt.txt
    fi

    echo "📡 [TASK-$TASK_ID] 发送指令给 Codex..."
    # 假设使用 codex cli
    codex cloud exec --env "$CODEX_ENV_ID" "$(cat /tmp/sdcl_prompt.txt)" > /tmp/codex_exec.log 2>&1 &
    PID=$!
    wait $PID


    # --- Step 3: 监控远程 (Monitor) ---
    echo "📡 [TASK-$TASK_ID] 等待远程推送..."
    MAX_WAIT=900 # 15分钟超时
    ELAPSED=0
    CHECK_INTERVAL=15
    FOUND=0

    while [ $ELAPSED -lt $MAX_WAIT ]; do
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        
        printf "\r⏳ 已等待 %3d秒..." $ELAPSED
        
        git fetch origin --quiet
        if git rev-parse --verify "origin/$BRANCH_NAME" > /dev/null 2>&1; then
            echo ""
            echo "✅ 捕获到远程分支！"
            FOUND=1
            break
        fi
    done

    if [ $FOUND -eq 0 ]; then
        echo ""
        echo "❌ [TASK-$TASK_ID] 超时失败：未检测到远程分支。"
        exit 1
    fi


    # --- Step 4: 拉取代码 (Pull) ---
    echo "📥 [TASK-$TASK_ID] 同步代码到本地"
    if git rev-parse --verify "$BRANCH_NAME" > /dev/null 2>&1; then
        git checkout "$BRANCH_NAME" --quiet
        git pull origin "$BRANCH_NAME" --quiet
    else
        git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME" --quiet
    fi


    # --- Step 5: 验证 (Validate) ---
    if [ -f "scripts/validator.sh" ]; then
        echo "🧪 [TASK-$TASK_ID] 执行验证..."
        if ! ./scripts/validator.sh; then
            echo "❌ 验证失败，脚本暂停。"
            echo "请手动修复 TASK-$TASK_ID 对应分支后重新运行。"
            exit 1
        fi
        echo "✅ 验证通过"
    fi


    # --- Step 6: 合并闭环 (Merge) ---
    echo "🔀 [TASK-$TASK_ID] 合并代码"
    git checkout main --quiet
    
    if git merge "$BRANCH_NAME" --quiet; then
        git push origin main --quiet
        echo "✅ 代码已合并并推送到 Main"
        # 可选：删除本地和远程功能分支以保持清洁
        # git branch -D "$BRANCH_NAME"
        # git push origin --delete "$BRANCH_NAME"
    else
        echo "❌ 合并冲突！请人工介入。"
        exit 1
    fi


    # --- Step 7: 更新 PLAN.md (Check off) ---
    # 更新 Markdown 复选框
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "${LINE_NUMBER}s/- \[ \]/- [x]/" PLAN.md
    else
        sed -i "${LINE_NUMBER}s/- \[ \]/- [x]/" PLAN.md
    fi

    git add PLAN.md
    git commit -m "docs: mark TASK-${TASK_ID} as completed" --quiet
    git push origin main --quiet

    echo "🎉 [TASK-$TASK_ID] 完成！"
    echo ""
    echo "⏳ 休息 5 秒后开始寻找下一个任务..."
    sleep 5
    echo ""

done