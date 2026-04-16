#!/usr/bin/env bash
set -euo pipefail

# ============================================
# organize - 文件自动整理工具
# 版本: @@VERSION@@
# ============================================

readonly SCRIPT_NAME="organize"
readonly VERSION="${VERSION:-2.0.5}"

# 配置文件路径（遵循 XDG 规范）
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
readonly CONFIG_DIR="$XDG_CONFIG_HOME/$SCRIPT_NAME"
readonly RULES_FILE="$CONFIG_DIR/rules.conf"
readonly LOG_DIR="$XDG_STATE_HOME/$SCRIPT_NAME"
readonly LOG_FILE="$LOG_DIR/organize.log"
readonly DEFAULT_RULES_SYSTEM="/usr/share/$SCRIPT_NAME/rules.conf.default"

# 颜色定义（输出到终端时启用）
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
else
    readonly RED=''; GREEN=''; YELLOW=''; BLUE=''; PURPLE=''; CYAN=''; NC=''
fi

# 全局选项
DRY_RUN=false
CLEAN_TEMP=false
VERBOSE=false
TARGET_DIR="$HOME"

# ============================================
# 辅助函数
# ============================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

log_to_file() {
    local msg="$1"
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# ============================================
# 初始化配置
# ============================================

init_config() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"

    # 如果用户规则文件不存在，尝试从系统默认复制
    if [[ ! -f "$RULES_FILE" ]]; then
        if [[ -f "$DEFAULT_RULES_SYSTEM" ]]; then
            cp "$DEFAULT_RULES_SYSTEM" "$RULES_FILE"
            log_info "已创建默认规则文件: $RULES_FILE"
        else
            log_warn "未找到系统默认规则文件，请手动创建: $RULES_FILE"
        fi
    fi
}

# ============================================
# 规则管理（基于数组）
# ============================================

declare -A RULES

