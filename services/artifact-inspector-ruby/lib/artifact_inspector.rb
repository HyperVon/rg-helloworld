# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module ArtifactInspector
  VERSION = '0.5.0-milestone11'
  SERVICE_NAME = 'artifact-inspector'

  class ArtifactLister # rubocop:disable Metrics/ClassLength
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

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def to_html(artifacts, run_id)
      rows = if artifacts.empty?
               '<tr><td colspan="4" style="text-align:center;padding:2rem;opacity:.6">' \
                 'No artifacts yet — run may still be in progress. ' \
                 'Try <a href="/" style="color:#22d3ee">another runId</a> ' \
                 'or check Web Shell at <a href="http://localhost:3000" style="color:#22d3ee">http://localhost:3000</a>.</td></tr>'
             else
               artifacts.map do |a|
                 <<~HTML
                   <tr>
                     <td style="font-family:monospace;font-size:.85rem">#{h(a['artifactId'])}</td>
                     <td><span style="background:rgba(139,92,246,0.2);color:#c4b5fd;padding:.15rem .4rem;border-radius:4px;font-size:.8rem">#{h(a['stage'])}</span></td>
                     <td style="font-family:monospace;font-size:.8rem">#{h(a['sha256']&.slice(0, 16))}…</td>
                     <td><a href="/inspector/runs/#{h(run_id)}/artifacts/#{h(a['artifactId'])}" style="color:#22d3ee;text-decoration:none;font-weight:600">View →</a></td>
                   </tr>
                 HTML
               end.join("\n")
             end

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Artifacts for #{h(run_id)} — Rube Goldberg</title><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          *{box-sizing:border-box}
          body{font-family:Inter,system-ui,sans-serif;margin:0;min-height:100vh;background:radial-gradient(1200px 600px at 20% -10%, #6d28d9 0%, transparent 60%),radial-gradient(1000px 500px at 100% 0%, #06b6d4 0%, transparent 55%),linear-gradient(180deg,#0f172a 0%,#020617 100%);color:#e2e8f0;padding:2rem}
          .wrap{max-width:960px;margin:0 auto}
          .header{display:flex;align-items:center;gap:1rem;margin-bottom:1.5rem}
          .logo{width:42px;height:42px;border-radius:12px;background:linear-gradient(135deg,#8b5cf6,#22d3ee);display:grid;place-items:center;font-weight:900;color:white;font-size:1.1rem}
          h1{margin:0;font-size:1.25rem;letter-spacing:-.02em}
          .sub{opacity:.6;font-size:.9rem;margin:.15rem 0 0}
          .card{background:rgba(15,23,42,0.7);backdrop-filter:blur(12px);border:1px solid rgba(148,163,184,0.15);border-radius:16px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,0.5)}
          .bar{padding:1rem 1.25rem;background:linear-gradient(90deg,rgba(109,40,217,0.3),rgba(6,182,214,0.25));border-bottom:1px solid rgba(148,163,184,0.15);display:flex;justify-content:space-between;align-items:center}
          .bar span{font-size:.85rem;opacity:.8}
          .bar a{color:#22d3ee;text-decoration:none;font-weight:600;font-size:.85rem}
          table{width:100%;border-collapse:collapse}
          th{ text-align:left;padding:.6rem 1rem;font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;opacity:.5;border-bottom:1px solid rgba(148,163,184,0.1)}
          td{padding:.6rem 1rem;border-bottom:1px solid rgba(148,163,184,0.07);font-size:.9rem}
          tr:hover td{background:rgba(30,41,59,0.4)}
          .empty{padding:2rem;text-align:center}
          .back{display:inline-block;margin-top:1rem;color:#22d3ee;text-decoration:none;font-weight:600}
        </style>
        </head>
        <body>
          <div class="wrap">
            <div class="header"><div class="logo">RG</div><div><h1>Artifacts for Run #{h(run_id[0, 8])}…</h1><p class="sub">#{artifacts.size} artifact#{'s' unless artifacts.size == 1} · #{h(run_id)}</p></div></div>
            <div class="card">
              <div class="bar"><span>Pipeline artifacts — SHA-256 verified, MinIO-backed</span><a href="/">← Back to inspector</a></div>
              <table>
                <thead><tr><th>ID</th><th>Stage</th><th>SHA-256</th><th></th></tr></thead>
                <tbody>
                  #{rows}
                </tbody>
              </table>
            </div>
            <a class="back" href="/">← Back</a>
          </div>
        </body>
        </html>
      HTML
    end

    def artifact_html(artifact, run_id, artifact_id)
      content_type = artifact['contentType'] || 'unknown'
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Artifact #{h(artifact_id)} — Rube Goldberg</title><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          body{font-family:Inter,system-ui,sans-serif;margin:0;min-height:100vh;background:radial-gradient(1200px 600px at 20% -10%, #6d28d9 0%, transparent 60%),radial-gradient(1000px 500px at 100% 0%, #06b6d4 0%, transparent 55%),linear-gradient(180deg,#0f172a 0%,#020617 100%);color:#e2e8f0;padding:2rem}
          .wrap{max-width:720px;margin:0 auto}
          .card{background:rgba(15,23,42,0.7);backdrop-filter:blur(12px);border:1px solid rgba(148,163,184,0.15);border-radius:16px;padding:1.5rem;box-shadow:0 20px 60px rgba(0,0,0,0.5)}
          h1{margin:0 0 .5rem;font-size:1.2rem}
          .tag{display:inline-block;background:rgba(139,92,246,0.2);color:#c4b5fd;padding:.15rem .4rem;border-radius:4px;font-size:.8rem}
          code{background:rgba(148,163,184,0.15);padding:.15rem .35rem;border-radius:4px;font-size:.85rem;word-break:break-all}
          a{color:#22d3ee;text-decoration:none;font-weight:600}
        </style>
        </head>
        <body>
          <div class="wrap">
            <div class="card">
              <h1>Artifact #{h(artifact_id)} <span class="tag">#{h(artifact['stage'])}</span></h1>
              <p><strong>SHA-256:</strong> <code>#{h(artifact['sha256'])}</code></p>
              <p><strong>Type:</strong> #{h(content_type)}</p>
              #{"<p><a href=\"#{h(artifact['proxyUrl'])}\" target=\"_blank\">View artifact proxy →</a></p>" if artifact['proxyUrl']}
              <p><a href="/inspector/runs/#{h(run_id)}">← Back to run</a></p>
            </div>
          </div>
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

  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
  def self.banner
    "#{SERVICE_NAME} #{VERSION} (Milestone 11)"
  end
end
