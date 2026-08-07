# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/artifact_inspector'

class BannerTest < Minitest::Test
  def test_banner
    assert_equal 'artifact-inspector 0.5.0-milestone11 (Milestone 11)', ArtifactInspector.banner
  end
end

class ArtifactListerTest < Minitest::Test
  def setup
    @lister = ArtifactInspector::ArtifactLister.new('http://fake-api')
  end

  def test_list_returns_empty_on_failure
    result = @lister.list('nonexistent')
    assert_equal [], result
  end

  def test_to_html_renders_table
    artifacts = [
      { 'artifactId' => 'a1', 'stage' => 'raster', 'sha256' => 'abcdef1234567890', 'contentType' => 'image/png',
        'proxyUrl' => '/proxy/a1' },
      { 'artifactId' => 'a2', 'stage' => 'assembly', 'sha256' => '0987654321fedcba', 'contentType' => 'text/plain',
        'proxyUrl' => '/proxy/a2' }
    ]
    html = @lister.to_html(artifacts, 'run-1')
    assert_includes html, 'a1'
    assert_includes html, 'a2'
    assert_includes html, 'raster'
    assert_includes html, 'assembly'
    assert_includes html, 'abcdef1234567890…'
  end

  def test_to_html_handles_empty_list
    html = @lister.to_html([], 'run-1')
    assert_includes html, 'Artifacts for Run run-1'
    assert_includes html, '<tbody>'
  end

  def test_artifact_html_renders_details
    artifact = { 'artifactId' => 'a1', 'stage' => 'raster', 'sha256' => 'abcdef1234567890',
                 'contentType' => 'image/png', 'proxyUrl' => '/proxy/a1' }
    html = @lister.artifact_html(artifact, 'run-1', 'a1')
    assert_includes html, 'Artifact a1'
    assert_includes html, 'abcdef1234567890'
    assert_includes html, 'image/png'
    assert_includes html, '/proxy/a1'
  end

  def test_artifact_html_handles_missing_proxy
    artifact = { 'artifactId' => 'a1', 'stage' => 'raster', 'sha256' => 'abcdef', 'contentType' => nil,
                 'proxyUrl' => nil }
    html = @lister.artifact_html(artifact, 'run-1', 'a1')
    assert_includes html, 'unknown'
    refute_includes html, 'View artifact proxy'
  end

  def test_to_html_escapes_html
    artifacts = [
      { 'artifactId' => '<script>alert(1)</script>', 'stage' => 'test', 'sha256' => 'abc', 'contentType' => 'text',
        'proxyUrl' => '/proxy' }
    ]
    html = @lister.to_html(artifacts, 'run-1')
    assert_includes html, '&lt;script&gt;'
    refute_includes html, '<script>alert(1)</script>'
  end
end
