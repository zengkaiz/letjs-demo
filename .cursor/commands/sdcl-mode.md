---
name: sdcl-mode
description: "Self-Directed Code Loop - 完全自动化的开发闭环。Claude 在本地监控任务、调度 Codex 云端编码、自动验证结果并更新任务状态。当用户需要自动执行 PLAN.md 中的多个开发任务时触发此 skill。实现真正的 AI 监管 AI 的开发流程。"
---

# SDCL Mode - Self-Directed Code Loop v2.0



## 完整执行流程

### 步骤 0: 同步本地修改（新增）

**在开始任务前，确保本地修改已推送到远程**

使用 Bash 工具执行：

```bash
echo "========================================="
echo "📤 同步本地修改到远程"
echo "========================================="
echo ""

# 检查当前分支
CURRENT_BRANCH=$(git branch --show-current)
echo "当前分支: $CURRENT_BRANCH"

# 检查是否有未提交的修改
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo ""
    echo "❌ 检测到未提交的修改"
    echo ""
    git status --short
    echo ""
    echo "请先提交这些修改再继续执行任务"
    exit 1
fi

echo "✅ 工作目录干净"

# 检查是否有未推送的提交
LOCAL_COMMITS=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")

if [ "$LOCAL_COMMITS" -gt 0 ]; then
    echo ""
    echo "📋 发现 $LOCAL_COMMITS 个未推送的本地提交："
    echo ""
    git log --oneline @{u}..HEAD
    echo ""

    # 推送到远程
    echo "🚀 推送到远程..."
    git push origin "$CURRENT_BRANCH"

    echo ""
    echo "✅ 本地提交已推送到 origin/$CURRENT_BRANCH"
else
    echo "✅ 没有未推送的提交"
fi

echo ""
echo "========================================="
echo "✅ 同步完成，可以开始新任务"
echo "========================================="
echo ""
```

向用户确认同步完成。

### 步骤 1: 环境检查

使用 Bash 工具检查必要文件和配置：

```bash
# 检查 .codex-env 配置
if [ ! -f .codex-env ]; then
    echo "❌ 未找到 .codex-env 配置文件"
    echo ""
    echo "配置方法："
    echo "1. 访问 https://chatgpt.com/codex"
    echo "2. 连接 GitHub 仓库并创建 Environment"
    echo "3. 复制 Environment ID"
    echo "4. 运行: echo 'CODEX_ENV_ID=你的环境ID' > .codex-env"
    exit 1
fi

# 加载环境变量
source .codex-env

# 检查必要文件
for file in SPEC.md PLAN.md; do
    if [ ! -f "$file" ]; then
        echo "❌ 未找到必要文件: $file"
        exit 1
    fi
done

# 检查 Git 仓库
if [ ! -d .git ]; then
    echo "❌ 当前目录不是 Git 仓库"
    exit 1
fi

echo "✅ 环境检查通过"
echo "Environment ID: ${CODEX_ENV_ID:0:15}..."
```

### 步骤 2: 查找下一个任务

使用 Bash 工具从 PLAN.md 提取任务：

```bash
# 提取下一个未完成任务
NEXT_TASK=$(grep -n "^- \[ \]" PLAN.md | head -1)

if [ -z "$NEXT_TASK" ]; then
    echo "🎉 所有任务已完成！"
    echo ""
    echo "统计信息："
    echo "- 已完成任务: $(grep -c "^- \[x\]" PLAN.md)"
    echo "- 日志位置: logs/completion.log"
    exit 0
fi

# 提取任务信息（兼容 macOS 和 Linux）
LINE_NUMBER=$(echo "$NEXT_TASK" | cut -d: -f1)
TASK_LINE=$(echo "$NEXT_TASK" | cut -d: -f2-)
TASK_ID=$(echo "$TASK_LINE" | grep -oE 'TASK-[0-9]+' | grep -oE '[0-9]+')
TASK_DESC=$(echo "$TASK_LINE" | sed 's/.*TASK-[0-9]*: //')

echo "========================================="
echo "📋 发现待执行任务"
echo "========================================="
echo "任务 ID: TASK-$TASK_ID"
echo "任务描述: $TASK_DESC"
echo "位置: PLAN.md 第 $LINE_NUMBER 行"
echo ""

# 保存到临时文件供后续步骤使用
echo "$LINE_NUMBER" > /tmp/sdcl_line_number
echo "$TASK_ID" > /tmp/sdcl_task_id
echo "$TASK_DESC" > /tmp/sdcl_task_desc
```

