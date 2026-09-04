# frozen_string_literal: true

module Mcpable
  module Dsl
    class ResourceBuilder
      class << self
        attr_accessor :type_inferrer, :source_factory
      end

      DEFAULT_PER_PAGE = 25
      SUPPORTED_ACTIONS = %i[list show].freeze

      def initialize(target)
        @target = target
        @base_name = Naming.underscore(target.name.to_s.split("::").last)
        @description = nil
        @attributes = []
        @conditional_attributes = []
        @filters = []
        @source = nil
        @policy = nil
        @actions = %i[list show]
        @order_whitelist = nil
        @per_page = DEFAULT_PER_PAGE
        @profiles = [:default]
        @annotations = { read_only: true }
      end

      def name(value) = @base_name = Naming.underscore(value.to_s)

      def description(value) = @description = value

      def attributes(*values) = @attributes = values.flatten.map(&:to_sym)

      def attribute(name, **options)
        condition = options[:if]
        return @attributes |= [name.to_sym] if condition.nil?

        @conditional_attributes << { name: name.to_sym, condition: condition }
      end

      def filter(name, type: nil, match: nil, range: false, required: false, description: nil,
                enum: nil, scope: false)
        @filters << {
          name: name.to_sym,
          type: type,
          match: match,
          range: range,
          required: required,
          description: description,
          enum: enum,
          scope: scope
        }
      end

      def source(value) = @source = value

      def order_whitelist(*values) = @order_whitelist = values.flatten.map(&:to_sym)

      def policy(value) = @policy = value

      def actions(*values) = @actions = values.flatten.map(&:to_sym)

      def default_page_size(value) = @per_page = Integer(value)

      def profiles(*values) = @profiles = values.flatten.map(&:to_sym)

      def annotations(**values) = @annotations = @annotations.merge(values)

      def compile
        validate_actions!
        validate_conditional_attributes!

        @source ||= build_default_source
        raise ArgumentError, "#{@target} needs a source" if @source.nil?

        definitions = []
        definitions << compile_list if @actions.include?(:list)
        definitions << compile_show if @actions.include?(:show)
        definitions
      end

      private

      def validate_conditional_attributes!
        hidden = @conditional_attributes.map { |a| a[:name] }
        return if hidden.empty?

        leaked = @filters.map { |f| f[:name] } & hidden
        return if leaked.empty?

        raise ArgumentError,
              "#{@target} filters on conditionally visible attributes: #{leaked.join(', ')} " \
              "(a filter would expose them to callers that cannot read them)"
      end

      def validate_actions!
        raise ArgumentError, "#{@target} declares no actions" if @actions.empty?

        unsupported = @actions - SUPPORTED_ACTIONS
        return if unsupported.empty?

        raise ArgumentError,
              "#{@target} declares unsupported actions: #{unsupported.join(', ')} " \
              "(supported: #{SUPPORTED_ACTIONS.join(', ')}; write actions are not implemented yet)"
      end

      def build_default_source
        factory = self.class.source_factory
        factory&.call(@target, order_whitelist: @order_whitelist || @attributes)
      end

      def list_name = "#{Naming.pluralize(@base_name)}_list"

      def show_name = "#{Naming.pluralize(@base_name)}_show"

      def compile_list
        arguments = list_arguments
        attributes = @attributes
        conditional = @conditional_attributes
        source_ref = @source
        per_page = @per_page

        handler = lambda do |ctx|
          visible = ResourceBuilder.visible_attributes(attributes, conditional, ctx)
          source = ResourceBuilder.resolve_source(source_ref)
          filters = arguments.select(&:filter?).to_h { |a| [a, ctx.args[a.name]] }
          page = source.fetch(
            filters: filters,
            scope: ctx.scope,
            page: ctx.args[:page] || 1,
            per_page: ctx.args[:per_page] || per_page,
            order: ctx.args[:order]
          )
          Result.ok(
            records: page.records.map { |r| ResourceBuilder.serialize(r, visible) },
            total: page.total,
            page: page.page,
            per_page: page.per_page
          )
        end

        Definition.build(
          name: list_name,
          description: @description,
          arguments: arguments,
          handler: handler,
          annotations: @annotations,
          profiles: @profiles,
          metadata: {
            model: @target,
            action: :list,
            policy: @policy,
            per_page: @per_page,
            paginated: true
          }
        )
      end

      def compile_show
        attributes = @attributes
        conditional = @conditional_attributes
        source_ref = @source

        handler = lambda do |ctx|
          source = ResourceBuilder.resolve_source(source_ref)
          record = source.find(ctx.args[:id], scope: ctx.scope)
          next Result.fail("not found") if record.nil?

          visible = ResourceBuilder.visible_attributes(attributes, conditional, ctx)
          Result.ok(ResourceBuilder.serialize(record, visible))
        end

        Definition.build(
          name: show_name,
          description: @description,
          arguments: [Argument.build(:id, type: :integer, required: true, description: "Record id.")],
          handler: handler,
          annotations: @annotations,
          profiles: @profiles,
          metadata: {
            model: @target,
            action: :show,
            policy: @policy
          }
        )
      end

      def list_arguments
        @filters.flat_map { |spec| expand_filter(spec) }
      end

      def expand_filter(spec)
        type, enum = resolve_type(spec)

        if spec[:range]
          [
            build_argument("#{spec[:name]}_from", spec, type, enum, :range_from),
            build_argument("#{spec[:name]}_to", spec, type, enum, :range_to)
          ]
        elsif spec[:scope]
          [build_argument(spec[:name], spec, type, enum, :scope)]
        elsif spec[:match] == :partial
          [build_argument(spec[:name], spec, type, enum, :match)]
        else
          [build_argument(spec[:name], spec, type, enum, :eq)]
        end
      end

      def build_argument(name, spec, type, enum, kind)
        Argument.build(
          name,
          type: type,
          required: kind == :eq ? spec[:required] : false,
          description: spec[:description],
          enum: enum,
          filter: { kind: kind, target: spec[:name] }
        )
      end

      def resolve_type(spec)
        return [spec[:type].to_sym, spec[:enum]] if spec[:type]

        inferrer = self.class.type_inferrer
        inferred = inferrer&.call(@target, spec[:name])
        raise ArgumentError, "filter :#{spec[:name]} needs type:" if inferred.nil?

        [inferred[:type], spec[:enum] || inferred[:enum]]
      end

      def self.resolve_source(source_ref)
        return source_ref if source_ref.respond_to?(:fetch)

        source_ref.respond_to?(:call) ? source_ref.call : source_ref
      end

      def self.visible_attributes(base, conditional, ctx)
        return base if conditional.empty?

        base + conditional.select { |a| visible?(a[:condition], ctx) }.map { |a| a[:name] }
      end

      def self.visible?(condition, ctx)
        case condition
        when Symbol then ctx.user.respond_to?(condition) && !!ctx.user.public_send(condition)
        else condition.arity.zero? ? !!condition.call : !!condition.call(ctx)
        end
      end

      def self.serialize(record, attributes)
        attributes.each_with_object({}) do |attribute, out|
          out[attribute] = read(record, attribute)
        end
      end

      def self.read(record, attribute)
        return record.public_send(attribute) if record.respond_to?(attribute)
        return record[attribute] if record.respond_to?(:[])

        nil
      end
    end
  end
end
