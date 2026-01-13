#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 参数接收
TASK_ID=$1
PREVIEW_URL=$2
LOG_FILE="./logs/validation.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

# 开始验证
log "========================================="
log "开始验证任务: $TASK_ID"
log "预览地址: $PREVIEW_URL"
log "========================================="

# 阶段 1: 代码静态检查
log "阶段 1: 执行代码静态检查..."

# TypeScript 类型检查
if command -v tsc &> /dev/null; then
    log "执行 TypeScript 类型检查..."
    if npm run type-check > /dev/null 2>&1; then
        log_success "TypeScript 类型检查通过"
    else
        log_error "TypeScript 类型检查失败"
        exit 1
    fi
fi

# ESLint 检查
if npm run lint > /dev/null 2>&1; then
    log_success "ESLint 检查通过"
else
    log_error "ESLint 检查失败"
    exit 1
fi

# 阶段 2: 连通性验证
if [ -n "$PREVIEW_URL" ]; then
    log "阶段 2: 验证云端部署连通性..."
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PREVIEW_URL" --max-time 10)
    
    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 301 ] || [ "$HTTP_CODE" -eq 302 ]; then
        log_success "云端服务可访问 (HTTP $HTTP_CODE)"
    else
        log_error "云端服务不可访问 (HTTP $HTTP_CODE)"
        exit 1
    fi
fi

# 阶段 3: 任务特定验证
log "阶段 3: 执行任务特定验证..."

case $TASK_ID in
    "001")
        # 验证 Next.js 项目初始化
        if [ -f "package.json" ] && [ -f "tsconfig.json" ]; then
            log_success "TASK-001: Next.js 项目结构验证通过"
        else
            log_error "TASK-001: 缺少必要的配置文件"
            exit 1
        fi
        ;;
    
    "002")
        # 验证 Prisma 配置
        if [ -f "prisma/schema.prisma" ]; then
            log_success "TASK-002: Prisma 配置文件存在"
        else
            log_error "TASK-002: 未找到 Prisma 配置"
            exit 1
        fi
        ;;
    
    "007"|"008")
        # 验证认证 API
        if [ -n "$PREVIEW_URL" ]; then
            log "测试认证接口..."
            
            # 测试注册接口
            if [ "$TASK_ID" == "007" ]; then
                RESPONSE=$(curl -s -X POST "$PREVIEW_URL/api/auth/register" \
                    -H "Content-Type: application/json" \
                    -d '{"email":"test@example.com","password":"testpass123"}')
                
                if echo "$RESPONSE" | grep -q "success"; then
                    log_success "注册接口返回正确格式"
                else
                    log_error "注册接口返回格式错误"
                    exit 1
                fi
            fi
            
            # 测试登录接口
            if [ "$TASK_ID" == "008" ]; then
                RESPONSE=$(curl -s -X POST "$PREVIEW_URL/api/auth/login" \
                    -H "Content-Type: application/json" \
                    -d '{"email":"wrong@example.com","password":"wrongpass"}')
                
                if echo "$RESPONSE" | grep -q "error"; then
                    log_success "登录接口错误处理正确"
                else
                    log_error "登录接口错误处理异常"
                    exit 1
                fi
            fi
        fi
        ;;
    
    "010"|"011"|"012"|"013")
        # 验证 Todo API
        if [ -n "$PREVIEW_URL" ]; then
            log "测试 Todo API 接口..."
            
            case $TASK_ID in
                "010")
                    # 测试创建 Todo
                    RESPONSE=$(curl -s -X POST "$PREVIEW_URL/api/todos" \
                        -H "Content-Type: application/json" \
                        -d '{"title":"Test Todo","completed":false}')
                    ;;
                "011")
                    # 测试获取 Todo 列表
                    RESPONSE=$(curl -s "$PREVIEW_URL/api/todos")
                    ;;
            esac
            
            if echo "$RESPONSE" | grep -q -E "success|data"; then
                log_success "Todo API 接口验证通过"
            else
                log_error "Todo API 接口返回异常"
                exit 1
            fi
        fi
        ;;
    
    *)
        log_warning "未定义具体验证逻辑，执行通用检查"
        ;;
esac

# 验证成功
log "========================================="
log_success "任务 $TASK_ID 验证完成！"
log "========================================="

exit 0