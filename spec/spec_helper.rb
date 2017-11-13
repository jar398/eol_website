# This file was generated by the `rails generate rspec:install` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# The generated `.rspec` file contains `--require spec_helper` which will cause
# this file to always be loaded, without a need to explicitly require it in any
# files.
#
# Given that it is always loaded, you are encouraged to keep this file as
# light-weight as possible. Requiring heavyweight dependencies from this file
# will add to the boot time of your test suite on EVERY test run, even for an
# individual file that may not need all of that loaded. Instead, consider making
# a separate helper file that requires the additional dependencies and performs
# the additional setup, and require it from the spec files that actually need
# it.
#
# The `.rspec` file also contains a few flags that are not defaults but that
# users commonly want.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration

require "factory_girl"
require "rack_session_access/capybara"
Dir[Rails.root.join("spec/support/**/*.rb")].each { |file| require file }
require "coveralls"
require "pundit/rspec"

Coveralls.wear!

RSpec.configure do |config|
  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.include FactoryGirl::Syntax::Methods
  config.include EolSpecHelpers

  config.before(:suite) do
    FactoryGirl.find_definitions
    # disable callbacks
    Searchkick.disable_callbacks
  end

  config.before(:each, type: :controller) do
    allow_any_instance_of(ActionView::Helpers::AssetTagHelper).
      to receive(:stylesheet_link_tag) { "<style />".html_safe }
    allow_any_instance_of(ActionView::Helpers::AssetTagHelper).
      to receive(:javascript_include_tag) { "<script />".html_safe }
    allow_any_instance_of(ActionView::Helpers::AssetTagHelper).
      to receive(:image_tag) { |arg1, arg2| "<img src='#{arg1}'></img>".html_safe }
    allow_any_instance_of(ActionView::Helpers::CsrfHelper).
      to receive(:csrf_meta_tags) { "<meta/>".html_safe }
    allow_any_instance_of(ApplicationHelper).
      to receive_message_chain(:cms_menu, :to_html) { "" }
  end

  config.before(:each, type: :request) do
    allow_any_instance_of(ActionView::Helpers::AssetTagHelper).
      to receive(:stylesheet_link_tag) { "<style />".html_safe }
    allow_any_instance_of(ActionView::Helpers::AssetTagHelper).
      to receive(:javascript_include_tag) { "<script />".html_safe }
    allow_any_instance_of(ActionView::Helpers::AssetTagHelper).
      to receive(:image_tag) { |arg1, arg2| "<img src='#{arg1}'></img>".html_safe }
    allow_any_instance_of(ActionView::Helpers::CsrfHelper).
      to receive(:csrf_meta_tags) { "<meta/>".html_safe }
    allow_any_instance_of(ApplicationHelper).
      to receive_message_chain(:cms_menu, :to_html) { "" }
  end

  config.before(:each, type: :view) do
    allow(view).to receive(:stylesheet_link_tag) { "<style />".html_safe }
    allow(view).to receive(:javascript_include_tag) { "<script />".html_safe }
    allow(view).to receive(:image_tag) do |arg1, arg2|
      "<img src='#{arg1}'></img>".html_safe
    end
    allow(view).to receive(:csrf_meta_tags) { "<meta/>".html_safe }
    allow_any_instance_of(ApplicationHelper).
      to receive_message_chain(:cms_menu, :to_html) { "" }
  end

  config.after(:each) do
    # Hmmn. We really want to clear the entire cache before EVERY test?  Okay...  :\
    Rails.cache.clear if Rails.cache && !Rails.env.test?
    # Important to clear the language cache:
    Language.remove_instance_variable :@current if
      Language.instance_variable_defined?(:@current)
    I18n.locale = :en
  end

  # Sadly, Pundit gem causes errors with implementing #policy, sooo:
  # q.v.: https://github.com/rspec/rspec-rails/issues/1076
  config.around(:each, type: :view) do |ex|
    config.mock_with :rspec do |mocks|
      mocks.verify_partial_doubles = false
      ex.run
      mocks.verify_partial_doubles = true
    end
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end
end
