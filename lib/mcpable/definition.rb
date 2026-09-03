# frozen_string_literal: true

module Mcpable
  Definition = Data.define(
    :name,
    :description,
    :arguments,
    :handler,
    :annotations,
    :profiles,
    :metadata
  ) do
    def self.build(name:, description: nil, arguments: [], handler: nil, annotations: {},
                   profiles: [:default], metadata: {})
      new(
        name: name.to_s,
        description: description,
        arguments: arguments,
        handler: handler,
        annotations: annotations,
        profiles: profiles,
        metadata: metadata
      )
    end

    def read_only? = annotations.fetch(:read_only, true)

    def destructive? = annotations.fetch(:destructive, false)

    def open_world? = annotations.fetch(:open_world, false)

    def profile?(profile) = profiles.include?(profile)

    def argument(name) = arguments.find { |a| a.name == name.to_sym }
  end
end
