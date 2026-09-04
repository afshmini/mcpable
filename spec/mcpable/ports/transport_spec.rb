# frozen_string_literal: true

RSpec.describe Mcpable::Ports::Transport do
  subject(:transport) { described_class.new(registry: Mcpable.registry, runtime: Mcpable.runtime) }

  it "declares the serving contract as not implemented" do
    expect { transport.list_tools }.to raise_error(NotImplementedError)
    expect { transport.handle("{}") }.to raise_error(NotImplementedError)
    expect { transport.serve_stdio }.to raise_error(NotImplementedError)
  end

  it "accepts a context on both serving entry points" do
    expect { transport.handle("{}", context: { user_id: 1 }) }.to raise_error(NotImplementedError)
    expect { transport.serve_stdio(context: { user_id: 1 }) }.to raise_error(NotImplementedError)
  end
end
