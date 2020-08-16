# frozen_string_literal: true

require "active_support/configuration_file"

module ActiveRecord
  class FixtureSet
    class File # :nodoc:
      include Enumerable

      ##
      # Open a fixture file named +file+.  When called with a block, the block
      # is called with the filehandle and the filehandle is automatically closed
      # when the block finishes.
      def self.open(file)
        x = new file
        block_given? ? yield(x) : x
      end

      def initialize(file)
        @file = file
      end

      def each(&block)
        rows.each(&block)
      end

      def configuration
        parse_rows
        @configuration.symbolize_keys
      end

      private
        def rows
          parse_rows
          @rows
        end

        def parse_rows
          unless defined?(@rows)
            @rows = read_data
            @configuration = @rows.delete("_fixture") || {}
          end
        end

        def read_data
          ActiveSupport::ConfigurationFile.parse(@file, context: new_render_context)
            .tap { |data| validate!(data) if data }
        rescue RuntimeError => error
          raise Fixture::FormatError, error.message
        end

        def new_render_context
          ActiveRecord::FixtureSet::RenderContext.create_subclass.new.get_binding
        end

        # Validate our unmarshalled data.
        def validate!(data)
          unless Hash === data || YAML::Omap === data
            raise Fixture::FormatError, "fixture is not a hash: #{@file}"
          end

          invalid = data.reject { |_, row| Hash === row }
          if invalid.any?
            raise Fixture::FormatError, "fixture key is not a hash: #{@file}, keys: #{invalid.keys.inspect}"
          end
        end
    end
  end
end
