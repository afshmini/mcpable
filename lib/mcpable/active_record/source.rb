# frozen_string_literal: true

module Mcpable
  module ActiveRecord
    class Source < Ports::Source
      DEFAULT_PER_PAGE = 25

      attr_reader :order_whitelist

      def self.supports?(model)
        model.respond_to?(:all) && model.respond_to?(:arel_table) && model.respond_to?(:columns_hash)
      end

      def initialize(base, order_whitelist: [])
        super(base)
        @order_whitelist = order_whitelist.map(&:to_s)
      end

      def fetch(filters:, scope: nil, page: nil, per_page: nil, order: nil)
        relation = apply_scope(resolve_base, scope)
        relation = apply_filters(relation, filters)
        relation = apply_order(relation, order)

        total = relation.count
        page = normalize_page(page)
        per_page = normalize_per_page(per_page)

        Page.new(
          records: relation.offset((page - 1) * per_page).limit(per_page).to_a,
          total: total,
          page: page,
          per_page: per_page
        )
      end

      def find(id, scope: nil)
        apply_scope(resolve_base, scope).find_by(id: id)
      end

      private

      def resolve_base
        resolved = base.respond_to?(:call) ? base.call : base
        resolved.respond_to?(:all) ? resolved.all : resolved
      end

      def apply_scope(relation, scope)
        scope.nil? ? relation : relation.merge(scope)
      end

      def apply_filters(relation, filters)
        (filters || {}).reduce(relation) do |acc, (argument, value)|
          apply_filter(acc, argument, value)
        end
      end

      def apply_filter(relation, argument, value)
        return relation if value.nil?

        target = (argument.filter_target || argument.name).to_s

        case argument.filter_kind
        when :eq then relation.where(target => value)
        when :match then apply_match(relation, target, value)
        when :range_from then relation.where(arel_column(relation, target).gteq(value))
        when :range_to then relation.where(arel_column(relation, target).lteq(value))
        when :scope then value ? relation.public_send(target) : relation
        else relation
        end
      end

      def apply_match(relation, target, value)
        pattern = "%#{escape_like(relation, value.to_s)}%"
        relation.where(arel_column(relation, target).matches(pattern, nil, false))
      end

      def arel_column(relation, target)
        relation.klass.arel_table[target]
      end

      def escape_like(relation, value)
        model = relation.klass
        model.respond_to?(:sanitize_sql_like) ? model.sanitize_sql_like(value) : value
      end

      def apply_order(relation, order)
        return relation if order.nil? || order.to_s.empty?

        raw = order.to_s
        desc = raw.start_with?("-")
        column = desc ? raw[1..] : raw
        return relation unless order_whitelist.include?(column)

        relation.order(column => desc ? :desc : :asc)
      end

      def normalize_page(page)
        value = page.to_i
        value < 1 ? 1 : value
      end

      def normalize_per_page(per_page)
        value = per_page.to_i
        value < 1 ? DEFAULT_PER_PAGE : value
      end
    end
  end
end
