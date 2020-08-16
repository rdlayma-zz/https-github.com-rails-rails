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
        tmp_yaml ["empty", "yml"], "" do |t|
          assert_empty File.new(t.path).rows
        end
      end

      # A valid YAML file is not necessarily a value Fixture file. Make sure
      # an exception is raised if the format is not valid Fixture format.
      def test_wrong_fixture_format_string
        tmp_yaml ["empty", "yml"], "qwerty" do |t|
          assert_raises ActiveRecord::Fixture::FormatError do
            File.new(t.path)
          end
        end
      end

      def test_wrong_fixture_format_nested
        tmp_yaml ["empty", "yml"], "one: two" do |t|
          assert_raises ActiveRecord::Fixture::FormatError do
            File.new(t.path)
          end
        end
      end

      def test_render_context_helper
        ActiveRecord::FixtureSet.context_class.class_eval do
          def fixture_helper; "Fixture helper"; end
        end

        tmp_yaml ["curious", "yml"], "one:\n  name: <%= fixture_helper %>\n" do |t|
          assert_equal({ "one" => { "name" => "Fixture helper" } }, File.new(t.path).rows)
        end
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

        tmp_yaml ["curious", "yml"], yaml do |t|
          assert_equal golden, File.new(t.path).rows
        end
      end

      # Make sure that each fixture gets its own rendering context so that
      # fixtures are independent.
      def test_independent_render_contexts
        yaml1 = "<% def leaked_method; 'leak'; end %>\n"
        yaml2 = "one:\n  name: <%= leaked_method %>\n"

        tmp_yaml ["leaky", "yml"], yaml1 do |t1|
          tmp_yaml ["curious", "yml"], yaml2 do |t2|
            File.new(t1.path).rows.to_a

            assert_raises(NameError) do
              File.new(t2.path).rows.to_a
            end
          end
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
        def tmp_yaml(name, contents)
          t = Tempfile.new name
          t.binmode
          t.write contents
          t.close
          yield t
        ensure
          t.close true
        end
    end
  end
end