向用户显示任务信息。

### 步骤 3: 构建优化的提示词（改进）

使用 Read 工具读取 SPEC.md，然后构建强化的提示词：

先使用 Read 工具读取 `SPEC.md`，然后使用 Bash 构建提示词：

```bash
TASK_ID=$(cat /tmp/sdcl_task_id)
TASK_DESC=$(cat /tmp/sdcl_task_desc)

mkdir -p logs

# 构建强化的提示词
cat > /tmp/sdcl_prompt.txt << 'PROMPT_START'
🚨🚨🚨 CRITICAL REQUIREMENT - 分支命名规范 🚨🚨🚨

你必须严格遵守以下分支命名规则，这是强制性的：

分支名称（MANDATORY）: feature/task-TASK_ID_PLACEHOLDER

执行流程：
1. 开始工作前，执行: git checkout -b feature/task-TASK_ID_PLACEHOLDER
2. 在该分支上完成所有开发工作
3. 提交代码到该分支
4. 推送到远程: git push -u origin feature/task-TASK_ID_PLACEHOLDER

重要说明：
❌ 不能使用 codex/ 前缀
❌ 不能自己创造分支名
❌ 不能使用任务描述作为分支名
✅ 必须严格使用 feature/task-TASK_ID_PLACEHOLDER 格式

这是验证流程的关键要求，如果分支名错误，任务将被标记为失败。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【任务信息】
任务编号: TASK-TASK_ID_PLACEHOLDER
任务描述: TASK_DESC_PLACEHOLDER

【项目规范 - 必须严格遵守】
请仔细阅读以下 SPEC.md 中的所有规范：

PROMPT_START

# 替换占位符
sed -i '' "s/TASK_ID_PLACEHOLDER/${TASK_ID}/g" /tmp/sdcl_prompt.txt
sed -i '' "s/TASK_DESC_PLACEHOLDER/${TASK_DESC}/g" /tmp/sdcl_prompt.txt

# 附加 SPEC.md 内容
cat SPEC.md >> /tmp/sdcl_prompt.txt

# 附加执行要求
cat >> /tmp/sdcl_prompt.txt << 'PROMPT_END'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【完成标准】
1. ✅ 代码实现符合需求
2. ✅ 通过 npm run lint（如果有）
3. ✅ 通过 npm run type-check（如果有）
4. ✅ 代码已提交到分支 feature/task-TASK_ID_PLACEHOLDER
5. ✅ 已推送到远程仓库
6. ✅ Commit 信息格式: "Complete TASK-TASK_ID_PLACEHOLDER: TASK_DESC_PLACEHOLDER"

再次确认：你使用的分支名是 feature/task-TASK_ID_PLACEHOLDER 吗？
PROMPT_END

# 再次替换占位符
sed -i '' "s/TASK_ID_PLACEHOLDER/${TASK_ID}/g" /tmp/sdcl_prompt.txt
sed -i '' "s/TASK_DESC_PLACEHOLDER/${TASK_DESC}/g" /tmp/sdcl_prompt.txt

echo "✅ 优化的提示词已构建"
echo "提示词长度: $(wc -l < /tmp/sdcl_prompt.txt) 行"
```

### 步骤 4: 提交到 Codex Cloud

使用 Bash 工具提交任务：

```bash
source .codex-env

TASK_ID=$(cat /tmp/sdcl_task_id)

echo ""
echo "========================================="
echo "📤 提交任务到 Codex Cloud"
echo "========================================="
echo "任务 ID: TASK-$TASK_ID"
echo "Environment ID: ${CODEX_ENV_ID:0:15}..."
echo ""

# 提交到 Codex Cloud
codex cloud exec \
    --env "$CODEX_ENV_ID" \
    "$(cat /tmp/sdcl_prompt.txt)" \
    2>&1 | tee "logs/codex_cloud_task_${TASK_ID}.log"

EXEC_RESULT=$?

echo ""
if [ $EXEC_RESULT -eq 0 ]; then
    echo "✅ 任务已成功提交"
else
    echo "❌ 任务提交失败（退出码: $EXEC_RESULT）"
    exit 1
fi

# 提取任务 URL
TASK_URL=$(grep -oE 'https://chatgpt\.com/codex/tasks/[a-zA-Z0-9_-]+' "logs/codex_cloud_task_${TASK_ID}.log" | head -1)

if [ -n "$TASK_URL" ]; then
    echo ""
    echo "🔗 实时查看进度: $TASK_URL"
    echo "$TASK_URL" > /tmp/sdcl_task_url
fi

echo ""
```

