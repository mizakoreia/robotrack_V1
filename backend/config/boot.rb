# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
unless ENV['RAILS_ENV'] == 'test'
  require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
end

# Unfreeze autoload paths for test/engines to safely mutate during initialization
begin
  require 'active_support/dependencies'
  ActiveSupport::Dependencies.autoload_paths = ActiveSupport::Dependencies.autoload_paths.dup
  ActiveSupport::Dependencies.autoload_once_paths = ActiveSupport::Dependencies.autoload_once_paths.dup
rescue StandardError
end
