require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'

Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "ram"
  gem.homepage = "https://sites.google.com/a/rallydev.com/the-wrack-zone/home/ruby-scripts"
  gem.license = "MIT"
  gem.summary = %Q{Utility to Migrate Rally Artifacts}
  gem.description = %Q{Utility to Migrate Rally Artifacts}
  gem.email = "mwilliams@rallydev.com"
  gem.authors = ["Colin O'Brien, Mark Williams"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)

	# gem.add_runtime_dependency 'multi_json', '~> 1.10.1'
	# gem.add_runtime_dependency 'i18n', "~> 0.6.0"
	# gem.add_runtime_dependency 'rally_api', ">= 0.5.2"
    #
	# ['activesupport', 'activemodel', 'activerecord', 'actionpack'].each {|d| gem.add_runtime_dependency d, "~> 4.1.2"}
	# ['require_all', 'sqlite3', 'rake', 'trollop', 'rest-client', 'rainbow', 'json_pure', 'events', 'options', "highline"].each do |d|
	#     gem.add_runtime_dependency d
	# end
	
	gem.files.include 'example_config.rb'
	gem.files.include Dir.glob('lib/**/*.*')
	gem.files.include 'VERSION'
	
	gem.executables = ['ram']
  #gem.add_development_dependency 'rspec', '> 1.2.3'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

require 'rake/packagetask'
version = File.exist?('VERSION') ? File.read('VERSION') : ""
Rake::PackageTask.new('ram', version) do |p|
	p.need_tar_gz = true
	
	p.package_files.include "bin/**/*.*"
	p.package_files.include "lib/**/*.rb"
	p.package_files.include "example_config.rb"
	p.package_files.include "VERSION"
end
=begin
require 'rcov/rcovtask'
Rcov::RcovTask.new do |test|
  test.libs << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test
=end

=begin
require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "RAM #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
=end

require 'fileutils'
task :latest do
  FileUtils.copy "./pkg/ram-#{version}.gem", "./ram-latest.gem"
end