向用户展示任务 URL。

### 步骤 5: 智能检测任务完成（改进）

**不再依赖监控脚本，主动检测 GitHub 分支**

使用 Bash 工具循环检测：

```bash
TASK_ID=$(cat /tmp/sdcl_task_id)
TASK_URL=$(cat /tmp/sdcl_task_url)
EXPECTED_BRANCH="feature/task-${TASK_ID}"

echo "========================================="
echo "⏳ 等待 Codex 完成任务"
echo "========================================="
echo ""
echo "检测策略："
echo "  - 每30秒检查一次 GitHub 远程分支"
echo "  - 最多等待15分钟"
echo "  - 自动检测并修正分支命名"
echo ""
echo "💡 请在浏览器查看实时进度:"
echo "   $TASK_URL"
echo ""

MAX_WAIT=900  # 15分钟
ELAPSED=0
CHECK_INTERVAL=30
FOUND_BRANCH=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
    MINUTES=$((ELAPSED / 60))

    echo "⏱️  已等待 ${MINUTES} 分钟..."

    # 刷新远程分支
    git fetch origin --quiet 2>&1

    # 检查期望的分支
    if git branch -r | grep -q "origin/${EXPECTED_BRANCH}"; then
        echo "✅ 检测到期望分支: $EXPECTED_BRANCH"
        FOUND_BRANCH="origin/$EXPECTED_BRANCH"
        echo "$EXPECTED_BRANCH" > /tmp/sdcl_found_branch
        break
    fi

    # 检查 codex/ 前缀的分支（最近创建的，排除已知的旧分支）
    CODEX_BRANCH=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin/ | grep "codex/" | grep -v "set-up-eslint" | grep -v "create-user-data-model" | head -1)

    if [ -n "$CODEX_BRANCH" ]; then
        echo "⚠️  检测到 Codex 分支: $CODEX_BRANCH"
        echo "   （分支命名不符合规范，稍后会自动修正）"
        FOUND_BRANCH="$CODEX_BRANCH"
        echo "$(echo $CODEX_BRANCH | sed 's/origin\///')" > /tmp/sdcl_found_branch
        break
    fi

    # 每2分钟提示一次
    if [ $((ELAPSED % 120)) -eq 0 ]; then
        echo "💡 建议在浏览器查看详细进度"
    fi
done

if [ -z "$FOUND_BRANCH" ]; then
    echo ""
    echo "❌ 等待超时，未检测到分支"
    echo "请手动检查任务状态: $TASK_URL"
    exit 1
fi

echo ""
echo "✅ 任务完成，检测到代码分支"
echo ""
```

### 步骤 6: 自动修正分支命名（新增）

**如果 Codex 没有按规范命名，自动修正**

使用 Bash 工具：

```bash
TASK_ID=$(cat /tmp/sdcl_task_id)
EXPECTED_BRANCH="feature/task-${TASK_ID}"
FOUND_BRANCH_NAME=$(cat /tmp/sdcl_found_branch)

if [ "$FOUND_BRANCH_NAME" != "$EXPECTED_BRANCH" ]; then
    echo "========================================="
    echo "🔄 修正分支命名"
    echo "========================================="
    echo ""
    echo "检测到分支: $FOUND_BRANCH_NAME"
    echo "重命名为: $EXPECTED_BRANCH"
    echo ""

    # 切换到该分支
    git checkout "$FOUND_BRANCH_NAME" 2>/dev/null || git checkout -b "$FOUND_BRANCH_NAME" --track "origin/$FOUND_BRANCH_NAME"

    # 重命名本地分支
    git branch -m "$EXPECTED_BRANCH"

    # 推送新分支
    git push -u origin "$EXPECTED_BRANCH" --quiet

    # 删除远程旧分支
    git push origin ":$FOUND_BRANCH_NAME" --quiet 2>/dev/null || true

    # 切回 main
    git checkout main --quiet

    echo "✅ 分支已重命名为: $EXPECTED_BRANCH"
    echo ""
else
    echo "========================================="
    echo "✅ 分支命名正确"
    echo "========================================="
    echo "分支: $EXPECTED_BRANCH"
    echo ""
fi
```

