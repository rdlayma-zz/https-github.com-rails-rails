# frozen_string_literal: true

require "cases/helper"
require "tempfile"

module ActiveRecord
  class FixtureSet
    class FileTest < ActiveRecord::TestCase
      def test_parsing
        file = File.new(::File.join(FIXTURES_ROOT, "accounts.yml"))
        assert_equal 6, file.rows.to_a.size
      end

      def test_names
        file = File.new(::File.join(FIXTURES_ROOT, "accounts.yml"))
        assert_equal [ "signals37", "unknown", "rails_core_account", "last_account", "rails_core_account_2", "odegy_account" ].sort,
          file.rows.to_a.map(&:first).sort
      end

      def test_values
        file = File.new(::File.join(FIXTURES_ROOT, "accounts.yml"))
        assert_equal [ 1, 2, 3, 4, 5, 6 ], file.rows.map { |row| row.last["id"] }.sort
      end

      def test_erb_processing
        file = File.new(::File.join(FIXTURES_ROOT, "developers.yml"))
        devs = Array.new(8) { |i| "dev_#{i + 3}" }
        assert_equal [], devs - file.rows.to_a.map(&:first)
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
        file = File.new(::File.join(FIXTURES_ROOT, "other_posts.yml"))
        assert_equal [ "second_welcome" ], file.rows.map(&:first)
      end

      def test_extracts_model_class_from_config_row
        file = File.new(::File.join(FIXTURES_ROOT, "other_posts.yml"))
        assert_equal "Post", file.configuration[:model_class]
      end

      private
        def read_yaml(contents = "")
          tmpfile = Tempfile.open("#{rand * 10}.yml") { |f| f.binmode; f << contents }
          File.new(tmpfile.path)
        end
    end
  end
end
