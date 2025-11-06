# frozen_string_literal: true

require 'symbol_finder/version'
require 'symbol_finder/index_builder'
require 'symbol_finder/searcher'
require 'symbol_finder/watcher'
require 'symbol_finder/cli'

# SymbolFinder - Rails 项目符号搜索工具
#
# 一个高性能的 Ruby 符号搜索工具，专为 Rails 项目设计。提供毫秒级搜索、
# 实时文件监控和编辑器集成功能。
#
# 主要功能：
# - 快速符号搜索（类、模块、方法、常量、Rails scope）
# - 实时文件监控和自动索引更新
# - 编辑器集成，支持直接跳转
# - 并发处理和性能优化
# - 灵活的命令行界面
#
# 使用示例：
#   # 在命令行中使用
#   symbol_finder "User"
#   symbol_finder --rebuild
#
#   # 在代码中使用
#   finder = SymbolFinder::CLI.new
#   finder.run(["--rebuild"])
#
# 作者: SymbolFinder Team
# 版本: 1.0.0
# 许可证: MIT
module SymbolFinder
  class Error < StandardError; end

  # 索引目录和文件常量
  INDEX_DIR = '.symbol_finder'
  INDEX_FILE = File.join(INDEX_DIR, 'index.json')
  FILES_FILE = File.join(INDEX_DIR, 'files.json')
  META_FILE = File.join(INDEX_DIR, 'meta.json')
  PID_FILE = File.join(INDEX_DIR, 'watcher.pid')

  # 性能优化：预编译正则表达式
  FILE_FILTER_REGEX = %r{\A\..*|vendor/.*|tmp/.*}i
  RUBY_FILE_PATTERN = '**/*.rb'

  class << self
    # 获取当前版本
    def version
      VERSION
    end

    # 检查必要的依赖
    def check_dependencies!
      require 'parser/current'
      require 'listen'
      require 'concurrent-ruby'
      require 'json'
      require 'fileutils'
      require 'digest'
      require 'optparse'
      require 'time'
    rescue LoadError => e
      puts "❌ 缺少依赖: #{e.message}"
      puts "请运行: gem install symbol_finder"
      exit 1
    end

    # 检查进程是否在运行
    def process_running?(pid)
      Process.getpgid(pid)
      true
    rescue Errno::ESRCH
      false
    end

    # 确保索引目录存在
    def ensure_index_dir
      FileUtils.mkdir_p(INDEX_DIR) unless Dir.exist?(INDEX_DIR)
    end
  end
end