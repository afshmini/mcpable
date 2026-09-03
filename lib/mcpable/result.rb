# frozen_string_literal: true

module Mcpable
  Result = Data.define(:status, :payload, :error) do
    def self.ok(payload) = new(status: :ok, payload: payload, error: nil)

    def self.deny(msg) = new(status: :denied, payload: nil, error: msg)

    def self.fail(msg) = new(status: :error, payload: nil, error: msg)

    def ok? = status == :ok

    def denied? = status == :denied

    def error? = status == :error
  end
end
