#!/bin/bash

# SymbolFinder Installation Script
# 自动安装 SymbolFinder 及其所有依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 显示欢迎信息
show_welcome() {
    echo -e "${BLUE}"
    echo "🔍 SymbolFinder 安装程序"
    echo "========================"
    echo -e "${NC}"
    echo "📋 SymbolFinder 是一个高性能的 Rails 项目符号搜索工具"
    echo "⚡ 特性：毫秒级搜索、实时监控、编辑器集成"
    echo ""
}

# 检查 Ruby 环境
check_ruby() {
    print_info "检查 Ruby 环境..."

    if ! command -v ruby &> /dev/null; then
        print_error "Ruby 未安装！请先安装 Ruby 2.5 或更高版本"
        echo "📖 安装指南：https://www.ruby-lang.org/en/downloads/"
        exit 1
    fi

    ruby_version=$(ruby -e 'puts RUBY_VERSION')
    print_success "Ruby 版本: $ruby_version"

    # 检查版本是否 >= 2.5
    if ! ruby -e 'exit(RUBY_VERSION >= "2.5.0")'; then
        print_error "Ruby 版本过低！需要 2.5 或更高版本，当前版本: $ruby_version"
        exit 1
    fi
}

# 检查 gem 命令
check_gem() {
    print_info "检查 RubyGems..."

    if ! command -v gem &> /dev/null; then
        print_error "gem 命令未找到！请检查 Ruby 安装"
        exit 1
    fi

    gem_version=$(gem -v)
    print_success "RubyGems 版本: $gem_version"
}

# 安装系统依赖（如果需要）
install_system_deps() {
    print_info "检查系统依赖..."

    # 检查是否存在编译工具
    case "$(uname -s)" in
        Linux*)
            if command -v apt-get &> /dev/null; then
                print_info "Debian/Ubuntu 系统，检查编译工具..."
                sudo apt-get update -qq
                sudo apt-get install -y build-essential ruby-dev
            elif command -v yum &> /dev/null; then
                print_info "RedHat/CentOS 系统，检查编译工具..."
                sudo yum install -y gcc ruby-devel make
            elif command -v dnf &> /dev/null; then
                print_info "Fedora 系统，检查编译工具..."
                sudo dnf install -y gcc ruby-devel make
            fi
            ;;
        Darwin*)
            print_info "macOS 系统，检查 Xcode 工具..."
            if ! command -v xcode-select &> /dev/null; then
                print_warning "需要安装 Xcode 命令行工具"
                xcode-select --install || print_warning "请手动安装 Xcode 命令行工具"
            fi
            ;;
    esac
}

# 安装 gem 依赖
install_gem_deps() {
    print_info "安装 gem 依赖..."

    # 安装基础依赖
    gems=("parser" "listen" "concurrent-ruby")

    for gem in "${gems[@]}"; do
        print_info "安装 $gem..."

        # 检查是否已安装
        if gem list "$gem" -i &> /dev/null; then
            print_success "$gem 已安装"
        else
            print_info "正在安装 $gem..."
            if gem install "$gem"; then
                print_success "$gem 安装成功"
            else
                print_error "$gem 安装失败"
                exit 1
            fi
        fi
    done
}

# 安装 SymbolFinder gem
install_symbol_finder() {
    print_info "安装 SymbolFinder gem..."

    # 从本地安装如果存在 gem 文件
    if [ -f "symbol_finder-*.gem" ]; then
        gem_file=$(ls symbol_finder-*.gem | head -n 1)
        print_info "从本地安装: $gem_file"

        if gem install --local "$gem_file"; then
            print_success "SymbolFinder 安装成功"
        else
            print_error "本地安装失败，尝试从远程安装"
            install_from_remote
        fi
    else
        install_from_remote
    fi
}

# 从远程安装
install_from_remote() {
    print_info "从 RubyGems.org 安装 SymbolFinder..."

    if gem install symbol_finder; then
        print_success "SymbolFinder 安装成功"
    else
        print_error "安装失败！请检查网络连接和权限"
        exit 1
    fi
}

# 验证安装
verify_installation() {
    print_info "验证安装..."

    if command -v symbol_finder &> /dev/null; then
        version=$(symbol_finder --version 2>/dev/null || echo "版本信息获取失败")
        print_success "SymbolFinder 安装验证成功"
        print_success "命令行工具可用: symbol_finder"

        # 测试帮助命令
        if symbol_finder --help > /dev/null 2>&1; then
            print_success "命令行界面工作正常"
        else
            print_warning "命令行界面可能有问题"
        fi
    else
        print_error "SymbolFinder 命令未找到！安装可能失败"
        exit 1
    fi
}

# 显示使用说明
show_usage() {
    echo ""
    echo -e "${GREEN}🎉 SymbolFinder 安装完成！${NC}"
    echo ""
    echo -e "${BLUE}🚀 快速开始：${NC}"
    echo "1. 在 Rails 项目中运行: symbol_finder --rebuild"
    echo "2. 搜索符号: symbol_finder \"YourSymbol\""
    echo "3. 查看帮助: symbol_finder --help"
    echo ""
    echo -e "${BLUE}📚 更多信息：${NC}"
    echo "- 完整文档: https://github.com/symbolfinder/symbol_finder"
    echo "- 使用示例: symbol_finder --help"
    echo "- 项目主页: https://rubygems.org/gems/symbol_finder"
    echo ""
    echo -e "${YELLOW}💡 提示：在 Zed 编辑器中集成 SymbolFinder 以获得最佳体验！${NC}"
    echo ""
}

# 错误处理
handle_error() {
    print_error "安装过程中发生错误！"
    echo ""
    echo "🔧 故障排除："
    echo "1. 确保有网络连接"
    echo "2. 检查 Ruby 和 gem 版本"
    echo "3. 确保有写入权限"
    echo "4. 尝试使用 sudo 权限"
    echo ""
    echo "如需帮助，请访问: https://github.com/symbolfinder/symbol_finder/issues"
    exit 1
}

# 设置错误处理
trap handle_error ERR

# 主安装流程
main() {
    show_welcome
    check_ruby
    check_gem
    install_system_deps
    install_gem_deps
    install_symbol_finder
    verify_installation
    show_usage
}

# 检查是否以 root 权限运行
if [[ $EUID -eq 0 ]]; then
    print_warning "不建议以 root 权限运行此脚本"
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 运行主安装流程
main "$@"