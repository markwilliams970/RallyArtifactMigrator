source "http://rubygems.org"
# Add dependencies required to use your gem here.
# Example:
#   gem "activesupport", ">= 2.3.5"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "shoulda", ">= 0"
  gem "bundler", "~> 1.6.2"
  gem "jeweler", "~> 2.0.1"
#  gem "rcov", ">= 0"
#  gem "rspec", ">= 2"
end

gem "rally_api", ">= 1.0.0"
gem "multi_json", '~> 1.10.1'
gem 'i18n', "~> 0.6.0"

['activesupport', 'activemodel', 'activerecord', 'actionpack'].each {|d| gem d, "~> 4.1.2"}
['require_all', 'sqlite3', 'rake', 'trollop', 'httpclient', 'rainbow', 'json_pure', 'events', 'options', "highline"].each do |d|
  gem d
end