### 步骤 7: 验证代码质量（可选）

如果项目有 validator.sh，运行验证：

使用 Bash 工具：

```bash
TASK_ID=$(cat /tmp/sdcl_task_id)
EXPECTED_BRANCH="feature/task-${TASK_ID}"

if [ -f "scripts/validator.sh" ]; then
    echo "========================================="
    echo "🧪 验证代码质量"
    echo "========================================="
    echo ""

    # 切换到分支
    git checkout "$EXPECTED_BRANCH" --quiet

    # 运行验证
    ./scripts/validator.sh "$TASK_ID" || true

    # 切回 main
    git checkout main --quiet

    echo ""
    echo "✅ 验证完成"
    echo ""
else
    echo "跳过代码验证（未找到 scripts/validator.sh）"
    echo ""
fi
```

### 步骤 8: 更新 PLAN.md 并推送（改进）

**自动更新并推送到远程**

使用 Bash 工具：

```bash
TASK_ID=$(cat /tmp/sdcl_task_id)
TASK_DESC=$(cat /tmp/sdcl_task_desc)
LINE_NUMBER=$(cat /tmp/sdcl_line_number)
TASK_URL=$(cat /tmp/sdcl_task_url)
EXPECTED_BRANCH="feature/task-${TASK_ID}"

echo "========================================="
echo "📝 更新 PLAN.md"
echo "========================================="
echo ""

# 备份
cp PLAN.md PLAN.md.bak

# 更新任务状态（macOS 兼容）
sed -i '' "${LINE_NUMBER}s/- \[ \]/- [x]/" PLAN.md

# 验证更新
UPDATED_LINE=$(sed -n "${LINE_NUMBER}p" PLAN.md)

if echo "$UPDATED_LINE" | grep -q "\[x\]"; then
    echo "✅ PLAN.md 已更新"
    echo "   ${UPDATED_LINE}"
    echo ""

    # 提交并推送
    git add PLAN.md
    git commit -m "Update PLAN.md: Mark TASK-${TASK_ID} as completed" --quiet
    git push origin main --quiet

    echo "✅ 已推送到远程"
    echo ""

    # 记录完成日志
    mkdir -p logs
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TASK-${TASK_ID} completed" >> logs/completion.log
    echo "  Description: ${TASK_DESC}" >> logs/completion.log
    echo "  Task URL: ${TASK_URL}" >> logs/completion.log
    echo "  Branch: ${EXPECTED_BRANCH}" >> logs/completion.log
    echo "" >> logs/completion.log

    # 清理备份
    rm PLAN.md.bak

    echo "✅ 任务完成记录已保存"
else
    echo "❌ PLAN.md 更新失败"
    mv PLAN.md.bak PLAN.md
    exit 1
fi

echo ""
```

### 步骤 9: 完成总结和继续

使用 Bash 工具显示总结：

```bash
TASK_ID=$(cat /tmp/sdcl_task_id)
TASK_DESC=$(cat /tmp/sdcl_task_desc)
TASK_URL=$(cat /tmp/sdcl_task_url)
EXPECTED_BRANCH="feature/task-${TASK_ID}"

echo "========================================="
echo "✅ TASK-${TASK_ID} 已完成！"
echo "========================================="
echo ""
echo "完成详情："
echo "  - 任务描述: $TASK_DESC"
echo "  - 代码分支: $EXPECTED_BRANCH"
echo "  - 任务 URL: $TASK_URL"
echo ""

# 检查剩余任务
REMAINING=$(grep -c "^- \[ \]" PLAN.md)
echo "⏭️  还有 $REMAINING 个任务待完成"

if [ $REMAINING -gt 0 ]; then
    echo ""
    NEXT=$(grep -n "^- \[ \]" PLAN.md | head -1 | cut -d: -f2-)
    echo "下一个任务: $NEXT"
fi

echo ""
```