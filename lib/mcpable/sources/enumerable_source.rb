# frozen_string_literal: true

module Mcpable
  module Sources
    class EnumerableSource < Ports::Source
      DEFAULT_PER_PAGE = 25

      def fetch(filters:, scope: nil, page: nil, per_page: nil, order: nil)
        records = apply_scope(resolve_base, scope)
        records = apply_filters(records, filters)
        records = apply_order(records, order)

        total = records.size
        page = normalize_page(page)
        per_page = normalize_per_page(per_page)

        Page.new(
          records: records.drop((page - 1) * per_page).take(per_page),
          total: total,
          page: page,
          per_page: per_page
        )
      end

      def find(id, scope: nil)
        records = apply_scope(resolve_base, scope)
        records.find { |record| read(record, :id).to_s == id.to_s }
      end

      private

      def resolve_base
        resolved = base.respond_to?(:call) ? base.call : base
        resolved.to_a
      end

      def apply_scope(records, scope)
        return records if scope.nil?
        raise Error, "scope must be Enumerable" unless scope.is_a?(Enumerable)

        records & scope.to_a
      end

      def apply_filters(records, filters)
        (filters || {}).reduce(records) do |acc, (argument, value)|
          apply_filter(acc, argument, value)
        end
      end

      def apply_filter(records, argument, value)
        return records if value.nil?

        target = argument.filter_target || argument.name

        case argument.filter_kind
        when :eq then records.select { |r| read(r, target) == value }
        when :match then records.select { |r| read(r, target).to_s.downcase.include?(value.to_s.downcase) }
        when :range_from then records.select { |r| comparable?(read(r, target), value) && read(r, target) >= value }
        when :range_to then records.select { |r| comparable?(read(r, target), value) && read(r, target) <= value }
        when :scope then records
        else records
        end
      end

      def comparable?(left, right)
        !left.nil? && left.respond_to?(:<=>) && !(left <=> right).nil?
      end

      def apply_order(records, order)
        return records if order.nil? || order.to_s.empty?

        raw = order.to_s
        desc = raw.start_with?("-")
        attribute = desc ? raw[1..] : raw
        sorted = records.sort_by { |r| read(r, attribute) }
        desc ? sorted.reverse : sorted
      end

      def normalize_page(page)
        value = page.to_i
        value < 1 ? 1 : value
      end

      def normalize_per_page(per_page)
        value = per_page.to_i
        value < 1 ? DEFAULT_PER_PAGE : value
      end

      def read(record, attribute)
        name = attribute.to_sym
        return record.public_send(name) if record.respond_to?(name)
        return record[name] if record.respond_to?(:[]) && record.respond_to?(:key?) && record.key?(name)
        return record[name.to_s] if record.respond_to?(:[]) && record.respond_to?(:key?) && record.key?(name.to_s)

        nil
      end
    end
  end
end
