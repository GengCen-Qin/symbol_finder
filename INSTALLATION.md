# SymbolFinder 安装指南

SymbolFinder 提供了多种安装方式，用户可以根据自己的需求选择最适合的方式。

## 📦 安装方式

### 1. 一键安装脚本（推荐）

使用我们提供的一键安装脚本，自动安装所有依赖：

```bash
curl -sSL https://raw.githubusercontent.com/symbolfinder/symbol_finder/main/install.sh | bash
```

或者：

```bash
wget https://raw.githubusercontent.com/symbolfinder/symbol_finder/main/install.sh
chmod +x install.sh
./install.sh
```

### 2. 从 RubyGems 安装

最简单直接的安装方式：

```bash
gem install symbol_finder
```

### 3. 从源码安装

如果需要安装最新开发版本：

```bash
git clone https://github.com/symbolfinder/symbol_finder.git
cd symbol_finder
rake gem:install
```

### 4. 在 Rails 项目中使用

将 SymbolFinder 添加到您的 Rails 项目：

```ruby
# Gemfile
gem 'symbol_finder'
```

然后运行：

```bash
bundle install
```

## 📋 系统要求

- **Ruby**: >= 2.5.0
- **操作系统**: Linux, macOS, Windows (WSL)
- **依赖**: 自动安装 parser, listen, concurrent-ruby

## 🛠️ 依赖说明

SymbolFinder 依赖以下 gem 包，所有安装方式都会自动处理这些依赖：

- **parser** (~> 3.0) - Ruby 代码解析，用于 AST 分析
- **listen** (~> 3.0) - 文件系统监控，用于实时更新索引
- **concurrent-ruby** (~> 1.0) - 并发处理支持

## 🔧 手动安装依赖

如果由于网络原因导致自动安装失败，可以手动安装依赖：

```bash
gem install parser listen concurrent-ruby
gem install symbol_finder
```

## ✅ 验证安装

安装完成后，验证 SymbolFinder 是否正确安装：

```bash
# 检查版本
symbol_finder --version

# 查看帮助
symbol_finder --help

# 测试基本功能（在包含 Ruby 文件的目录中）
symbol_finder --rebuild
symbol_finder "YourSymbol"
```

## 🎯 快速开始

1. **在您的 Rails 项目中构建索引：**
   ```bash
   cd /path/to/your/rails/project
   symbol_finder --rebuild
   ```

2. **搜索符号：**
   ```bash
   symbol_finder "User"        # 搜索类
   symbol_finder "create_user" # 搜索方法
   symbol_finder -t method "create" # 只搜索方法
   ```

3. **启动实时监控：**
   ```bash
   symbol_finder --watch       # 启动文件监控
   symbol_finder --stop        # 停止监控
   ```

## 🔗 编辑器集成

### Zed 编辑器

创建 `.zed/tasks.json` 文件：

```json
{
  "tasks": [
    {
      "label": "Symbol Finder",
      "command": "symbol_finder",
      "args": ["-z", "{selection}"],
      "cwd": "{projectRoot}"
    }
  ]
}
```

### 其他编辑器

SymbolFinder 是命令行工具，可以与任何支持命令行调用的编辑器集成。

## 🛠️ 故障排除

### 常见问题

1. **权限问题**
   ```bash
   sudo gem install symbol_finder
   ```

2. **网络连接问题**
   ```bash
   # 使用国内镜像
   gem sources --add https://gems.ruby-china.com/ --remove https://rubygems.org/
   gem install symbol_finder
   ```

3. **编译错误**
   ```bash
   # macOS
   xcode-select --install

   # Ubuntu/Debian
   sudo apt-get install build-essential ruby-dev

   # CentOS/RHEL
   sudo yum install gcc ruby-devel make
   ```

4. **Ruby 版本过低**
   请升级到 Ruby 2.5 或更高版本：
   ```bash
   # 使用 RVM
   rvm install 2.7
   rvm use 2.7

   # 使用 rbenv
   rbenv install 2.7.0
   rbenv local 2.7.0
   ```

### 卸载

如需卸载 SymbolFinder：

```bash
gem uninstall symbol_finder
```

## 📚 更多资源

- [完整文档](README.md)
- [GitHub 仓库](https://github.com/symbolfinder/symbol_finder)
- [问题反馈](https://github.com/symbolfinder/symbol_finder/issues)
- [更新日志](CHANGELOG.md)

## 🎉 安装成功！

恭喜！您已成功安装 SymbolFinder。现在享受高效的符号搜索体验吧！

如遇到问题，请通过 GitHub Issues 联系我们。