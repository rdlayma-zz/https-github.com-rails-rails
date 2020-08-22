# frozen_string_literal: true

require "active_support/configuration_file"

module ActiveRecord
  class FixtureSet
    class File # :nodoc:
      attr_reader :rows, :model_class

      class CompositeFile
        attr_reader :model_class, :rows

        def initialize(directory)
          @rows = []

          loadable_paths_from(directory).each do |path|
            file = File.new(path)
            @model_class ||= file.model_class
            @rows.concat file.rows
          end
        end

        private
          def loadable_paths_from(directory)
            Dir["#{directory}/{**,*}/*.yml"].select { |f| ::File.file?(f) } | [ "#{directory}.yml" ]
          end
      end

      def self.load_composite_from(directory)
        CompositeFile.new directory
      end

      def initialize(file)
        rows = parse_rows_from(file)
        @model_class, ignored_fixtures = rows.delete("_fixture")&.values_at("model_class", "ignore")
        @rows = rows.except!("DEFAULTS", *ignored_fixtures).to_a
      end

      private
        def parse_rows_from(file)
          ActiveSupport::ConfigurationFile.parse(file, context: new_render_context, row_type: Hash)
        rescue ActiveSupport::ConfigurationFile::FormatError
          raise Fixture::FormatError, $!
        end

        def new_render_context
          ActiveRecord::FixtureSet::RenderContext.create_subclass.new.get_binding
        end
    end
  end
end
