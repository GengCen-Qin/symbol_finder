# SymbolFinder - Rails 项目符号搜索工具

## 📋 简介

SymbolFinder 是一个为 Rails 项目设计的高性能符号搜索工具，能够快速定位方法、类、模块、常量和 Rails scope 的定义位置。支持 Zed 编辑器集成和实时文件监控。

## 🚀 核心特性

- ⚡ **毫秒级搜索** - 基于预构建索引的快速响应
- 📁 **项目内索引** - 索引存储在项目目录中，易于管理
- 🔍 **多符号类型** - 支持方法、类、模块、常量、Rails scope
- 👀 **实时监控** - 文件变更时自动更新索引
- 🔗 **Zed 集成** - 无缝编辑器跳转
- 📊 **状态监控** - 实时显示索引和监控状态

## 📦 安装依赖

```bash
gem install parser
gem install listen
```

## 🎯 基本使用

### 1. 构建索引

首次使用需要构建索引：

```bash
ruby symbol_finder.rb --rebuild
```

输出示例：
```
🔍 构建符号索引...
📁 扫描文件: 1382 个 .rb 文件
🔄 解析进度: ████████████████████ 100% (1382/1382)
⚡ 索引构建完成: 34,647 个符号
💾 保存索引: .symbol_finder/index.json
✅ 完成! 用时: 15.3 秒
```

### 2. 基本搜索

```bash
# 搜索符号
ruby symbol_finder.rb "ApplicationMailer"

# 类型过滤
ruby symbol_finder.rb -t constant "INVOICE_TYPE"
ruby symbol_finder.rb -t method "create_user"

# 前缀搜索
ruby symbol_finder.rb "User"  # 匹配 User, UserService, UserController 等
```

### 3. Zed 编辑器集成

搜索后自动在 Zed 中打开：

```bash
ruby symbol_finder.rb -z "QueryQuotationInvoice"
```

### 4. 文件监控

启动实时监控，文件修改时自动更新索引：

```bash
ruby symbol_finder.rb --watch
```

输出示例：
```
👀 启动文件监控...
💡 按 Ctrl+C 停止监控
📝 监控目录: /Users/rcc/RubyProject/rcc/oms-api
✅ 文件监控已启动
🔄 监控中... (14:30:15)
```

停止监控：

```bash
ruby symbol_finder.rb --stop
```

## 📊 状态查看

```bash
ruby symbol_finder.rb --status
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

## 🔧 索引管理

### 手动更新

```bash
# 增量更新索引（推荐）
ruby symbol_finder.rb --update

# 完全重建索引
ruby symbol_finder.rb --rebuild
```

### 监控状态下的自动更新

当启动文件监控时，任何 `.rb` 文件的修改、新增或删除都会自动触发索引更新：

```
📝 检测到文件变更 (14:35:22):
   📝 修改: 1 个文件
   📝 app/models/user.rb
🔄 更新索引...
✅ 索引更新完成！继续监控...
```

## 🔗 Zed 编辑器集成

### 方法 1：命令行使用

在 Zed 中打开终端，使用 `-z` 参数：

```bash
ruby symbol_finder.rb -z "symbol_name"
```

### 方法 2：Task 集成

在项目根目录创建 `.zed/tasks.json`：

```json
{
  "tasks": [
    {
      "label": "Symbol Finder",
      "command": "ruby",
      "args": ["symbol_finder.rb", "-z", "{selection}"],
      "cwd": "{projectRoot}"
    }
  ]
}
```

然后在 Zed 中：
1. 选中要搜索的符号文本
2. 使用快捷键绑定 Task
3. 自动跳转到符号定义位置

## 📁 项目结构

```
your-rails-project/
├── .symbol_finder/          # 索引目录（已添加到 .gitignore）
│   ├── index.json          # 主符号索引
│   ├── files.json          # 文件索引
│   ├── meta.json           # 元信息
│   └── watcher.pid         # 监控进程 PID
├── symbol_finder.rb        # 主脚本文件
├── .gitignore              # 已更新排除索引目录
└── SYMBOL_FINDER_USAGE.md  # 使用说明
```

## ⚡ 性能表现

| 操作 | 典型时间 | 说明 |
|------|----------|------|
| **首次构建** | 10-30秒 | 取决于项目大小 |
| **增量更新** | <500ms | 单文件变更 |
| **搜索响应** | <100ms | 毫秒级查询 |
| **监控响应** | 实时 | 文件变更立即触发 |

## 🎯 支持的符号类型

| 类型 | 示例 | 描述 |
|------|------|------|
| **类** | `class User` | 类定义 |
| **模块** | `module Serviceable` | 模块定义 |
| **方法** | `def create_user` | 实例方法 |
| **类方法** | `def self.find_by` | 类方法 |
| **常量** | `MAX_LIMIT = 100` | 常量定义 |
| **Rails Scope** | `scope :active, -> { where(status: 'active') }` | ActiveRecord scope |

## 💡 使用技巧

### 1. 快速启动工作流

```bash
# 一键启动监控
ruby symbol_finder.rb --watch

