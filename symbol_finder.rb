#!/usr/bin/env ruby
# frozen_string_literal: true

# 添加 lib 目录到加载路径
$LOAD_PATH.unshift(File.expand_path('./lib', __dir__))

require 'symbol_finder'

# 检查依赖并安装缺失的 gem
begin
  SymbolFinder.check_dependencies!
rescue LoadError => e
  missing_gem = e.message.match(/gem\s+(\w+)/)
  if missing_gem
    gem_name = missing_gem[1]
    puts "🔧 正在安装缺失的依赖: #{gem_name}"
    system("gem install #{gem_name}")
    puts "✅ #{gem_name} 安装完成，正在重新启动..."
    exec(File.expand_path(__FILE__), *ARGV)
  else
    puts "❌ 依赖检查失败: #{e.message}"
    puts "请手动安装依赖: gem install symbol_finder"
    exit 1
  end
end

# 创建并运行 CLI
cli = SymbolFinder::CLI.new
cli.run(ARGV)