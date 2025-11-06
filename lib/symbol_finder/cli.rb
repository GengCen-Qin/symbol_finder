# frozen_string_literal: true

require 'optparse'

module SymbolFinder
  # 命令行界面类
  #
  # 负责处理用户输入、参数解析和命令执行
  class CLI
    attr_reader :options, :index_builder, :searcher, :watcher

    # 初始化 CLI
    def initialize
      @options = {
        type: nil,           # 符号类型过滤
        zed: false,          # Zed 编辑器集成
        rebuild: false,      # 重建索引
        update: false,       # 更新索引
        status: false,       # 显示状态
        watch: false,        # 启动监控
        stop_watcher: false, # 停止监控
        verbose: false       # 详细输出
      }

      @index_builder = nil
      @searcher = nil
      @watcher = nil
    end

    # 主执行方法
    def run(args)
      @start_time = Time.now

      begin
        # 检查依赖
        SymbolFinder.check_dependencies!

        # 解析参数
        parse_options(args)

        # 执行相应命令
        execute_command(args)

      rescue Interrupt
        puts "\n❌ 操作被用户中断"
        exit 1
      rescue StandardError => e
        puts "❌ 执行出错: #{e.message}"
        puts "❌ 详细信息: #{e.backtrace.join("\n")}" if @options[:verbose]
        exit 1
      ensure
        cleanup
      end
    end

    private

    # 执行命令
    def execute_command(args)
      if @options[:rebuild]
        execute_rebuild
      elsif @options[:update]
        execute_update
      elsif @options[:status]
        execute_status
      elsif @options[:watch]
        execute_watch
      elsif @options[:stop_watcher]
        execute_stop_watcher
      elsif args.empty?
        puts '❌ 请提供搜索关键词或使用 --help 查看帮助'
        exit 1
      else
        execute_search(args.first)
      end
    end

    # 执行重建索引命令
    def execute_rebuild
      puts '🔍 SymbolFinder - 重建索引'
      puts '=' * 50

      SymbolFinder.ensure_index_dir
      index_builder = IndexBuilder.new(@options)
      result = index_builder.build_index

      puts '=' * 50
      puts "🎉 索引重建完成！"
      puts "📄 处理文件: #{result[:files_count]} 个"
      puts "⚡ 提取符号: #{result[:symbols_count]} 个"
      puts "📍 索引位置: #{SymbolFinder::INDEX_FILE}"
      puts "⏱️  用时: #{Time.now - @start_time}秒"
    end

    # 执行更新索引命令
    def execute_update
      puts '🔍 SymbolFinder - 增量更新索引'
      puts '=' * 50

      index_builder = IndexBuilder.new(@options)
      result = index_builder.update_index

      if result[:updated]
        puts '=' * 50
        puts "🎉 索引更新完成！"
        puts "⏱️  用时: #{Time.now - @start_time}秒"
      else
        puts "✅ 索引已是最新"
      end
    end

    # 执行状态查看命令
    def execute_status
      puts '📊 SymbolFinder - 状态信息'
      puts '=' * 50

      searcher = Searcher.new(@options)
      searcher.show_status

      puts '=' * 50
    end

    # 执行文件监控命令
    def execute_watch
      puts '👀 SymbolFinder - 启动文件监控'
      puts '=' * 50

      watcher = Watcher.new(@options)
      watcher.start_watcher
    end

    # 执行停止监控命令
    def execute_stop_watcher
      puts '🛑 SymbolFinder - 停止文件监控'
      puts '=' * 50

      watcher = Watcher.new(@options)
      watcher.stop_existing_watcher

      puts '=' * 50
      puts "✅ 操作完成"
    end

    # 执行搜索命令
    def execute_search(query)
      searcher = Searcher.new(@options)
      results = searcher.search(query)

      if @options[:verbose]
        puts '🔍 SymbolFinder - 符号搜索'
        puts '=' * 50
        puts "🎯 搜索词: \"#{query}\""
        puts "⚡ 响应时间: #{(Time.now - @start_time) * 1000}ms" if @start_time
        puts '=' * 50
      end

      searcher.display_results(query, results)
    end

    # 解析命令行参数
    def parse_options(args)
      parser = create_option_parser
      begin
        parser.parse!(args)
      rescue OptionParser::InvalidOption => e
        handle_parse_error(e)
      end
    end

    # 创建选项解析器
    def create_option_parser
      OptionParser.new do |opts|
        setup_basic_options(opts)
        setup_action_options(opts)
        setup_monitoring_options(opts)
        setup_help_option(opts)
      end
    end

    # 设置基本选项
    def setup_basic_options(opts)
      opts.banner = '用法: symbol_finder <查询> [选项]'
      opts.separator ''
      opts.separator '选项:'

      opts.on('-t', '--type TYPE', '符号类型过滤 (method|class|module|constant|scope)') do |type|
        @options[:type] = type.to_sym
      end

      opts.on('-z', '--zed', '搜索完成后直接在 Zed 中打开结果') do
        @options[:zed] = true
      end

      opts.on('-v', '--verbose', '显示详细输出') do
        @options[:verbose] = true
      end
    end

    # 设置动作选项
    def setup_action_options(opts)
      opts.on('--rebuild', '重建完整索引') do
        @options[:rebuild] = true
      end

      opts.on('--update', '增量更新索引') do
        @options[:update] = true
      end

      opts.on('--status', '显示索引状态') do
        @options[:status] = true
      end
    end

    # 设置监控选项
    def setup_monitoring_options(opts)
      opts.on('--watch', '启动文件监控，自动更新索引') do
        @options[:watch] = true
      end

      opts.on('--stop', '停止文件监控') do
        @options[:stop_watcher] = true
      end
    end

    # 设置帮助选项
    def setup_help_option(opts)
      opts.on('--version', '显示版本信息') do
        puts "SymbolFinder version #{SymbolFinder::VERSION}"
        exit 0
      end

      opts.on('-h', '--help', '显示帮助信息') do
        display_help(opts)
        exit 0
      end
    end

    # 处理解析错误
    def handle_parse_error(error)
      puts "❌ 无效选项: #{error.message}"
      puts '使用 --help 查看帮助信息'
      exit 1
    end

    # 显示帮助信息
    def display_help(parser)
      puts '🔍 SymbolFinder - Rails 项目符号搜索工具'
      puts '版本: ' + SymbolFinder::VERSION
      puts ''
      puts parser
      puts ''
      display_usage_examples
      display_zed_integration
      display_monitoring_info
      display_troubleshooting
    end

    # 显示使用示例
    def display_usage_examples
      puts '示例:'
      puts '  symbol_finder "create_user"                    # 基本搜索'
      puts '  symbol_finder "create_user" -z                 # 搜索并在 Zed 中打开'
      puts '  symbol_finder -t method "create"              # 只搜索方法'
      puts '  symbol_finder --rebuild                       # 重建索引'
      puts '  symbol_finder --update                        # 增量更新索引'
      puts '  symbol_finder --status                        # 显示索引状态'
      puts '  symbol_finder --watch                         # 启动文件监控'
      puts '  symbol_finder --stop                          # 停止文件监控'
      puts ''
    end

    # 显示 Zed 集成信息
    def display_zed_integration
      puts 'Zed 集成:'
      puts '  在 .zed/tasks.json 中添加:'
      puts '  {'
      puts '    "label": "Symbol Finder",'
      puts '    "command": "symbol_finder",'
      puts '    "args": ["-z", "{selection}"],'
      puts '    "cwd": "{projectRoot}"'
      puts '  }'
      puts ''
    end

    # 显示文件监控信息
    def display_monitoring_info
      puts '文件监控:'
      puts '  启动监控后，当 .rb 文件发生变化时自动更新索引'
      puts '  监控进程在后台运行，通过 --stop 命令停止'
      puts ''
    end

    # 显示故障排除信息
    def display_troubleshooting
      puts '故障排除:'
      puts '  1. "需要安装 parser gem" → symbol_finder --rebuild (自动安装)'
      puts '  2. 搜索结果为空 → 运行 --rebuild 重建索引'
      puts '  3. 监控不工作 → 运行 --stop 停止并重启'
      puts '  4. 索引过期 → 运行 --update 或 --rebuild'
      puts ''
    end

    # 清理资源
    def cleanup
      @index_builder&.cleanup
      @searcher = nil
      @watcher&.cleanup
    end
  end
end