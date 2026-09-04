# frozen_string_literal: true

module Mcpable
  module Rails
    module Loader
      module_function

      def reload!(root: ::Rails.root, relative_paths: nil, autoloaders: ::Rails.autoloaders)
        Mcpable.registry.reset!
        resolve_paths(root, relative_paths).each { |path| load_path(path, autoloaders) }
        Mcpable.registry
      end

      def schema_ready?
        return true unless defined?(::ActiveRecord::Base)

        table = ::ActiveRecord::Base.schema_migrations_table_name
        ::ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.data_source_exists?(table)
        end
      rescue StandardError
        false
      end

      def resolve_paths(root, relative_paths)
        paths = relative_paths || Engine.config.mcpable.eager_load_paths
        paths.map { |relative| root.join(relative) }.select(&:exist?)
      end

      def load_path(path, autoloaders)
        loader = autoloader_for(path, autoloaders)
        return loader.eager_load_dir(path.to_s) if loader

        Dir.glob(File.join(path.to_s, "**", "*.rb")).sort.each { |file| require file }
      end

      def autoloader_for(path, autoloaders)
        return nil if autoloaders.nil?

        autoloaders.find do |candidate|
          candidate.respond_to?(:eager_load_dir) && managed?(candidate, path.to_s)
        end
      end

      def managed?(loader, path)
        roots(loader).any? { |root| path == root || path.start_with?("#{root}/") }
      end

      def roots(loader)
        return [] unless loader.respond_to?(:dirs)

        dirs = loader.dirs
        dirs.respond_to?(:keys) ? dirs.keys : Array(dirs)
      end
    end
  end
end
