# SymbolFinder

[![Gem Version](https://badge.fury.io/rb/symbol_finder.svg)](https://badge.fury.io/rb/symbol_finder)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D2.5.0-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

SymbolFinder 是一个为 Rails 项目设计的高性能符号搜索工具，能够快速定位方法、类、模块、常量和 Rails scope 的定义位置。支持毫秒级搜索、实时文件监控和编辑器集成。

## ✨ 核心特性

- ⚡ **毫秒级搜索** - 基于预构建索引的快速响应
- 📁 **项目内索引** - 索引存储在项目目录中，易于管理
- 🔍 **多符号类型** - 支持方法、类、模块、常量、Rails scope
- 👀 **实时监控** - 文件变更时自动更新索引
- 🔗 **编辑器集成** - 无缝 Zed 编辑器跳转
- 📊 **状态监控** - 实时显示索引和监控状态
- 🚀 **并发处理** - 优化的多线程处理
- 🛠️ **自动依赖** - 自动安装缺失的 gem 依赖

## 📦 安装

### 从 RubyGems 安装（推荐）

```bash
gem install symbol_finder
```

### 从源码安装

```bash
git clone https://github.com/symbolfinder/symbol_finder.git
cd symbol_finder
rake gem:install
```

## 🎯 快速开始

### 1. 构建索引

在 Rails 项目根目录运行：

```bash
symbol_finder --rebuild
```

### 2. 搜索符号

```bash
# 基本搜索
symbol_finder "ApplicationMailer"

# 类型过滤
symbol_finder -t method "create_user"
symbol_finder -t constant "MAX_LIMIT"

# 前缀搜索
symbol_finder "User"  # 匹配 User, UserService, UserController 等
```

### 3. 编辑器集成

```bash
# 搜索后直接在 Zed 中打开
symbol_finder -z "symbol_name"
```

## 📚 使用指南

### 命令行选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `-t, --type TYPE` | 符号类型过滤 | `-t method` |
| `-z, --zed` | 在 Zed 编辑器中打开结果 | `-z` |
| `-v, --verbose` | 显示详细输出 | `--verbose` |
| `--rebuild` | 重建完整索引 | `--rebuild` |
| `--update` | 增量更新索引 | `--update` |
| `--status` | 显示索引状态 | `--status` |
| `--watch` | 启动文件监控 | `--watch` |
| `--stop` | 停止文件监控 | `--stop` |
| `-h, --help` | 显示帮助信息 | `--help` |

### 支持的符号类型

| 类型 | 描述 | 示例 |
|------|------|------|
| `class` | 类定义 | `class User` |
| `module` | 模块定义 | `module Serviceable` |
| `method` | 实例/类方法 | `def create_user` |
| `constant` | 常量定义 | `MAX_LIMIT = 100` |
| `scope` | Rails scope | `scope :active, -> { where(status: 'active') }` |

### 实时监控

启动文件监控，自动检测变更并更新索引：

```bash
symbol_finder --watch
```

停止监控：

```bash
symbol_finder --stop
```

### Zed 编辑器集成

在 Zed 中完美集成，创建 `.zed/tasks.json`：

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

然后在 Zed 中：
1. 选中要搜索的符号文本
2. 绑定快捷键到 Symbol Finder 任务
3. 自动跳转到符号定义位置

## 🔧 高级功能

### 状态查看

查看索引状态和统计信息：

```bash
symbol_finder --status
```

输出示例：
```
📊 索引状态:
📁 索引目录: .symbol_finder
📅 构建时间: 2025-11-06 14:30:15
📄 文件数量: 1382
⚡ 符号数量: 34,647
💎 Ruby 版本: 2.6.6
🔧 Parser 版本: 3.3.5.0
👀 文件监控: 运行中 (PID: 12345)
✅ 索引是最新的
```

### 性能表现

| 操作 | 典型时间 | 说明 |
|------|----------|------|
| **首次构建** | 10-30秒 | 取决于项目大小 |
| **增量更新** | <500ms | 单文件变更 |
| **搜索响应** | <100ms | 毫秒级查询 |
| **监控响应** | 实时 | 文件变更立即触发 |

## 🏗️ 项目结构

```
your-rails-project/
├── .symbol_finder/          # 索引目录（自动忽略）
│   ├── index.json          # 主符号索引
│   ├── files.json          # 文件索引
│   ├── meta.json           # 元信息
│   └── watcher.pid         # 监控进程 PID
├── .zed/tasks.json         # Zed 编辑器集成
└── Gemfile                 # 添加 gem 'symbol_finder'
```

## 🚀 性能优化

### 智能缓存
- 符号解析结果缓存
- 文件哈希缓存
- 索引数据缓存

### 并发处理
- 多线程文件解析
- 智能线程池配置
- 异步索引更新

### 增量更新
- 只处理变更文件
- 智能变更检测
- 高效索引更新

## 🛠️ 故障排除

### 常见问题

1. **"需要安装依赖"**
   ```bash
   symbol_finder --rebuild  # 自动安装依赖
   ```

2. **搜索结果为空**
   ```bash
   symbol_finder --rebuild  # 重建索引
   ```

3. **监控不工作**
   ```bash
   symbol_finder --stop && symbol_finder --watch
   ```

4. **索引过期**
   ```bash
   symbol_finder --update  # 增量更新
   symbol_finder --rebuild # 完全重建
   ```

### 调试模式

使用详细输出查看更多信息：

```bash
symbol_finder --verbose --status
symbol_finder --verbose --rebuild
```

## 📈 贡献

欢迎提交 Issue 和 Pull Request！

### 开发环境设置

```bash
git clone https://github.com/symbolfinder/symbol_finder.git
cd symbol_finder
bundle install
rake spec  # 运行测试
rake rubocop  # 代码风格检查
```

### 测试

```bash
# 运行所有测试
rake spec

# 运行特定测试
rspec spec/symbol_finder_spec.rb

# 测试安装流程
rake test:install
```

## 📝 更新日志

### v1.0.0
- 初始版本发布
- 支持符号搜索和索引构建
- 文件监控和实时更新
- Zed 编辑器集成
- 自动依赖安装

## 📄 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE) 文件。

## 🔗 相关链接

- [GitHub 仓库](https://github.com/symbolfinder/symbol_finder)
- [RubyGems 页面](https://rubygems.org/gems/symbol_finder)
- [问题反馈](https://github.com/symbolfinder/symbol_finder/issues)
- [更新日志](CHANGELOG.md)

## 🙏 致谢

感谢以下开源项目：
- [Parser](https://github.com/whitequark/parser) - Ruby AST 解析
- [Listen](https://github.com/guard/listen) - 文件监控
- [Concurrent Ruby](https://github.com/ruby-concurrency/concurrent-ruby) - 并发处理

---

**SymbolFinder** - 让符号搜索变得简单高效 ⚡