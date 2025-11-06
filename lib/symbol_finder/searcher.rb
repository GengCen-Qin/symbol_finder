# frozen_string_literal: true

require 'json'

module SymbolFinder
  # 负责符号搜索和结果显示的类
  #
  # 主要功能：
  # - 高效的符号搜索
  # - 结果过滤和排序
  # - 编辑器集成
  # - 结果格式化显示
  class Searcher
    attr_reader :options

    # 初始化搜索器
    def initialize(options = {})
      @options = {
        type: nil,    # 符号类型过滤
        zed: false,   # Zed 编辑器集成
        verbose: false
      }.merge(options)

      @index_cache = {}
    end

    # 搜索符号定义
    def search(query)
      unless File.exist?(SymbolFinder::INDEX_FILE)
        puts '❌ 索引文件不存在，请先运行 --rebuild 构建索引'
        return []
      end

      index_data = load_index_cached
      symbol_index = index_data['symbols']

      results = []

      # 1. 精确匹配
      results.concat(symbol_index[query]) if symbol_index[query]

      # 2. 前缀匹配
      symbol_index.each do |symbol, symbol_list|
        results.concat(symbol_list) if symbol.start_with?(query) && symbol != query
      end

      # 3. 按类型过滤结果
      results.select! { |result| result['type'] == @options[:type].to_s } if @options[:type]

      # 4. 去重并排序
      results.uniq! { |r| "#{r['file']}:#{r['line']}" }
      results.sort_by! { |r| [r['file'], r['line']] }

      results
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

      handle_editor_integration(results)
    end

    # 显示索引状态
    def show_status
      puts '📊 索引状态:'

      unless index_files_exist?
        puts '❌ 索引不存在，请先运行 --rebuild 构建索引'
        return
      end

      index_data = load_index_cached
      meta_data = JSON.parse(File.read(SymbolFinder::META_FILE))

      puts "📁 索引目录: #{SymbolFinder::INDEX_DIR}"
      puts "📅 构建时间: #{Time.parse(index_data['built_at']).strftime('%Y-%m-%d %H:%M:%S')}"
      puts "📄 文件数量: #{index_data['total_files']}"
      puts "⚡ 符号数量: #{index_data['total_symbols']}"
      puts "💎 Ruby 版本: #{meta_data['ruby_version']}"
      puts "🔧 Parser 版本: #{meta_data['parser_version']}"

      # 显示监控状态
      show_watcher_status

      # 检查索引是否需要更新
      check_index_status(index_data)
    end

    private

    # 缓存索引加载
    def load_index_cached
      cache_key = SymbolFinder::INDEX_FILE
      return @index_cache[cache_key] if @index_cache.key?(cache_key)

      @index_cache[cache_key] = JSON.parse(File.read(SymbolFinder::INDEX_FILE))
    end

    # 处理编辑器集成
    def handle_editor_integration(results)
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

    # 在 Zed 中打开文件并跳转到指定行
    def open_in_zed(file, line)
      system('zed', "#{file}:#{line}")
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

    # 检查索引文件是否存在
    def index_files_exist?
      File.exist?(SymbolFinder::INDEX_FILE) &&
        File.exist?(SymbolFinder::FILES_FILE) &&
        File.exist?(SymbolFinder::META_FILE)
    end

    # 显示监控状态
    def show_watcher_status
      if File.exist?(SymbolFinder::PID_FILE)
        pid = File.read(SymbolFinder::PID_FILE).strip
        if SymbolFinder.process_running?(pid.to_i)
          puts "👀 文件监控: 运行中 (PID: #{pid})"
        else
          puts '👀 文件监控: 已停止'
          File.delete(SymbolFinder::PID_FILE)
        end
      else
        puts '👀 文件监控: 未启动'
      end
    end

    # 检查索引状态
    def check_index_status(index_data)
      files = Dir.glob(SymbolFinder::RUBY_FILE_PATTERN).reject { |file| file.match?(SymbolFinder::FILE_FILTER_REGEX) }
      current_files_count = files.length
      indexed_files_count = index_data['total_files']

      if current_files_count != indexed_files_count
        puts '⚠️  文件数量发生变化，建议运行 --update 更新索引'
      else
        # 检查文件修改时间
        files_json = JSON.parse(File.read(SymbolFinder::FILES_FILE))
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
  end
end