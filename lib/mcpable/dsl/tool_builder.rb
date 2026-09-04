# frozen_string_literal: true

module Mcpable
  module Dsl
    class ToolBuilder
      def initialize(target)
        @target = target
        @name = default_name(target)
        @description = nil
        @arguments = []
        @annotations = {}
        @profiles = [:default]
        @metadata = {}
      end

      def name(value) = @name = value.to_s

      def description(value) = @description = value

      def argument(name, type, required: false, description: nil, enum: nil)
        @arguments << Argument.build(
          name,
          type: type,
          required: required,
          description: description,
          enum: enum
        )
      end

      def annotations(**values) = @annotations = @annotations.merge(values)

      def profiles(*values) = @profiles = values.flatten.map(&:to_sym)

      def metadata(**values) = @metadata = @metadata.merge(values)

      def compile
        target = @target
        argument_names = @arguments.map(&:name)

        handler = lambda do |ctx|
          call_args = ctx.args.slice(*argument_names)
          instance = target.new
          instance.mcp_call = ctx if instance.respond_to?(:mcp_call=)
          value = instance.call(**call_args)
          value.is_a?(Result) ? value : Result.ok(value)
        end

        Definition.build(
          name: @name,
          description: @description,
          arguments: @arguments,
          handler: handler,
          annotations: @annotations,
          profiles: @profiles,
          metadata: @metadata
        )
      end

      private

      def default_name(target)
        Naming.underscore(target.name.to_s.gsub("::", "_"))
      end
    end
  end
end
