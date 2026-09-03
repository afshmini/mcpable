# frozen_string_literal: true

require "mcpable"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  config.before { Mcpable.reset! }
end
