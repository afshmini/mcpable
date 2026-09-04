# frozen_string_literal: true

require "pathname"
require "tmpdir"
require "mcpable/rails/loader"

RSpec.describe Mcpable::Rails::Loader do
  let(:root) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.remove_entry(root) }

  def fake_autoloader(dirs)
    Class.new do
      attr_reader :eager_loaded

      define_method(:initialize) do
        @eager_loaded = []
      end

      define_method(:dirs) { dirs }

      define_method(:eager_load_dir) { |path| @eager_loaded << path }
    end.new
  end

  describe ".resolve_paths" do
    it "keeps only the directories that exist" do
      (root / "app" / "models").mkpath

      paths = described_class.resolve_paths(root, %w[app/models app/tools])

      expect(paths.map(&:to_s)).to eq([(root / "app" / "models").to_s])
    end
  end

  describe ".load_path" do
    it "delegates to the autoloader that manages the directory" do
      dir = root / "app" / "models"
      dir.mkpath
      loader = fake_autoloader([dir.to_s])

      described_class.load_path(dir, [loader])

      expect(loader.eager_loaded).to eq([dir.to_s])
    end

    it "matches a directory nested under an autoloader root" do
      root_dir = root / "app"
      nested = root_dir / "tools"
      nested.mkpath
      loader = fake_autoloader([root_dir.to_s])

      described_class.load_path(nested, [loader])

      expect(loader.eager_loaded).to eq([nested.to_s])
    end

    it "accepts an autoloader that reports its dirs as a hash" do
      dir = root / "app" / "models"
      dir.mkpath
      loader = fake_autoloader({ dir.to_s => nil })

      described_class.load_path(dir, [loader])

      expect(loader.eager_loaded).to eq([dir.to_s])
    end

    it "requires the files itself when no autoloader manages the directory" do
      dir = root / "app" / "tools"
      dir.mkpath
      (dir / "widget.rb").write(<<~RUBY)
        Mcpable.registry.register(
          Mcpable::Definition.build(name: "loaded_from_disk", handler: ->(_ctx) { Mcpable::Result.ok(1) })
        )
      RUBY

      described_class.load_path(dir, [fake_autoloader([])])

      expect(Mcpable.registry.names).to eq(["loaded_from_disk"])
    end

    it "requires each file only once so a second pass cannot duplicate a tool" do
      dir = root / "app" / "tools"
      dir.mkpath
      (dir / "widget.rb").write(<<~RUBY)
        Mcpable.registry.register(
          Mcpable::Definition.build(name: "loaded_once", handler: ->(_ctx) { Mcpable::Result.ok(1) })
        )
      RUBY

      described_class.load_path(dir, nil)
      Mcpable.registry.reset!

      expect { described_class.load_path(dir, nil) }.not_to raise_error
      expect(Mcpable.registry.names).to be_empty
    end
  end

  describe ".reload!" do
    it "empties the registry before loading" do
      Mcpable.registry.register(
        Mcpable::Definition.build(name: "stale", handler: ->(_ctx) { Mcpable::Result.ok(1) })
      )

      described_class.reload!(root: root, relative_paths: [], autoloaders: [])

      expect(Mcpable.registry.names).to be_empty
    end

    it "eager loads every configured path" do
      %w[app/models app/tools].each { |relative| (root / relative).mkpath }
      loader = fake_autoloader([(root / "app").to_s])

      described_class.reload!(root: root, relative_paths: %w[app/models app/tools], autoloaders: [loader])

      expect(loader.eager_loaded).to eq([(root / "app" / "models").to_s, (root / "app" / "tools").to_s])
    end
  end

  describe ".schema_ready?" do
    it "is true when the app has no ActiveRecord" do
      expect(described_class.schema_ready?).to be(true)
    end
  end
end
