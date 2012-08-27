source "http://rubygems.org"
# Add dependencies required to use your gem here.
# Example:
#   gem "activesupport", ">= 2.3.5"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "shoulda", ">= 0"
  gem "bundler", "~> 1.1.0"
  gem "jeweler", "~> 1.8.4"
#  gem "rcov", ">= 0"
#  gem "rspec", ">= 2"
end

gem "rally_api", "> 0.5"
gem "multi_json", '~> 1.0'
gem 'i18n', "~> 0.6.0"

['activesupport', 'activemodel', 'activerecord', 'actionpack'].each {|d| gem d, "~> 3.1.0"}
['require_all', 'sqlite3', 'rake', 'trollop', 'rest-client', 'rainbow', 'json_pure', 'events', 'fastercsv', 'options', "highline"].each do |d|
  gem d
end