# 在另一个终端中搜索
ruby symbol_finder.rb "your_symbol"
```

### 2. 类型特定搜索

```bash
# 只查找常量
ruby symbol_finder.rb -t constant "VERSION"

# 只查找方法
ruby symbol_finder.rb -t method "validate"

# 只查找类
ruby symbol_finder.rb -t class "Service"
```

### 3. 模糊匹配

```bash
# 前缀匹配所有以 User 开头的符号
ruby symbol_finder.rb "User"

# 结果可能包含：User, UserService, UserController, USER_ROLE 等
```

### 4. 批量项目部署

```bash
# 复制脚本到多个项目
cp symbol_finder.rb /path/to/project1/
cp symbol_finder.rb /path/to/project2/

# 在每个项目中构建索引
cd /path/to/project1/ && ruby symbol_finder.rb --rebuild
cd /path/to/project2/ && ruby symbol_finder.rb --rebuild
```

## 🛠️ 故障排除

### 常见问题

1. **"需要安装 parser gem"**
   ```bash
   gem install parser
   ```

2. **"需要安装 listen gem"**
   ```bash
   gem install listen
   ```

3. **搜索结果为空**
   - 检查索引是否存在：`ruby symbol_finder.rb --status`
   - 重建索引：`ruby symbol_finder.rb --rebuild`

4. **监控不工作**
   - 检查进程状态：`ruby symbol_finder.rb --status`
   - 重启监控：`ruby symbol_finder.rb --stop && ruby symbol_finder.rb --watch`

5. **索引过期**
   ```bash
   ruby symbol_finder.rb --update  # 增量更新
   ruby symbol_finder.rb --rebuild  # 完全重建
   ```

### 调试模式

使用详细输出查看更多信息：

```bash
ruby symbol_finder.rb --verbose --status
ruby symbol_finder.rb --verbose --rebuild
```

## 🔄 升级和维护

### 更新脚本

```bash
# 备份现有配置
cp -r .symbol_finder .symbol_finder.backup

# 替换脚本文件
# 用新版本覆盖 symbol_finder.rb

# 重建索引
ruby symbol_finder.rb --rebuild
```

### 清理

```bash
# 停止监控
ruby symbol_finder.rb --stop

# 删除索引目录
rm -rf .symbol_finder

# 重新开始
ruby symbol_finder.rb --rebuild
```

## 📝 开发说明

### 技术架构

- **符号解析**: 基于 Parser gem 的 AST 分析
- **索引存储**: JSON 格式，支持快速查询
- **文件监控**: Listen gem 实现跨平台监控
- **进程管理**: PID 文件管理后台监控进程

### 扩展功能

脚本采用模块化设计，可以轻松扩展：
- 添加新的符号类型支持
- 实现更复杂的搜索算法
- 集成其他编辑器
- 添加统计和分析功能

## 📄 许可证

本项目采用 MIT 许可证，可自由使用和修改。