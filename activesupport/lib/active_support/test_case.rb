require 'test/unit/testcase'
require 'active_support/testing/setup_and_teardown'
require 'active_support/testing/assertions'
require 'active_support/testing/deprecation'
require 'active_support/testing/declarative'
require 'active_support/testing/pending'
require 'active_support/testing/isolation'
require 'active_support/core_ext/kernel/reporting'

class Object
  alias_method :__respond_to?, :respond_to?

  def respond_to?(mid, all = false)
    if !all && self.class.protected_method_defined?(mid)
      raise "PROTECTED_METHOD_IN_RESPOND_TO"
    end

    __respond_to?(mid, all)
  end
end

begin
  silence_warnings { require 'mocha/setup' }
rescue LoadError
  # Fake Mocha::ExpectationError so we can rescue it in #run. Bleh.
  Object.const_set :Mocha, Module.new
  Mocha.const_set :ExpectationError, Class.new(StandardError)
end

module ActiveSupport
  class TestCase < ::Test::Unit::TestCase
    if defined? MiniTest
      Assertion = MiniTest::Assertion
      alias_method :method_name, :name if method_defined? :name
      alias_method :method_name, :__name__ if method_defined? :__name__
    else
      Assertion = Test::Unit::AssertionFailedError

      require 'active_support/testing/default'
      include ActiveSupport::Testing::Default
    end

    $tags = {}
    def self.for_tag(tag)
      yield if $tags[tag]
    end

    include ActiveSupport::Testing::SetupAndTeardown
    include ActiveSupport::Testing::Assertions
    include ActiveSupport::Testing::Deprecation
    include ActiveSupport::Testing::Pending
    extend ActiveSupport::Testing::Declarative
  end
end
