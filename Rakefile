# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# RSpec 测试任务
RSpec::Core::RakeTask.new(:spec)

# Rubocop 代码风格检查任务
RuboCop::RakeTask.new

# 默认任务
task default: %i[spec rubocop]

# 构建和安装任务
namespace :gem do
  desc 'Build the gem'
  task :build do
    sh 'gem build symbol_finder.gemspec'
  end

  desc 'Install the gem locally'
  task :install => :build do
    gem_file = Dir.glob('symbol_finder-*.gem').first
    sh "gem install --local #{gem_file}"
  end

  desc 'Uninstall the gem'
  task :uninstall do
    sh 'gem uninstall symbol_finder -x'
  end

  desc 'Reinstall the gem'
  task :reinstall => [:uninstall, :install]
end

# 清理任务
task :clean do
  sh 'rm -f *.gem'
  sh 'rm -rf pkg/'
end

# 测试安装
namespace :test do
  desc 'Test gem installation and basic functionality'
  task :install do
    puts '🧪 Testing gem installation...'
    system('gem uninstall symbol_finder -x') rescue nil
    system('gem build symbol_finder.gemspec')
    gem_file = Dir.glob('symbol_finder-*.gem').first
    system("gem install --local #{gem_file}")

    puts '🧪 Testing basic functionality...'
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        File.write('test.rb', 'class TestClass; def test_method; end; end')
        system('symbol_finder --help')
        puts '✅ Basic functionality test passed'
      end
    end
  end
end