# frozen_string_literal: true

module Mcpable
  module Ports
    class Source
      Page = Data.define(:records, :total, :page, :per_page)

      attr_reader :base

      def initialize(base)
        @base = base
      end

      def fetch(filters:, scope:, page:, per_page:, order:)
        raise NotImplementedError, "#{self.class}#fetch"
      end

      def find(id, scope:)
        raise NotImplementedError, "#{self.class}#find"
      end
    end
  end
end
