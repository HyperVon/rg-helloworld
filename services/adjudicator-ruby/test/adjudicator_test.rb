# frozen_string_literal: true

require 'minitest/autorun'
require 'adjudicator'

class AdjudicatorTest < Minitest::Test
  def test_version_matches_milestone_8
    assert_equal '0.5.0-milestone8', Adjudicator::VERSION
  end

  def test_service_name_is_set
    assert_equal 'adjudicator', Adjudicator::SERVICE_NAME
  end

  def test_banner_includes_service_and_version
    assert_match(/\Aadjudicator 0\.5\.0-milestone8/, Adjudicator.banner)
  end
end
