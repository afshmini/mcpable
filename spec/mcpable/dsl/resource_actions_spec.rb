# frozen_string_literal: true

RSpec.describe Mcpable::Dsl::ResourceBuilder do
  WidgetRecord = Struct.new(:id, :name, keyword_init: true) unless defined?(WidgetRecord)

  def builder(*actions, skip_actions: false)
    described_class.new(WidgetRecord).tap do |b|
      b.name "widget"
      b.description "Widgets."
      b.attributes :id, :name
      b.source Mcpable::Sources::EnumerableSource.new(-> { [] })
      b.actions(*actions) unless skip_actions
    end
  end

  it "raises on a write action instead of silently compiling nothing" do
    expect { builder(:list, :update).compile }
      .to raise_error(ArgumentError, /unsupported actions: update/)
  end

  it "names the supported actions and says write actions are missing" do
    expect { builder(:update).compile }
      .to raise_error(ArgumentError, /supported: list, show; write actions are not implemented yet/)
  end

  it "reports every unsupported action" do
    expect { builder(:create, :destroy).compile }
      .to raise_error(ArgumentError, /unsupported actions: create, destroy/)
  end

  it "raises when actions is empty" do
    expect { builder.compile }.to raise_error(ArgumentError, /declares no actions/)
  end

  it "still compiles both default actions" do
    expect(builder(skip_actions: true).compile.map(&:name)).to eq(%w[widgets_list widgets_show])
  end

  it "still compiles a single supported action" do
    expect(builder(:show).compile.map(&:name)).to eq(%w[widgets_show])
  end
end