load_rules() {
    RULES=()
    if [[ ! -f "$RULES_FILE" ]]; then
        return
    fi

    while IFS=: read -r extensions dest; do
        # 跳过注释和空行
        [[ "$extensions" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$extensions" ]] && continue

        # 去除首尾空格
        extensions=$(echo "$extensions" | xargs)
        dest=$(echo "$dest" | xargs)
        [[ -z "$extensions" || -z "$dest" ]] && continue

        # 支持多个扩展名用逗号分隔
        IFS=',' read -ra ext_array <<< "$extensions"
        for ext in "${ext_array[@]}"; do
            ext=$(echo "$ext" | xargs)
            if [[ -n "$ext" ]]; then
                RULES["$ext"]="$HOME/$dest"
            fi
        done
    done < "$RULES_FILE"
}

show_rules() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}当前文件整理规则:${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

    if [[ ! -f "$RULES_FILE" ]]; then
        echo -e "${YELLOW}未找到规则文件，请运行 'organize --init' 创建默认规则${NC}"
        return
    fi

    local current_category=""
    while IFS=: read -r extensions dest; do
        [[ "$extensions" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$extensions" ]] && continue
        dest=$(echo "$dest" | xargs)
        category=$(echo "$dest" | cut -d'/' -f1)
        if [[ "$category" != "$current_category" ]]; then
            echo -e "\n${YELLOW}[$category]${NC}"
            current_category="$category"
        fi
        echo "  $extensions → $dest"
    done < "$RULES_FILE"

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

add_rule() {
    local extensions="$1"
    local dest_dir="$2"

    if [[ -z "$extensions" || -z "$dest_dir" ]]; then
        log_error "请提供扩展名和目标目录"
        echo "用法: organize --add <扩展名> <目标目录>"
        echo "示例: organize --add iso 下载/镜像"
        return 1
    fi

    # 检查是否已存在
    if grep -q "^$extensions:" "$RULES_FILE" 2>/dev/null; then
        log_warn "规则 '$extensions' 已存在"
        read -p "是否覆盖? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        sed -i "/^$extensions:/d" "$RULES_FILE"
    fi

    echo "$extensions:$dest_dir" >> "$RULES_FILE"
    log_info "已添加规则: $extensions → $dest_dir"

    # 可选：创建目录
    local full_path="$HOME/$dest_dir"
    if [[ ! -d "$full_path" ]]; then
        read -p "是否创建目录 '$full_path'? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            mkdir -p "$full_path"
            log_info "已创建目录: $full_path"
        fi
    fi
}

remove_rule() {
    local extensions="$1"
    if [[ -z "$extensions" ]]; then
        log_error "请提供要删除的扩展名"
        echo "用法: organize --remove <扩展名>"
        return 1
    fi

    if grep -q "^$extensions:" "$RULES_FILE" 2>/dev/null; then
        sed -i "/^$extensions:/d" "$RULES_FILE"
        log_info "已删除规则: $extensions"
    else
        log_error "未找到规则: $extensions"
        return 1
    fi
}

# ============================================
# 清理临时文件
# ============================================

clean_temp() {
    local target_dir="$1"
    log_info "清理临时文件: $target_dir"

    # 清理 temp 目录内容
    if [[ -d "$target_dir/temp" ]]; then
        local count=$(find "$target_dir/temp" -type f 2>/dev/null | wc -l)
        if [[ $count -gt 0 ]]; then
            log_debug "发现 $count 个临时文件"
            if [[ "$DRY_RUN" == false ]]; then
                rm -rf "$target_dir/temp"/*
                log_info "已清空 temp 目录"
            else
                log_info "[模拟] 将清空 temp 目录"
            fi
        fi
    fi

    # 清理常见临时文件模式
    local patterns=("temp.*" "*.tmp" "*.temp" "*.cache" "~*" "*~")
    for pattern in "${patterns[@]}"; do
        local files=()
        while IFS= read -r f; do
            files+=("$f")
        done < <(find "$target_dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null)
        if [[ ${#files[@]} -gt 0 ]]; then
            log_debug "发现 ${#files[@]} 个匹配 '$pattern' 的文件"
            if [[ "$DRY_RUN" == false ]]; then
                rm -f "${files[@]}"
                log_info "已删除匹配 '$pattern' 的文件"
            else
                log_info "[模拟] 将删除匹配 '$pattern' 的文件"
                for f in "${files[@]}"; do
                    echo "  - $(basename "$f")"
                done
            fi
        fi
    done
}

# ============================================
# 核心整理逻辑
# ============================================

organize_directory() {
    local target_dir="$1"
    target_dir=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")

    if [[ ! -d "$target_dir" ]]; then
        log_error "目录不存在: $target_dir"
        return 1
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}📂 整理目录: $target_dir${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}⚠️  模拟运行模式 - 不会实际移动文件${NC}\n"
    fi

    # 收集所有需要创建的目标目录
    declare -A dirs_to_create
    for dest_dir in "${RULES[@]}"; do
        if [[ ! -d "$dest_dir" ]]; then
            dirs_to_create["$dest_dir"]=1
        fi
    done

    if [[ ${#dirs_to_create[@]} -gt 0 ]]; then
        log_info "创建必要目录..."
        for dir in "${!dirs_to_create[@]}"; do
            if [[ "$DRY_RUN" == false ]]; then
                mkdir -p "$dir"
                echo -e "  ${GREEN}✓${NC} $dir"
            else
                echo -e "  ${CYAN}[模拟]${NC} 将创建: $dir"
            fi
        done
        echo
    fi

    # 移动文件
    local moved_count=0 skipped_count=0 unknown_count=0
    local total_size=0

    # 使用 find 获取文件列表（不递归子目录）
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$target_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    if [[ ${#files[@]} -eq 0 ]]; then
        log_info "没有需要整理的文件"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        return 0
    fi

    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        # 跳过隐藏文件（可选，如果需要整理隐藏文件，注释下面两行）
        [[ "$filename" == .* ]] && continue

        local ext="${filename##*.}"
        if [[ "$filename" == "$ext" ]]; then
            ext=""  # 无扩展名
        else
            ext="${ext,,}"
        fi

        local dest_dir="${RULES[$ext]}"
        if [[ -n "$dest_dir" ]]; then
            local file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
            total_size=$((total_size + file_size))

            local dest_file="$dest_dir/$filename"
            if [[ -f "$dest_file" ]]; then
                echo -e "  ${YELLOW}⚠${NC} 跳过: $filename (目标已存在)"
                ((skipped_count++))
                continue
            fi

            echo -e "  ${GREEN}→${NC} $filename (.$ext → ${BLUE}$dest_dir${NC})"
            if [[ "$DRY_RUN" == false ]]; then
                mv "$file" "$dest_dir/" && {
                    ((moved_count++))
                    log_to_file "MOVED: $filename -> $dest_dir"
                } || {
                    log_error "移动失败: $filename"
                }
            else
                ((moved_count++))
            fi
        else
            echo -e "  ${PURPLE}?${NC} $filename (未知类型: ${ext:-无扩展名})"
            ((unknown_count++))
        fi
    done

    # 清理临时文件
    if [[ "$CLEAN_TEMP" == true ]]; then
        clean_temp "$target_dir"
    fi

    # 统计输出
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}📊 整理完成:${NC}"
    echo -e "  ${GREEN}✓${NC} 已移动: $moved_count 个文件"
    [[ $skipped_count -gt 0 ]] && echo -e "  ${YELLOW}⚠${NC}  已跳过: $skipped_count 个文件"
    [[ $unknown_count -gt 0 ]] && echo -e "  ${PURPLE}?${NC}  未知类型: $unknown_count 个文件"

    if [[ $moved_count -gt 0 && "$DRY_RUN" == false ]]; then
        local total_mb=$((total_size / 1048576))
        [[ $total_mb -gt 0 ]] && echo -e "  💾 总大小: ~${total_mb} MB"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

    if [[ $unknown_count -gt 0 ]]; then
        echo -e "\n${YELLOW}💡 提示: 可以使用以下命令添加规则:${NC}"
        echo -e "   organize --add <扩展名> <目标目录>"
        echo -e "   示例: organize --add iso 下载/镜像"
    fi
}

# ============================================
# 帮助和版本
# ============================================

show_help() {
    cat <<EOF
${GREEN}organize - 文件自动整理工具 v$VERSION${NC}
根据扩展名规则自动整理指定目录中的文件。

${YELLOW}用法:${NC}
  organize [选项] [目录]

${YELLOW}选项:${NC}
  -d, --dir DIR         指定要整理的目录 (默认: ~)
  --dry-run             模拟运行，不实际移动文件
  --clean-temp          同时清理临时文件 (temp目录和常见临时文件)
  -v, --verbose         显示详细信息
  --init                创建默认规则文件（如果不存在）

${YELLOW}规则管理:${NC}
  --show-rules          显示当前所有规则
  --add EXT DIR         添加新规则 (EXT:扩展名, DIR:目标目录)
  --remove EXT          删除规则
  --edit-rules          用默认编辑器打开规则文件

${YELLOW}其他:${NC}
  -h, --help            显示此帮助
  --version             显示版本信息

${YELLOW}示例:${NC}
  organize                              # 整理主目录
  organize -d ~/下载                    # 整理下载目录
  organize --dry-run --clean-temp       # 模拟运行并显示临时文件清理
  organize --show-rules                 # 查看当前规则
  organize --add iso 下载/镜像          # 添加 .iso 规则
  organize --remove iso                 # 删除 .iso 规则

EOF
}

show_version() {
    echo "organize version $VERSION"
    echo "配置文件: $RULES_FILE"
    echo "日志文件: $LOG_FILE"
}

edit_rules() {
    if [[ ! -f "$RULES_FILE" ]]; then
        log_error "规则文件不存在，请先运行 'organize --init' 创建默认规则"
        return 1
    fi
    local editor="${EDITOR:-vi}"
    $editor "$RULES_FILE"
    log_info "规则已更新，请重新运行 organize 以生效"
}

# ============================================
# 主入口
# ============================================

main() {
    # 先初始化配置目录（但不一定创建规则文件）
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --clean-temp)
                CLEAN_TEMP=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --init)
                init_config
                if [[ ! -f "$RULES_FILE" ]] && [[ -f "$DEFAULT_RULES_SYSTEM" ]]; then
                    cp "$DEFAULT_RULES_SYSTEM" "$RULES_FILE"
                    log_info "已创建默认规则文件: $RULES_FILE"
                elif [[ ! -f "$RULES_FILE" ]]; then
                    log_error "系统默认规则文件不存在，请手动创建规则文件: $RULES_FILE"
                else
                    log_info "规则文件已存在: $RULES_FILE"
                fi
                exit 0
                ;;
            --show-rules)
                load_rules
                show_rules
                exit 0
                ;;
            --add)
                add_rule "$2" "$3"
                exit 0
                ;;
            --remove)
                remove_rule "$2"
                exit 0
                ;;
            --edit-rules)
                edit_rules
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                # 位置参数作为目标目录
                TARGET_DIR="$1"
                shift
                ;;
        esac
    done

    # 初始化用户配置（如果规则文件不存在则创建）
    init_config

    # 加载规则
    load_rules

    # 执行整理
    organize_directory "$TARGET_DIR"
}

# 捕获 Ctrl+C
trap 'echo -e "\n${YELLOW}中断整理${NC}"; exit 130' INT

main "$@"
