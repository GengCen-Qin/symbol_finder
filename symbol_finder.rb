#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'digest'
require 'optparse'
require 'time'
require 'concurrent-ruby'

# 检查必要的 gem
begin
  require 'parser/current'
rescue LoadError
  puts '❌ 需要安装 parser gem'
  puts '请运行: gem install parser'
  exit 1
end

# 检查文件监控依赖
begin
  require 'listen'
rescue LoadError
  puts '❌ 需要安装 listen gem 进行文件监控'
  puts '请运行: gem install listen'
  exit 1
end

# SymbolFinder - Rails 项目符号搜索工具
#
# 一个高性能的 Ruby 符号搜索工具，专为 Rails 项目设计。提供毫秒级搜索、
# 实时文件监控和 Zed 编辑器集成功能。
#
# 主要功能：
# - 快速符号搜索（类、模块、方法、常量、Rails scope）
# - 实时文件监控和自动索引更新
# - Zed 编辑器集成，支持直接跳转
# - 并发处理和性能优化
# - 灵活的命令行界面
#
# 使用示例：
#   finder = SymbolFinder.new
#   finder.build_index                    # 构建索引
#   results = finder.search("User")       # 搜索符号
#   finder.display_results("User", results) # 显示结果
#
# 作者: SymbolFinder Team
# 版本: 1.0.0
# 许可证: MIT
class SymbolFinder
  # 版本和配置常量
  VERSION = '1.0.0'
  INDEX_DIR = '.symbol_finder'
  INDEX_FILE = File.join(INDEX_DIR, 'index.json')
  FILES_FILE = File.join(INDEX_DIR, 'files.json')
  META_FILE = File.join(INDEX_DIR, 'meta.json')
  PID_FILE = File.join(INDEX_DIR, 'watcher.pid')

  # 性能优化：预编译正则表达式
  FILE_FILTER_REGEX = %r{\A\..*|vendor/.*|tmp/.*}i
  RUBY_FILE_PATTERN = '**/*.rb'

  # ==========================================
  # 初始化和基础设置
  # ==========================================

  # 初始化 SymbolFinder 实例
  #
  # 设置配置选项、缓存系统、线程池和文件监控组件。
  # 使用智能线程池配置以优化并发处理性能。
  #
  # 实例变量:
  #   @options - 命令行选项存储
  #   @symbol_cache - 符号解析结果缓存
  #   @hash_cache - 文件哈希值缓存
  #   @index_cache - 索引数据缓存
  #   @thread_pool - 并发处理线程池
  #   @listener - 文件监控监听器
  #   @watching - 文件监控状态标志
  def initialize
    @options = {
      type: nil, # 符号类型过滤
      zed: false,         # Zed 编辑器集成
      rebuild: false,     # 重建索引
      update: false,      # 更新索引
      status: false,      # 显示状态
      watch: false,       # 启动监控
      stop_watcher: false, # 停止监控
      verbose: false # 详细输出
    }

    @listener = nil      # 文件监控监听器
    @watching = false    # 监控状态标志

    # 性能优化：缓存和线程池
    @symbol_cache = {}   # 符号解析缓存
    @hash_cache = {}     # 文件哈希缓存
    @index_cache = {}    # 索引数据缓存

    # 性能优化：智能线程池配置
    setup_thread_pool

    ensure_index_dir
  end

  # 设置智能线程池
  #
  # 根据系统处理器数量自动配置线程池参数，
  # 在性能和资源使用之间取得平衡。
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

  # ==========================================
  # 工具方法
  # ==========================================

  # 确保索引目录存在
  def ensure_index_dir
    FileUtils.mkdir_p(INDEX_DIR) unless Dir.exist?(INDEX_DIR)
  end

  # 显示进度条
  def show_progress(current, total, prefix = '处理中')
    percentage = (current.to_f / total * 100).round(1)
    filled = (percentage / 5).to_i
    bar = '█' * filled + '░' * (20 - filled)

    print "\r🔄 #{prefix}: #{bar} #{percentage}% (#{current}/#{total})"
    $stdout.flush
    puts '' if current == total
  end

  # 查找所有 Ruby 文件 - 性能优化版
  def find_ruby_files
    @ruby_files ||= Dir.glob(RUBY_FILE_PATTERN).reject { |file| file.match?(FILE_FILTER_REGEX) }
  end

  # 性能优化：缓存的文件哈希计算
  def file_hash_cached(file_path)
    file_stat = File.stat(file_path)
    cache_key = "#{file_path}:#{file_stat.mtime}:#{file_stat.size}"
    @hash_cache[cache_key] ||= Digest::MD5.file(file_path).hexdigest
  end

  # ==========================================
  # 符号提取和解析
  # ==========================================

  # 解析单个文件并提取符号定义
  #
  # 使用 Parser gem 解析 Ruby 源文件的 AST，
  # 提取类、模块、方法、常量和 Rails scope 等符号。
  # 包含智能缓存机制以避免重复解析。
  #
  # 参数:
  #   file_path - 要解析的 Ruby 文件路径
  #
  # 返回:
  #   Array<Hash> - 符号信息数组，每个元素包含 type, name, file, line 等信息
  #
  # 示例:
  #   symbols = extract_symbols_from_file("app/models/user.rb")
  #   # => [{type: :class, name: "User", file: "app/models/user.rb", line: 1}, ...]
  def extract_symbols_from_file(file_path)
    # 性能优化：使用文件内容和修改时间作为缓存键
    cache_key = file_hash_cached(file_path)
    return @symbol_cache[cache_key] if @symbol_cache.key?(cache_key)

    symbols = []

    begin
      source = File.read(file_path)
      ast = Parser::CurrentRuby.parse(source)

      return symbols unless ast

      # 递归遍历 AST 提取各种类型的符号
      extract_from_node(ast, symbols, file_path)
    rescue Parser::SyntaxError => e
      # 优雅处理语法错误，不影响整体处理流程
      puts "⚠️  语法错误: #{file_path}" if @options[:verbose]
    rescue StandardError => e
      puts "❌ 解析文件失败 #{file_path}: #{e.message}" if @options[:verbose]
    end

    # 性能优化：缓存解析结果以避免重复处理
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

      # 递归处理类内部
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

      # 递归处理模块内部
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
      # 类方法定义 def self.method_name
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
      # 常量赋值 CONSTANT = value
      const_name = node.children[1].to_s
      symbols << {
        type: :constant,
        name: const_name,
        file: file_path,
        line: node.location.line,
        class: class_context
      }

    when :send
      # 检查 scope 定义
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

    # 递归处理子节点
    node.children.each do |child|
      extract_from_node(child, symbols, file_path, class_context) if child.is_a?(Parser::AST::Node)
    end
  end

  # 检查是否为 scope 定义
  def is_scope_definition?(node)
    return false unless node.type == :send
    return false unless node.children[0].nil? || node.children[0]&.type == :self
    return false unless node.children[1] == :scope

    # 检查第三个参数是否为 scope 名称（symbol）
    scope_name_node = node.children[2]
    return false unless scope_name_node&.type == :sym

    # 检查第四个参数是否为 block 节点（包含 lambda 或 Proc）
    block_node = node.children[3]
    return false unless block_node&.type == :block

    true
  end

  # ==========================================
  # 索引构建和管理
  # ==========================================

  # 构建完整索引 - 性能优化并发版
  def build_index
    start_build_message

    files = find_ruby_files
    show_build_start_info(files)

    symbols, file_data = process_files_concurrently(files)
    symbol_index = build_symbol_index(symbols)

    save_index_data(files, symbols, symbol_index, file_data)
    save_metadata

    show_build_completion(symbols.length)
  end

  private

  # 显示构建开始信息
  def start_build_message
    puts '🔍 构建符号索引...'
  end

  # 显示构建开始统计
  def show_build_start_info(files)
    puts "📁 扫描文件: #{files.length} 个 .rb 文件"
    puts "🚀 使用 #{@thread_pool.max_length} 个线程并发处理"
  end

  # 并发处理文件
  def process_files_concurrently(files)
    futures = create_file_processing_futures(files)
    collect_file_processing_results(futures)
  end

  # 创建文件处理任务
  def create_file_processing_futures(files)
    files.map do |file|
      Concurrent::Future.execute(executor: @thread_pool) do
        process_single_file(file)
      end
    end
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

  # 收集文件处理结果
  def collect_file_processing_results(futures)
    symbols = []
    file_data = {}

    futures.each_with_index do |future, index|
      show_progress(index + 1, futures.length, '解析进度')

      begin
        file, file_symbols, data = future.value!
        symbols.concat(file_symbols)
        file_data[file] = data
      rescue Concurrent::TimeoutError
        puts '⚠️  文件处理超时，跳过'
      rescue StandardError => e
        puts "❌ 处理文件时出错: #{e.message}" if @options[:verbose]
      end
    end

    [symbols, file_data]
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
      version: VERSION,
      built_at: Time.now.iso8601,
      total_files: files.length,
      total_symbols: symbols.length,
      symbols: symbol_index
    }

    File.write(INDEX_FILE, JSON.pretty_generate(index_data))
    File.write(FILES_FILE, JSON.pretty_generate(file_data))
  end

  # 保存元数据
  def save_metadata
    meta_data = {
      last_built: Time.now.iso8601,
      ruby_version: RUBY_VERSION,
      parser_version: Parser::VERSION
    }
    File.write(META_FILE, JSON.pretty_generate(meta_data))
  end

  # 显示构建完成信息
  def show_build_completion(symbol_count)
    puts "⚡ 索引构建完成: #{symbol_count} 个符号"
    puts "💾 保存索引: #{INDEX_FILE}"
    puts "✅ 完成! 用时: #{Time.now - @start_time}秒"
  end

  # 增量更新索引 - 性能优化版
  def update_index
    puts '🔍 检查文件变更...'

    return build_index unless index_files_exist?

    files = find_ruby_files
    file_data = load_existing_file_data

    file_changes = detect_file_changes(files, file_data)

    if no_changes_detected?(file_changes)
      puts '✅ 索引已是最新，无需更新'
      return
    end

    show_change_summary(file_changes)

    symbol_index = update_symbol_index(file_changes, file_data)
    save_updated_index(files, symbol_index, file_changes[:updated_file_data])

    show_update_completion
  end

  # 检查索引文件是否存在
  def index_files_exist?
    File.exist?(INDEX_FILE) && File.exist?(FILES_FILE)
  end

  # 加载现有文件数据
  def load_existing_file_data
    JSON.parse(File.read(FILES_FILE))
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

  # 显示变更摘要
  def show_change_summary(file_changes)
    puts "📝 变更文件: #{file_changes[:changed].length} 个修改, #{file_changes[:new].length} 个新增"
  end

  # 更新符号索引
  def update_symbol_index(file_changes, original_file_data)
    index_data = JSON.parse(File.read(INDEX_FILE))
    symbol_index = index_data['symbols']
    updated_file_data = original_file_data.dup

    remove_deleted_files(symbol_index, updated_file_data, file_changes[:deleted])
    update_changed_files(symbol_index, updated_file_data, file_changes[:changed] + file_changes[:new])

    # Store the updated file data for later saving
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
    files_to_update.each_with_index do |file, index|
      show_progress(index + 1, files_to_update.length, '更新索引')

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
      version: VERSION,
      built_at: Time.now.iso8601,
      total_files: files.length,
      total_symbols: symbol_index.values.flatten.length,
      symbols: symbol_index
    }

    File.write(INDEX_FILE, JSON.pretty_generate(index_data))
    File.write(FILES_FILE, JSON.pretty_generate(updated_file_data))
  end

  # 显示更新完成信息
  def show_update_completion
    puts "✅ 索引更新完成! 用时: #{Time.now - @start_time}秒"
  end

  # ==========================================
  # 符号搜索和显示
  # ==========================================

  # 搜索符号定义
  #
  # 在构建的索引中搜索匹配的符号定义。
  # 支持精确匹配、前缀匹配和类型过滤。
  #
  # 参数:
  #   query - 搜索查询字符串
  #
  # 返回:
  #   Array<Hash> - 匹配的符号结果数组
  #
  # 搜索策略:
  #   1. 精确匹配 - 完全匹配符号名称
  #   2. 前缀匹配 - 匹配以查询开头的符号
  #   3. 类型过滤 - 根据 @options[:type] 过滤结果
  #   4. 去重排序 - 移除重复项并按文件和行号排序
  #
  # 示例:
  #   search("User")        # 精确和前缀匹配
  #   search("create", type: :method)  # 只搜索方法
  def search(query)
    unless File.exist?(INDEX_FILE)
      puts '❌ 索引文件不存在，请先运行 --rebuild 构建索引'
      return []
    end

    # 性能优化：缓存索引加载以避免重复读取
    index_data = load_index_cached
    symbol_index = index_data['symbols']

    results = []

    # 1. 精确匹配 - 最高优先级
    results.concat(symbol_index[query]) if symbol_index[query]

    # 2. 前缀匹配 - 支持模糊查找
    symbol_index.each do |symbol, symbol_list|
      results.concat(symbol_list) if symbol.start_with?(query) && symbol != query
    end

    # 3. 按类型过滤结果
    results.select! { |result| result['type'] == @options[:type].to_s } if @options[:type]

    # 4. 去重并排序确保结果一致性
    results.uniq! { |r| "#{r['file']}:#{r['line']}" }
    results.sort_by! { |r| [r['file'], r['line']] }

    results
  end

  # 性能优化：缓存索引加载
  def load_index_cached
    cache_key = INDEX_FILE
    return @index_cache[cache_key] if @index_cache.key?(cache_key)

    @index_cache[cache_key] = JSON.parse(File.read(INDEX_FILE))
  end

  # ==========================================
  # 缓存和资源管理
  # ==========================================

  # 性能优化：清理缓存
  def clear_cache
    @symbol_cache.clear
    @hash_cache.clear
    @index_cache.clear
    GC.start if GC.respond_to?(:start)
  end

  # 清理资源
  def cleanup
    @thread_pool&.shutdown
    @thread_pool&.wait_for_termination(30)
    clear_cache
  end

  # ==========================================
  # 编辑器集成
  # ==========================================

  # 在 Zed 中打开文件并跳转到指定行
  def open_in_zed(file, line)
    system('zed', "#{file}:#{line}")
  end

  # 显示搜索结果
  def display_results(query, results)
    if results.empty?
      puts "🔍 搜索 \"#{query}\" - 未找到匹配结果"
      return
    end

    puts "🔍 搜索 \"#{query}\" - 找到 #{results.length} 个结果:"
    puts

    results.each_with_index do |result, index|
      class_info = result['class'] && result['class'] != 'null' ? " (#{result['class']})" : ''
      match_type = get_match_type_info(result['name'], query)
      type_info = get_type_description(result['type'])

      puts "#{index + 1}) #{result['file']}:#{result['line']}#{class_info}#{match_type}"
      puts "   #{format_signature(result, result['name'])} [#{type_info}]"
      puts
    end

    if @options[:zed] && !results.empty?
      # 如果指定了 -z 参数，直接跳转到第一个结果
      first_result = results.first
      puts "🚀 在 Zed 中打开: #{first_result['file']}:#{first_result['line']}"
      open_in_zed(first_result['file'], first_result['line'])
    elsif results.length > 1
      print "选择文件跳转 [1-#{results.length}] 或直接回车跳转第一个: "
      choice = $stdin.gets

      choice = if choice.nil? || choice.chomp.empty?
                 '1'
               else
                 choice.chomp
               end

      if choice =~ /^\d+$/ && choice.to_i.between?(1, results.length)
        selected = results[choice.to_i - 1]
        puts "🚀 在 Zed 中打开: #{selected['file']}:#{selected['line']}"
        open_in_zed(selected['file'], selected['line'])
      else
        puts '❌ 无效选择'
      end
    elsif results.length == 1
      puts "🚀 在 Zed 中打开: #{results.first['file']}:#{results.first['line']}"
      open_in_zed(results.first['file'], results.first['line'])
    end
  end

  # 获取类型图标
  def get_type_icon(type)
    icons = {
      'method' => '🔧',
      'class' => '📋',
      'module' => '📦',
      'constant' => '🏷️',
      'scope' => '🎯'
    }
    icons[type] || '❓'
  end

  # 格式化方法签名
  def format_signature(result, symbol_name)
    actual_name = result['name'] || symbol_name
    return "unknown" if actual_name.nil?

    case result['type']
    when 'method'
      full_name = build_full_method_name(result, actual_name)
      "#{full_name}(...)"
    when 'class'
      "class #{actual_name}"
    when 'module'
      "module #{actual_name}"
    when 'constant'
      "#{actual_name} = ..."
    when 'scope'
      "scope :#{actual_name}"
    else
      actual_name.to_s
    end
  end

  # 构建完整方法名
  def build_full_method_name(result, method_name)
    method_name ||= "unknown"

    if result['class']
      class_name = result['class'] || "UnknownClass"
      if result['class_method']
        "#{class_name}.#{method_name}"
      else
        "#{class_name}##{method_name}"
      end
    else
      method_name
    end
  end

  # 获取匹配类型信息
  def get_match_type_info(symbol_name, query)
    return "" if symbol_name.nil?

    if symbol_name == query
      " [exact]"
    elsif symbol_name.start_with?(query)
      " [prefix]"
    else
      ""
    end
  end

  # 获取符号类型描述
  def get_type_description(type)
    descriptions = {
      'method' => 'method',
      'class' => 'class',
      'module' => 'module',
      'constant' => 'constant',
      'scope' => 'scope'
    }
    descriptions[type] || 'unknown'
  end

  # ==========================================
  # 状态监控和进程管理
  # ==========================================

  # 显示索引状态
  def show_status
    puts '📊 索引状态:'

    unless File.exist?(INDEX_FILE) && File.exist?(FILES_FILE) && File.exist?(META_FILE)
      puts '❌ 索引不存在，请先运行 --rebuild 构建索引'
      return
    end

    index_data = load_index_cached
    meta_data = JSON.parse(File.read(META_FILE))

    puts "📁 索引目录: #{INDEX_DIR}"
    puts "📅 构建时间: #{Time.parse(index_data['built_at']).strftime('%Y-%m-%d %H:%M:%S')}"
    puts "📄 文件数量: #{index_data['total_files']}"
    puts "⚡ 符号数量: #{index_data['total_symbols']}"
    puts "💎 Ruby 版本: #{meta_data['ruby_version']}"
    puts "🔧 Parser 版本: #{meta_data['parser_version']}"

    # 显示监控状态
    if File.exist?(PID_FILE)
      pid = File.read(PID_FILE).strip
      if process_running?(pid.to_i)
        puts "👀 文件监控: 运行中 (PID: #{pid})"
      else
        puts '👀 文件监控: 已停止'
        File.delete(PID_FILE)
      end
    else
      puts '👀 文件监控: 未启动'
    end

    # 检查索引是否需要更新
    files = find_ruby_files
    current_files_count = files.length
    indexed_files_count = index_data['total_files']

    if current_files_count != indexed_files_count
      puts '⚠️  文件数量发生变化，建议运行 --update 更新索引'
    else
      # 检查文件修改时间
      files_json = JSON.parse(File.read(FILES_FILE))
      outdated_files = files.select do |file|
        next unless files_json[file]

        File.mtime(file).to_i > files_json[file]['mtime']
      end

      if outdated_files.any?
        puts "⚠️  发现 #{outdated_files.length} 个文件已修改，建议运行 --update 更新索引"
      else
        puts '✅ 索引是最新的'
      end
    end
  end

  # 检查进程是否在运行
  def process_running?(pid)
    Process.getpgid(pid)
    true
  rescue Errno::ESRCH
    false
  end

  # ==========================================
  # 文件监控功能
  # ==========================================

  # 启动文件监控
  def start_watcher
    if File.exist?(PID_FILE)
      pid = File.read(PID_FILE).strip
      if process_running?(pid.to_i)
        puts "❌ 文件监控已在运行中 (PID: #{pid})"
        puts '使用 --stop 停止监控'
        return
      else
        puts '🧹 清理过期的 PID 文件'
        File.delete(PID_FILE)
      end
    end

    # 确保索引存在
    unless File.exist?(INDEX_FILE)
      puts '📥 索引不存在，先构建索引...'
      build_index
    end

    puts '👀 启动文件监控...'
    puts '💡 按 Ctrl+C 停止监控'
    puts "📝 监控目录: #{Dir.pwd}"

    # 保存当前进程 PID
    File.write(PID_FILE, Process.pid.to_s)

    # 设置信号处理
    Signal.trap('INT') do
      puts "\n🛑 收到停止信号，正在关闭监控..."
      @watching = false
      if @listener
        @listener.stop
        @listener = nil
      end
      exit 0
    end

    Signal.trap('TERM') do
      puts "\n🛑 收到终止信号，正在关闭监控..."
      @watching = false
      if @listener
        @listener.stop
        @listener = nil
      end
      exit 0
    end

    @watching = true
    @listener = Listen.to('.',
                          ignore: [%r{\.git/}, %r{node_modules/}, %r{vendor/}, %r{tmp/},
                                   %r{\.symbol_finder/}]) do |modified, added, removed|
      handle_file_changes(modified, added, removed)
    end

    @listener.start
    puts '✅ 文件监控已启动'
    puts "🔄 监控中... (#{Time.now.strftime('%H:%M:%S')})"

    # 保持进程运行
    sleep(1) while @watching
  end

  # 停止文件监控
  def stop_watcher
    if @listener
      @listener.stop
      @listener = nil
    end

    @watching = false

    return unless File.exist?(PID_FILE)

    File.delete(PID_FILE)
    puts '✅ 文件监控已停止'
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

    puts
    puts "📝 检测到文件变更 (#{Time.now.strftime('%H:%M:%S')}):"
    puts "   📝 修改: #{ruby_changes[:modified].length} 个文件"
    puts "   ➕ 新增: #{ruby_changes[:added].length} 个文件"
    puts "   ➖ 删除: #{ruby_changes[:removed].length} 个文件"

    if ruby_changes[:modified].any?
      ruby_changes[:modified].each do |file|
        puts "   📝 #{file}"
      end
    end

    if ruby_changes[:added].any?
      ruby_changes[:added].each do |file|
        puts "   ➕ #{file}"
      end
    end

    if ruby_changes[:removed].any?
      ruby_changes[:removed].each do |file|
        puts "   ➖ #{file}"
      end
    end

    puts '🔄 更新索引...'
    update_index_silent
    puts '✅ 索引更新完成！继续监控...'
  end

  # 静默更新索引（用于监控中）
  def update_index_silent
    return unless File.exist?(INDEX_FILE) && File.exist?(FILES_FILE)

    files = find_ruby_files
    file_data = JSON.parse(File.read(FILES_FILE))
    index_data = JSON.parse(File.read(INDEX_FILE))
    symbol_index = index_data['symbols']

    changed_files = []
    new_files = []

    files.each do |file|
      file_stat = File.stat(file)
      current_data = file_data[file]

      if current_data.nil?
        new_files << file
      elsif current_data['mtime'] != file_stat.mtime.to_i ||
            current_data['size'] != file_stat.size ||
            current_data['hash'] != Digest::MD5.file(file).hexdigest
        changed_files << file
      end
    end

    # 处理删除的文件
    deleted_files = file_data.keys - files

    return if changed_files.empty? && new_files.empty? && deleted_files.empty?

    updated_file_data = file_data.dup

    # 处理删除的文件
    deleted_files.each do |file|
      updated_file_data.delete(file)
      symbol_index.each do |_symbol_name, symbol_list|
        symbol_list.reject! { |symbol| symbol['file'] == file }
      end
      symbol_index.reject! { |_, symbol_list| symbol_list.empty? }
    end

    # 处理新增和修改的文件
    total_files = changed_files + new_files

    total_files.each do |file|
      # 移除该文件的所有符号
      symbol_index.each do |_symbol_name, symbol_list|
        symbol_list.reject! { |symbol| symbol['file'] == file }
      end
      symbol_index.reject! { |_, symbol_list| symbol_list.empty? }

      # 重新解析文件
      file_symbols = extract_symbols_from_file(file)

      file_symbols.each do |symbol|
        name = symbol[:name]
        symbol_index[name] ||= []
        symbol_index[name] << symbol
      end

      # 更新文件信息
      file_stat = File.stat(file)
      updated_file_data[file] = {
        mtime: file_stat.mtime.to_i,
        size: file_stat.size,
        hash: Digest::MD5.file(file).hexdigest
      }
    end

    # 保存更新后的索引
    index_data['built_at'] = Time.now.iso8601
    index_data['total_files'] = files.length
    index_data['total_symbols'] = symbol_index.values.flatten.length
    index_data['symbols'] = symbol_index

    File.write(INDEX_FILE, JSON.pretty_generate(index_data))
    File.write(FILES_FILE, JSON.pretty_generate(updated_file_data))
  end

  # 停止已存在的监控进程
  def stop_existing_watcher
    unless File.exist?(PID_FILE)
      puts '❌ 没有运行中的文件监控'
      return
    end

    pid = File.read(PID_FILE).strip
    if process_running?(pid.to_i)
      begin
        Process.kill('TERM', pid.to_i)
        puts "🛑 已发送停止信号给进程 #{pid}"

        # 等待进程结束
        5.times do
          sleep(1)
          next if process_running?(pid.to_i)

          puts '✅ 文件监控已停止'
          File.delete(PID_FILE)
          return
        end

        # 强制终止
        puts '⚠️  强制终止进程...'
        Process.kill('KILL', pid.to_i)
        File.delete(PID_FILE)
        puts '✅ 文件监控已强制停止'
      rescue Errno::ESRCH
        puts '🧹 进程已不存在，清理 PID 文件'
        File.delete(PID_FILE)
      rescue StandardError => e
        puts "❌ 停止进程失败: #{e.message}"
      end
    else
      puts '🧹 进程不存在，清理 PID 文件'
      File.delete(PID_FILE)
    end
  end

  # ==========================================
  # 主程序执行和控制流程
  # ==========================================

  public

  # 主执行方法
  def run(args)
    @start_time = Time.now

    begin
      parse_options(args)

      if @options[:rebuild]
        build_index
      elsif @options[:update]
        update_index
      elsif @options[:status]
        show_status
      elsif @options[:watch]
        start_watcher
      elsif @options[:stop_watcher]
        stop_existing_watcher
      elsif args.empty?
        puts '❌ 请提供搜索关键词或使用 --help 查看帮助'
        exit 1
      else
        query = args.first
        results = search(query)
        display_results(query, results)
      end
    rescue Interrupt
      puts "\n❌ 操作被用户中断"
      exit 1
    rescue StandardError => e
      puts "❌ 执行出错: #{e.message}"
      puts "❌ 详细信息: #{e.backtrace.join("\n")}" if @options[:verbose]
      exit 1
    ensure
      # 性能优化：确保清理资源
      cleanup
    end
  end

  # 解析命令行参数
  def parse_options(args)
    parser = create_option_parser
    parse_with_error_handling(parser, args)
  end

  private

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
    opts.banner = '用法: ruby symbol_finder.rb <查询> [选项]'
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
    opts.on('-h', '--help', '显示帮助信息') do
      display_help(opts)
      exit 0
    end
  end

  # 带错误处理的参数解析
  def parse_with_error_handling(parser, args)
    parser.parse!(args)
  rescue OptionParser::InvalidOption => e
    handle_parse_error(e)
  end

  # 处理解析错误
  def handle_parse_error(error)
    puts "❌ 无效选项: #{error.message}"
    puts '使用 --help 查看帮助信息'
    exit 1
  end

  # 显示帮助信息
  def display_help(parser)
    puts parser
    puts ''
    display_usage_examples
    display_zed_integration
    display_monitoring_info
  end

  # 显示使用示例
  def display_usage_examples
    puts '示例:'
    puts '  ruby symbol_finder.rb "create_user"              # 基本搜索'
    puts '  ruby symbol_finder.rb "create_user" -z           # 搜索并在 Zed 中打开'
    puts '  ruby symbol_finder.rb -t method "create"        # 只搜索方法'
    puts '  ruby symbol_finder.rb --rebuild                  # 重建索引'
    puts '  ruby symbol_finder.rb --update                   # 增量更新索引'
    puts '  ruby symbol_finder.rb --status                   # 显示索引状态'
    puts '  ruby symbol_finder.rb --watch                    # 启动文件监控'
    puts '  ruby symbol_finder.rb --stop                     # 停止文件监控'
    puts ''
  end

  # 显示 Zed 集成信息
  def display_zed_integration
    puts 'Zed 集成:'
    puts '  在 .zed/tasks.json 中添加:'
    puts '  {'
    puts '    "label": "Symbol Finder",'
    puts '    "command": "ruby",'
    puts '    "args": ["symbol_finder.rb", "-z", "{selection}"],'
    puts '    "cwd": "{projectRoot}"'
    puts '  }'
    puts ''
  end

  # 显示文件监控信息
  def display_monitoring_info
    puts '文件监控:'
    puts '  启动监控后，当 .rb 文件发生变化时自动更新索引'
    puts '  监控进程在后台运行，通过 --stop 命令停止'
  end
end

# 主程序入口
if __FILE__ == $0
  finder = SymbolFinder.new
  finder.run(ARGV)
end
