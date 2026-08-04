# frozen_string_literal: true

require 'minitest/autorun'
require 'adjudicator'

class AdjudicatorTest < Minitest::Test
  def test_version_matches_skeleton
    assert_equal '0.0.0-skeleton', Adjudicator::VERSION
  end

  def test_version_is_not_empty
    refute_empty Adjudicator::VERSION
  end

  def test_service_name_is_set
    assert_equal 'adjudicator', Adjudicator::SERVICE_NAME
  end

  def test_banner_includes_service_and_version
    assert_match(/\Aadjudicator 0\.0\.0-skeleton/, Adjudicator.banner)
  end

  def test_banner_is_deterministic
    assert_equal Adjudicator.banner, Adjudicator.banner
  end
end
