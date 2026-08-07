# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module ArtifactInspector
  VERSION = '0.5.0-milestone11'
  SERVICE_NAME = 'artifact-inspector'

  class ArtifactLister
    attr_reader :api_url

    def initialize(api_url = 'http://localhost:4567')
      @api_url = api_url
    end

    def list(run_id)
      fetch_artifacts(run_id)
    end

    def find(run_id, artifact_id)
      fetch_artifacts(run_id).find { |a| a['artifactId'] == artifact_id }
    end

    def to_html(artifacts, run_id)
      rows = artifacts.map do |a|
        <<~HTML
          <tr>
            <td>#{h(a['artifactId'])}</td>
            <td>#{h(a['stage'])}</td>
            <td>#{h(a['sha256']&.slice(0, 16))}…</td>
            <td><a href="/inspector/runs/#{h(run_id)}/artifacts/#{h(a['artifactId'])}">View</a></td>
          </tr>
        HTML
      end.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Artifacts for #{h(run_id)}</title></head>
        <body>
          <h1>Artifacts for Run #{h(run_id)}</h1>
          <table>
            <thead><tr><th>ID</th><th>Stage</th><th>SHA-256</th><th>Actions</th></tr></thead>
            <tbody>
              #{rows}
            </tbody>
          </table>
          <p><a href="/">Back</a></p>
        </body>
        </html>
      HTML
    end

    def artifact_html(artifact, run_id, artifact_id)
      content_type = artifact['contentType'] || 'unknown'
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Artifact #{h(artifact_id)}</title></head>
        <body>
          <h1>Artifact #{h(artifact_id)} (#{h(artifact['stage'])})</h1>
          <p><strong>SHA-256:</strong> #{h(artifact['sha256'])}</p>
          <p><strong>Type:</strong> #{h(content_type)}</p>
          #{"<p><a href=\"#{h(artifact['proxyUrl'])}\" target=\"_blank\">View artifact proxy</a></p>" if artifact['proxyUrl']}
          <p><a href="/inspector/runs/#{h(run_id)}">Back to run</a></p>
        </body>
        </html>
      HTML
    end

    private

    def fetch_artifacts(run_id)
      uri = URI("#{api_url}/api/v1/runs/#{run_id}/artifacts")
      resp = JSON.parse(Net::HTTP.get(uri))
      resp['artifacts'] || []
    rescue StandardError
      []
    end

    def h(str)
      str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end
  end

  def self.banner
    "#{SERVICE_NAME} #{VERSION} (Milestone 11)"
  end
end
