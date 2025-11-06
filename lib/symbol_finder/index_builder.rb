# frozen_string_literal: true

require 'concurrent-ruby'
require 'digest'
require 'json'
require 'fileutils'
require 'parser/current'

module SymbolFinder
  # 负责构建和管理符号索引的类
  #
  # 主要功能：
  # - 解析 Ruby 源文件提取符号
  # - 构建高效的符号索引
  # - 支持并发处理提高性能
  # - 实现增量更新机制
  class IndexBuilder
    attr_reader :options, :symbol_cache, :hash_cache, :index_cache, :thread_pool

    # 初始化索引构建器
    def initialize(options = {})
      @options = {
        verbose: false
      }.merge(options)

      @symbol_cache = {}
      @hash_cache = {}
      @index_cache = {}
      setup_thread_pool
    end

    # 设置智能线程池
    def setup_thread_pool
      processor_count = Concurrent.processor_count || 4
      max_threads = [processor_count, 8].min

      @thread_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 2,
        max_threads: max_threads,
        max_queue: 100,
        fallback_policy: :caller_runs
      )
    end

    # 构建完整索引
    def build_index
      start_time = Time.now

      puts '🔍 构建符号索引...' if @options[:verbose]

      files = find_ruby_files
      puts "📁 扫描文件: #{files.length} 个 .rb 文件" if @options[:verbose]
      puts "🚀 使用 #{@thread_pool.max_length} 个线程并发处理" if @options[:verbose]

      symbols, file_data = process_files_concurrently(files)
      symbol_index = build_symbol_index(symbols)

      save_index_data(files, symbols, symbol_index, file_data)
      save_metadata

      puts "⚡ 索引构建完成: #{symbols.length} 个符号" if @options[:verbose]
      puts "✅ 完成! 用时: #{Time.now - start_time}秒" if @options[:verbose]

      { symbols_count: symbols.length, files_count: files.length }
    end

    # 增量更新索引
    def update_index
      start_time = Time.now
      puts '🔍 检查文件变更...' if @options[:verbose]

      return build_index unless index_files_exist?

      files = find_ruby_files
      file_data = load_existing_file_data

      file_changes = detect_file_changes(files, file_data)

      if no_changes_detected?(file_changes)
        puts '✅ 索引已是最新，无需更新' if @options[:verbose]
        return { updated: false }
      end

      puts "📝 变更文件: #{file_changes[:changed].length} 个修改, #{file_changes[:new].length} 个新增" if @options[:verbose]

      symbol_index = update_symbol_index(file_changes, file_data)
      save_updated_index(files, symbol_index, file_changes[:updated_file_data])

      puts "✅ 索引更新完成! 用时: #{Time.now - start_time}秒" if @options[:verbose]
      { updated: true, changes: file_changes }
    end

    private

    # 查找所有 Ruby 文件
    def find_ruby_files
      Dir.glob(SymbolFinder::RUBY_FILE_PATTERN).reject { |file| file.match?(SymbolFinder::FILE_FILTER_REGEX) }
    end

    # 并发处理文件
    def process_files_concurrently(files)
      futures = files.map do |file|
        Concurrent::Future.execute(executor: @thread_pool) do
          process_single_file(file)
        end
      end

      symbols = []
      file_data = {}

      futures.each_with_index do |future, index|
        if @options[:verbose]
          percentage = (index + 1).to_f / futures.length * 100
          filled = (percentage / 5).to_i
          bar = '█' * filled + '░' * (20 - filled)
          print "\r🔄 解析进度: #{bar} #{percentage.round(1)}% (#{index + 1}/#{futures.length})"
          $stdout.flush
        end

        begin
          file, file_symbols, data = future.value!
          symbols.concat(file_symbols)
          file_data[file] = data
        rescue Concurrent::TimeoutError
          puts '⚠️  文件处理超时，跳过' if @options[:verbose]
        rescue StandardError => e
          puts "❌ 处理文件时出错: #{e.message}" if @options[:verbose]
        end
      end

      puts '' if @options[:verbose]
      [symbols, file_data]
    end

    # 处理单个文件
    def process_single_file(file)
      file_symbols = extract_symbols_from_file(file)
      file_data = create_file_data(file)
      [file, file_symbols, file_data]
    end

    # 创建文件数据
    def create_file_data(file)
      file_stat = File.stat(file)
      {
        mtime: file_stat.mtime.to_i,
        size: file_stat.size,
        hash: file_hash_cached(file)
      }
    end

    # 缓存的文件哈希计算
    def file_hash_cached(file_path)
      file_stat = File.stat(file_path)
      cache_key = "#{file_path}:#{file_stat.mtime}:#{file_stat.size}"
      @hash_cache[cache_key] ||= Digest::MD5.file(file_path).hexdigest
    end

    # 解析单个文件并提取符号定义
    def extract_symbols_from_file(file_path)
      cache_key = file_hash_cached(file_path)
      return @symbol_cache[cache_key] if @symbol_cache.key?(cache_key)

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

      @symbol_cache[cache_key] = symbols
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

    # 构建符号索引
    def build_symbol_index(symbols)
      symbol_index = {}

      symbols.each do |symbol|
        name = symbol[:name]
        symbol_index[name] ||= []
        symbol_index[name] << symbol
      end

      symbol_index
    end

    # 保存索引数据
    def save_index_data(files, symbols, symbol_index, file_data)
      index_data = {
        version: SymbolFinder::VERSION,
        built_at: Time.now.iso8601,
        total_files: files.length,
        total_symbols: symbols.length,
        symbols: symbol_index
      }

      SymbolFinder.ensure_index_dir
      File.write(SymbolFinder::INDEX_FILE, JSON.pretty_generate(index_data))
      File.write(SymbolFinder::FILES_FILE, JSON.pretty_generate(file_data))
    end

    # 保存元数据
    def save_metadata
      meta_data = {
        last_built: Time.now.iso8601,
        ruby_version: RUBY_VERSION,
        parser_version: Parser::VERSION
      }
      File.write(SymbolFinder::META_FILE, JSON.pretty_generate(meta_data))
    end

    # 检查索引文件是否存在
    def index_files_exist?
      File.exist?(SymbolFinder::INDEX_FILE) && File.exist?(SymbolFinder::FILES_FILE)
    end

    # 加载现有文件数据
    def load_existing_file_data
      JSON.parse(File.read(SymbolFinder::FILES_FILE))
    end

    # 检测文件变更
    def detect_file_changes(files, file_data)
      changed_files = []
      new_files = []

      files.each do |file|
        file_stat = File.stat(file)
        current_data = file_data[file]

        if current_data.nil?
          new_files << file
        elsif file_changed?(current_data, file_stat, file)
          changed_files << file
        end
      end

      deleted_files = file_data.keys - files

      {
        changed: changed_files,
        new: new_files,
        deleted: deleted_files
      }
    end

    # 检查文件是否已变更
    def file_changed?(current_data, file_stat, file)
      current_data['mtime'] != file_stat.mtime.to_i ||
        current_data['size'] != file_stat.size ||
        current_data['hash'] != file_hash_cached(file)
    end

    # 检查是否有文件变更
    def no_changes_detected?(file_changes)
      file_changes[:changed].empty? &&
        file_changes[:new].empty? &&
        file_changes[:deleted].empty?
    end

    # 更新符号索引
    def update_symbol_index(file_changes, original_file_data)
      index_data = JSON.parse(File.read(SymbolFinder::INDEX_FILE))
      symbol_index = index_data['symbols']
      updated_file_data = original_file_data.dup

      remove_deleted_files(symbol_index, updated_file_data, file_changes[:deleted])
      update_changed_files(symbol_index, updated_file_data, file_changes[:changed] + file_changes[:new])

      file_changes[:updated_file_data] = updated_file_data
      symbol_index
    end

    # 移除已删除文件的符号
    def remove_deleted_files(symbol_index, file_data, deleted_files)
      deleted_files.each do |file|
        file_data.delete(file)
        remove_file_symbols(symbol_index, file)
      end
    end

    # 从符号索引中移除指定文件的符号
    def remove_file_symbols(symbol_index, file)
      symbol_index.each do |_symbol_name, symbol_list|
        symbol_list.reject! { |symbol| symbol['file'] == file }
      end
      symbol_index.reject! { |_, symbol_list| symbol_list.empty? }
    end

    # 更新增改和新增的文件
    def update_changed_files(symbol_index, file_data, files_to_update)
      files_to_update.each do |file|
        remove_file_symbols(symbol_index, file)
        add_file_symbols(symbol_index, file)
        update_file_data(file_data, file)
      end
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

    # 更新文件数据
    def update_file_data(file_data, file)
      file_stat = File.stat(file)
      file_data[file] = {
        mtime: file_stat.mtime.to_i,
        size: file_stat.size,
        hash: Digest::MD5.file(file).hexdigest
      }
    end

    # 保存更新后的索引
    def save_updated_index(files, symbol_index, updated_file_data)
      index_data = {
        version: SymbolFinder::VERSION,
        built_at: Time.now.iso8601,
        total_files: files.length,
        total_symbols: symbol_index.values.flatten.length,
        symbols: symbol_index
      }

      File.write(SymbolFinder::INDEX_FILE, JSON.pretty_generate(index_data))
      File.write(SymbolFinder::FILES_FILE, JSON.pretty_generate(updated_file_data))
    end

    # 清理资源
    def cleanup
      @thread_pool&.shutdown
      @thread_pool&.wait_for_termination(30)
      clear_cache
    end

    # 清理缓存
    def clear_cache
      @symbol_cache.clear
      @hash_cache.clear
      @index_cache.clear
      GC.start if GC.respond_to?(:start)
    end
  end
end