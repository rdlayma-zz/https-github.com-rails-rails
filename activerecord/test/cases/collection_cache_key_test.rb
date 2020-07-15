# frozen_string_literal: true

require "cases/helper"
require "models/developer"
require "models/computer" # Required by Developer
require "models/project"

module ActiveRecord
  class CollectionCacheKeyTest < ActiveRecord::TestCase
    fixtures :developers, :projects, :developers_projects

    test "cache_key for relations" do
      [ Developer.where(salary: 100_000).order(updated_at: :desc),
        Developer.where(salary: 100_000).order(updated_at: :desc).limit(5),
        Developer.includes(:projects).where("projects.name": "Active Record") ].each do |developers|
        assert_cache_key_format :developers, developers, digest: developers.map(&:cache_key).join("-")
      end
    end

    test "query counts" do
      developers = Developer.where(name: "David")
      assert_queries(1) { developers.cache_key }
      assert_no_queries { developers.cache_key }
    end

    test "cache_key for empty relation" do
      assert_cache_key_format :developers, Developer.none, digest: ""
    end

    test "collection proxy provides a cache_key" do
      assert_cache_key_format :developers, projects(:active_record).developers
    end

    test "cache_key for empty collection proxy" do
      Developer.delete_all
      assert_cache_key_format :developers, Project.includes(:developers).first.developers
    end

    test "cache_key with a relation having selected columns" do
      assert_raises ActiveModel::MissingAttributeError do
        assert_cache_key_format :developers, Developer.select(:salary).cache_key
      end

      assert_cache_key_format :developers, Developer.select(:salary, :legacy_updated_at, :legacy_updated_on)
    end

    test "cache_key with a relation having distinct and order" do
      assert_cache_key_format :developers, Developer.distinct.order(:salary).limit(5)
    end

    test "cache_key_with_version is an alias" do
      assert_equal Developer.all.cache_key, Developer.all.cache_key_with_version
    end

    test "cache_key with timestamp, cache_version are deprecated" do
      assert_deprecated { Developer.where(name: "David").cache_key(:legacy_updated_at) }
      assert_deprecated { Developer.all.cache_version }
    end

    private
      def assert_cache_key_format(model_name_cache_key, collection, digest: nil)
        assert_match(/\A#{model_name_cache_key}\/collection\/#{digest ? ActiveSupport::Digest.hexdigest(digest) : "[\\w-]+"}\z/, collection.cache_key)
      end
  end
end
