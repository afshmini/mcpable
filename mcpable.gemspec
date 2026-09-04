# frozen_string_literal: true

require_relative "lib/mcpable/version"

Gem::Specification.new do |spec|
  spec.name = "mcpable"
  spec.version = Mcpable::VERSION
  spec.authors = ["Afshin"]

  spec.summary = "Expose Ruby objects and Rails models as MCP tools."
  spec.description = "Mcpable turns plain Ruby classes and Rails models into Model Context " \
                     "Protocol tools through a declarative DSL, a middleware pipeline and " \
                     "pluggable source, schema and transport ports."
  spec.license = "MIT"
  spec.homepage = "https://github.com/afshmini/mcpable"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "app/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "mcp", ">= 1.0", "< 2.0"

  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
