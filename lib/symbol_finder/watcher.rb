# frozen_string_literal: true

require 'listen'
require 'json'
require 'digest'
require 'parser/current'
require 'fileutils'

module SymbolFinder
  # 负责文件监控和自动索引更新的类
  #
  # 主要功能：
  # - 实时监控 Ruby 文件变更
  # - 自动触发索引更新
  # - 进程管理（启动/停止）
  # - 优雅的信号处理
  class Watcher
    attr_reader :listener, :watching, :options

    # 初始化文件监控器
    def initialize(options = {})
      @options = {
        verbose: false
      }.merge(options)

      @listener = nil
      @watching = false
      @index_builder = IndexBuilder.new(@options)
    end

    # 启动文件监控
    def start_watcher
      if File.exist?(SymbolFinder::PID_FILE)
        pid = File.read(SymbolFinder::PID_FILE).strip
        if SymbolFinder.process_running?(pid.to_i)
          puts "❌ 文件监控已在运行中 (PID: #{pid})"
          puts '使用 --stop 停止监控'
          return
        else
          puts '🧹 清理过期的 PID 文件' if @options[:verbose]
          File.delete(SymbolFinder::PID_FILE)
        end
      end

      # 确保索引存在
      unless File.exist?(SymbolFinder::INDEX_FILE)
        puts '📥 索引不存在，先构建索引...'
        @index_builder.build_index
      end

      puts '👀 启动文件监控...' if @options[:verbose]
      puts '💡 按 Ctrl+C 停止监控' if @options[:verbose]
      puts "📝 监控目录: #{Dir.pwd}" if @options[:verbose]

      # 保存当前进程 PID
      File.write(SymbolFinder::PID_FILE, Process.pid.to_s)

      # 设置信号处理
      setup_signal_handlers

      @watching = true
      setup_file_listener
      start_monitoring_loop
    end

    # 停止文件监控
    def stop_watcher
      if @listener
        @listener.stop
        @listener = nil
      end

      @watching = false

      return unless File.exist?(SymbolFinder::PID_FILE)

      File.delete(SymbolFinder::PID_FILE)
      puts '✅ 文件监控已停止' if @options[:verbose]
    end

    # 停止已存在的监控进程
    def stop_existing_watcher
      unless File.exist?(SymbolFinder::PID_FILE)
        puts '❌ 没有运行中的文件监控'
        return
      end

      pid = File.read(SymbolFinder::PID_FILE).strip
      if SymbolFinder.process_running?(pid.to_i)
        begin
          Process.kill('TERM', pid.to_i)
          puts "🛑 已发送停止信号给进程 #{pid}" if @options[:verbose]

          # 等待进程结束
          5.times do
            sleep(1)
            next if SymbolFinder.process_running?(pid.to_i)

            puts '✅ 文件监控已停止' if @options[:verbose]
            File.delete(SymbolFinder::PID_FILE)
            return
          end

          # 强制终止
          puts '⚠️  强制终止进程...' if @options[:verbose]
          Process.kill('KILL', pid.to_i)
          File.delete(SymbolFinder::PID_FILE)
          puts '✅ 文件监控已强制停止' if @options[:verbose]
        rescue Errno::ESRCH
          puts '🧹 进程已不存在，清理 PID 文件' if @options[:verbose]
          File.delete(SymbolFinder::PID_FILE)
        rescue StandardError => e
          puts "❌ 停止进程失败: #{e.message}"
        end
      else
        puts '🧹 进程不存在，清理 PID 文件' if @options[:verbose]
        File.delete(SymbolFinder::PID_FILE)
      end
    end

    private

    # 设置信号处理器
    def setup_signal_handlers
      Signal.trap('INT') do
        puts "\n🛑 收到停止信号，正在关闭监控..." if @options[:verbose]
        @watching = false
        @listener&.stop
        @listener = nil
        exit 0
      end

      Signal.trap('TERM') do
        puts "\n🛑 收到终止信号，正在关闭监控..." if @options[:verbose]
        @watching = false
        @listener&.stop
        @listener = nil
        exit 0
      end
    end

    # 设置文件监听器
    def setup_file_listener
      @listener = Listen.to('.',
                            ignore: [
                              %r{\.git/},
                              %r{node_modules/},
                              %r{vendor/},
                              %r{tmp/},
                              %r{\.symbol_finder/}
                            ]) do |modified, added, removed|
        handle_file_changes(modified, added, removed)
      end
    end

    # 开始监控循环
    def start_monitoring_loop
      @listener.start
      puts '✅ 文件监控已启动' if @options[:verbose]
      puts "🔄 监控中... (#{Time.now.strftime('%H:%M:%S')})" if @options[:verbose]

      # 保持进程运行
      sleep(1) while @watching
    end

    # 处理文件变更
    def handle_file_changes(modified, added, removed)
      ruby_changes = {
        modified: modified.select { |f| f.end_with?('.rb') },
        added: added.select { |f| f.end_with?('.rb') },
        removed: removed.select { |f| f.end_with?('.rb') }
      }

      total_changes = ruby_changes.values.map(&:length).sum
      return if total_changes == 0

      if @options[:verbose]
        puts
        puts "📝 检测到文件变更 (#{Time.now.strftime('%H:%M:%S')}):"
        puts "   📝 修改: #{ruby_changes[:modified].length} 个文件"
        puts "   ➕ 新增: #{ruby_changes[:added].length} 个文件"
        puts "   ➖ 删除: #{ruby_changes[:removed].length} 个文件"

        ruby_changes[:modified].each { |file| puts "   📝 #{file}" } if ruby_changes[:modified].any?
        ruby_changes[:added].each { |file| puts "   ➕ #{file}" } if ruby_changes[:added].any?
        ruby_changes[:removed].each { |file| puts "   ➖ #{file}" } if ruby_changes[:removed].any?
      end

      puts '🔄 更新索引...' if @options[:verbose]
      update_index_silent(ruby_changes)
      puts '✅ 索引更新完成！继续监控...' if @options[:verbose]
    end

    # 静默更新索引（用于监控中）
    def update_index_silent(ruby_changes)
      return unless File.exist?(SymbolFinder::INDEX_FILE) && File.exist?(SymbolFinder::FILES_FILE)

      # 使用 IndexBuilder 的更新功能，但静默运行
      files = Dir.glob(SymbolFinder::RUBY_FILE_PATTERN).reject { |file| file.match?(SymbolFinder::FILE_FILTER_REGEX) }
      file_data = JSON.parse(File.read(SymbolFinder::FILES_FILE))
      index_data = JSON.parse(File.read(SymbolFinder::INDEX_FILE))
      symbol_index = index_data['symbols']

      # 处理删除的文件
      ruby_changes[:removed].each do |file|
        file_data.delete(file)
        remove_file_symbols(symbol_index, file)
      end

      # 处理新增和修改的文件
      (ruby_changes[:modified] + ruby_changes[:added]).each do |file|
        remove_file_symbols(symbol_index, file)
        add_file_symbols(symbol_index, file)
        update_file_data(file_data, file)
      end

      # 保存更新后的索引
      index_data['built_at'] = Time.now.iso8601
      index_data['total_files'] = files.length
      index_data['total_symbols'] = symbol_index.values.flatten.length
      index_data['symbols'] = symbol_index

      File.write(SymbolFinder::INDEX_FILE, JSON.pretty_generate(index_data))
      File.write(SymbolFinder::FILES_FILE, JSON.pretty_generate(file_data))
    end

    # 从符号索引中移除指定文件的符号
    def remove_file_symbols(symbol_index, file)
      symbol_index.each do |_symbol_name, symbol_list|
        symbol_list.reject! { |symbol| symbol['file'] == file }
      end
      symbol_index.reject! { |_, symbol_list| symbol_list.empty? }
    end

    # 添加文件符号到索引
    def add_file_symbols(symbol_index, file)
      file_symbols = extract_symbols_from_file(file)

      file_symbols.each do |symbol|
        name = symbol[:name]
        symbol_index[name] ||= []
        symbol_index[name] << symbol
      end
    end

    # 解析单个文件并提取符号定义
    def extract_symbols_from_file(file_path)
      symbols = []

      begin
        source = File.read(file_path)
        ast = Parser::CurrentRuby.parse(source)

        return symbols unless ast

        extract_from_node(ast, symbols, file_path)
      rescue Parser::SyntaxError => e
        puts "⚠️  语法错误: #{file_path}" if @options[:verbose]
      rescue StandardError => e
        puts "❌ 解析文件失败 #{file_path}: #{e.message}" if @options[:verbose]
      end

      symbols
    end

    # 从 AST 节点提取符号
    def extract_from_node(node, symbols, file_path, class_context = nil)
      return unless node.is_a?(Parser::AST::Node)

      case node.type
      when :class
        class_name = node.children[0].children[1].to_s
        symbols << {
          type: :class,
          name: class_name,
          file: file_path,
          line: node.location.line,
          class: class_context
        }
        extract_from_node(node.children[2], symbols, file_path, class_name)

      when :module
        module_name = node.children[0].children[1].to_s
        symbols << {
          type: :module,
          name: module_name,
          file: file_path,
          line: node.location.line,
          class: class_context
        }
        extract_from_node(node.children[1], symbols, file_path, module_name)

      when :def
        method_name = node.children[0].to_s
        symbols << {
          type: :method,
          name: method_name,
          file: file_path,
          line: node.location.line,
          class: class_context
        }

      when :defs
        method_name = node.children[1].to_s
        symbols << {
          type: :method,
          name: method_name,
          file: file_path,
          line: node.location.line,
          class: class_context,
          class_method: true
        }

      when :casgn
        const_name = node.children[1].to_s
        symbols << {
          type: :constant,
          name: const_name,
          file: file_path,
          line: node.location.line,
          class: class_context
        }

      when :send
        if is_scope_definition?(node)
          scope_name_node = node.children[2]
          scope_name = scope_name_node.children[0].to_s
          symbols << {
            type: :scope,
            name: scope_name,
            file: file_path,
            line: node.location.line,
            class: class_context
          }
        end
      end

      node.children.each do |child|
        extract_from_node(child, symbols, file_path, class_context) if child.is_a?(Parser::AST::Node)
      end
    end

    # 检查是否为 scope 定义
    def is_scope_definition?(node)
      return false unless node.type == :send
      return false unless node.children[0].nil? || node.children[0]&.type == :self
      return false unless node.children[1] == :scope

      scope_name_node = node.children[2]
      return false unless scope_name_node&.type == :sym

      block_node = node.children[3]
      return false unless block_node&.type == :block

      true
    end

    # 更新文件数据
    def update_file_data(file_data, file)
      file_stat = File.stat(file)
      file_data[file] = {
        mtime: file_stat.mtime.to_i,
        size: file_stat.size,
        hash: Digest::MD5.file(file).hexdigest
      }
    end

    # 清理资源
    def cleanup
      @listener&.stop
      @listener = nil
      @watching = false
      @index_builder&.cleanup
    end
  end
end