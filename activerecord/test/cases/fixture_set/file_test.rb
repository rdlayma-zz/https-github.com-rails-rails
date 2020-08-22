# frozen_string_literal: true

require "cases/helper"
require "tempfile"

module ActiveRecord
  class FixtureSet
    class FileTest < ActiveRecord::TestCase
      def test_parsing
        rows = read_fixture(:accounts).rows

        assert_equal 6, rows.size
        assert_equal %w[ signals37 unknown rails_core_account last_account rails_core_account_2 odegy_account ].sort, rows.keys.sort
        assert_equal (1..6).to_a, rows.values.map { |row| row["id"] }.sort
      end

      def test_erb_processing
        assert_equal %w[ david jamis dev_3 dev_4 dev_5 dev_6 dev_7 dev_8 dev_9 dev_10 poor_jamis ].sort,
          read_fixture(:developers).rows.keys.sort
      end

      def test_empty_file
        assert_empty read_yaml.rows
      end

      # A valid YAML file is not necessarily a value Fixture file. Make sure
      # an exception is raised if the format is not valid Fixture format.
      def test_wrong_fixture_format_string
        assert_raises ActiveRecord::Fixture::FormatError do
          read_yaml "qwerty"
        end
      end

      def test_wrong_fixture_format_nested
        assert_raises ActiveRecord::Fixture::FormatError do
          read_yaml "one: two"
        end
      end

      def test_render_context_helper
        ActiveRecord::FixtureSet.context_class.class_eval do
          def fixture_helper; "Fixture helper"; end
        end

        file = read_yaml "one:\n  name: <%= fixture_helper %>\n"
        assert_equal({ "one" => { "name" => "Fixture helper" } }, file.rows)
      ensure
        ActiveRecord::FixtureSet.context_class.class_eval { remove_method :fixture_helper }
      end

      def test_render_context_lookup_scope
        yaml = <<~END
          one:
            ActiveRecord: <%= defined? ActiveRecord %>
            ActiveRecord_FixtureSet: <%= defined? ActiveRecord::FixtureSet %>
            FixtureSet: <%= defined? FixtureSet %>
            ActiveRecord_FixtureSet_File: <%= defined? ActiveRecord::FixtureSet::File %>
            File: <%= File.name %>
        END

        golden = { "one" => {
          "ActiveRecord" => "constant",
          "ActiveRecord_FixtureSet" => "constant",
          "FixtureSet" => nil,
          "ActiveRecord_FixtureSet_File" => "constant",
          "File" => "File"
        } }

        assert_equal golden, read_yaml(yaml).rows
      end

      # Make sure that each fixture gets its own rendering context so that
      # fixtures are independent.
      def test_independent_render_contexts
        read_yaml "<% def leaked_method; 'leak'; end %>\n"

        assert_raises NameError do
          read_yaml "one:\n  name: <%= leaked_method %>\n"
        end
      end

      def test_removes_fixture_config_row
        assert_equal [ "second_welcome" ], read_fixture(:other_posts).rows.keys
      end

      def test_extracts_model_class_from_config_row
        assert_equal "Post", read_fixture(:other_posts).model_class
      end

      private
        def read_fixture(name)
          File.new ::File.join(FIXTURES_ROOT, "#{name}.yml")
        end

        def read_yaml(contents = "")
          tmpfile = Tempfile.open("#{rand * 10}.yml") { |f| f.binmode; f << contents }
          File.new(tmpfile.path)
        end
    end
  end
end
