# frozen_string_literal: true

RSpec.describe Mcpable::Registry do
  subject(:registry) { described_class.new }

  def definition(name, profiles: [:default])
    Mcpable::Definition.build(
      name: name,
      description: "d",
      handler: ->(_ctx) { Mcpable::Result.ok(name) },
      profiles: profiles
    )
  end

  it "registers and fetches a definition" do
    registry.register(definition("a_list"))
    expect(registry.fetch("a_list").name).to eq("a_list")
  end

  it "fetches by symbol" do
    registry.register(definition("a_list"))
    expect(registry.fetch(:a_list).name).to eq("a_list")
  end

  it "raises on duplicate names" do
    registry.register(definition("a_list"))
    expect { registry.register(definition("a_list")) }
      .to raise_error(Mcpable::DuplicateToolError, /a_list/)
  end

  it "raises on unknown names" do
    expect { registry.fetch("nope") }.to raise_error(Mcpable::UnknownToolError, /nope/)
  end

  it "filters by profile" do
    registry.register(definition("a_list", profiles: [:default]))
    registry.register(definition("b_list", profiles: [:admin]))
    registry.register(definition("c_list", profiles: %i[default admin]))

    expect(registry.for_profile(:default).map(&:name)).to contain_exactly("a_list", "c_list")
    expect(registry.for_profile(:admin).map(&:name)).to contain_exactly("b_list", "c_list")
  end

  it "lists names" do
    registry.register(definition("a_list"))
    registry.register(definition("b_list"))
    expect(registry.names).to eq(%w[a_list b_list])
  end

  it "clears everything on reset!" do
    registry.register(definition("a_list"))
    registry.reset!
    expect(registry.names).to be_empty
  end
end
