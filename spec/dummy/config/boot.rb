require 'rubygems'
gemfile = File.expand_path('../../../Gemfile', __dir__)

if File.exist?(gemfile)
  ENV['BUNDLE_GEMFILE'] = gemfile
  require 'bundler'
  Bundler.setup
end

$:.unshift File.expand_path('../../../lib', __dir__)

require 'logger' # Fix concurrent-ruby removing logger dependency which Rails itself does not have
