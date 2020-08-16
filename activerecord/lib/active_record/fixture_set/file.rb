# frozen_string_literal: true

require "active_support/configuration_file"

module ActiveRecord
  class FixtureSet
    class File # :nodoc:
      attr_reader :rows, :configuration

      def initialize(file)
        @file = file
        parse_rows
      end

      private
        def parse_rows
          unless defined?(@rows)
            @rows = read_data
            @configuration = (@rows.delete("_fixture") || {}).symbolize_keys
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
