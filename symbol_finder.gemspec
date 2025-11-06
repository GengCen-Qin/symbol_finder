Gem::Specification.new do |spec|
  spec.name          = "symbol_finder"
  spec.version       = "1.0.0"
  spec.authors       = ["lucas.qin"]
  spec.email         = ["464815411@qq.com"]
  spec.summary       = "High-performance Ruby symbol search tool for Rails projects"
  spec.description   = <<-DESC
    SymbolFinder is a high-performance symbol search tool designed specifically for Rails projects.
    It provides millisecond-level search capabilities, real-time file monitoring, and seamless
    editor integration. Features include:

    - ⚡ Fast symbol search with pre-built indexing
    - 📁 Project-local indexing for easy management
    - 🔍 Support for methods, classes, modules, constants, and Rails scopes
    - 👀 Real-time file monitoring with automatic index updates
    - 🔗 Zed editor integration for direct navigation
    - 📊 Status monitoring and performance metrics
    - 🚀 Concurrent processing for optimal performance
  DESC
  spec.homepage      = "https://github.com/GengCen-Qin"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.5.0"

  # 核心依赖
  spec.add_dependency "parser", ">= 3.0", "< 4.0"
  spec.add_dependency "listen", ">= 3.0", "< 4.0"
  spec.add_dependency "concurrent-ruby", ">= 1.0", "< 2.0"

  # 开发依赖
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "bundler", "~> 2.0"

  # 指定需要包含的文件
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end + [
    "lib/symbol_finder.rb",
    "lib/symbol_finder/index_builder.rb",
    "lib/symbol_finder/searcher.rb",
    "lib/symbol_finder/watcher.rb",
    "lib/symbol_finder/cli.rb",
    "lib/symbol_finder/version.rb",
    "exe/symbol_finder"
  ]

  # 可执行文件
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  # 加载路径
  spec.require_paths = ["lib"]

  # 元数据
  spec.metadata = {
    "homepage_uri"      => "https://github.com/symbolfinder/symbol_finder",
    "documentation_uri" => "https://github.com/symbolfinder/symbol_finder#readme",
    "source_code_uri"   => "https://github.com/symbolfinder/symbol_finder",
    "bug_tracker_uri"   => "https://github.com/symbolfinder/symbol_finder/issues",
    "changelog_uri"     => "https://github.com/symbolfinder/symbol_finder/blob/main/CHANGELOG.md"
  }
end