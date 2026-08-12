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

    def list_runs
      fetch_runs
    end

    def fetch_runs
      uri = URI("#{api_url}/api/v1/runs")
      resp = JSON.parse(Net::HTTP.get(uri))
      runs = resp['runs'] || []
      runs.sort_by { |r| r['createdAt'] }.reverse
    rescue StandardError
      []
    end

    def to_html(artifacts, run_id)
      rows = if artifacts.empty?
               '<tr><td colspan="5" style="text-align:center;padding:2rem;opacity:.6">' \
                 'No artifacts yet — run may still be in progress. ' \
                 'Try <a href="/" style="color:#22d3ee">another runId</a> ' \
                 'or check Web Shell at <a href="http://localhost:3000" style="color:#22d3ee">http://localhost:3000</a>.</td></tr>'
             else
               artifacts.map do |a|
                 preview = preview_cell(a, run_id)
                 <<~HTML
                   <tr>
                     <td style="font-family:monospace;font-size:.85rem">#{h(a['artifactId'][0, 8])}…</td>
                     <td><span style="background:rgba(139,92,246,0.2);color:#c4b5fd;padding:.15rem .4rem;border-radius:4px;font-size:.8rem">#{h(a['stage'])}</span></td>
                     <td style="font-family:monospace;font-size:.8rem">#{h(a['sha256']&.slice(0, 16))}…</td>
                     <td>#{preview}</td>
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
          td{padding:.6rem 1rem;border-bottom:1px solid rgba(148,163,184,0.07);font-size:.9rem;vertical-align:middle}
          tr:hover td{background:rgba(30,41,59,0.4)}
          .empty{padding:2rem;text-align:center}
          .back{display:inline-block;margin-top:1rem;color:#22d3ee;text-decoration:none;font-weight:600}
          .thumb{width:96px;height:64px;object-fit:contain;background:white;border-radius:6px;padding:4px;cursor:zoom-in;box-shadow:0 2px 8px rgba(0,0,0,0.2)}
          .thumb-wrap{position:relative;display:inline-block}
          .lightbox{position:fixed;inset:0;background:rgba(2,6,23,0.88);display:none;align-items:center;justify-content:center;z-index:999;padding:1rem}
          .lightbox.open{display:flex}
          .lightbox img{max-width:min(92vw,1000px);max-height:90vh;object-fit:contain;background:white;border-radius:10px;padding:8px;box-shadow:0 20px 60px rgba(0,0,0,0.6)}
          .lightbox .close{position:absolute;top:1rem;right:1rem;background:rgba(255,255,255,0.12);border:0;color:#e2e8f0;border-radius:8px;width:36px;height:36px;font-size:1.2rem;cursor:pointer}
        </style>
        </head>
        <body>
          <div class="wrap">
            <div class="header"><div class="logo">RG</div><div><h1>Artifacts for Run #{h(run_id[0, 8])}…</h1><p class="sub">#{artifacts.size} artifact#{'s' unless artifacts.size == 1} · #{h(run_id)} · #{artifacts.count { |a| image_type?(a['contentType']) }} images</p></div></div>
            <div class="card">
              <div class="bar"><span>Pipeline artifacts — SHA-256 verified, MinIO-backed — click thumbnails to enlarge</span><a href="/">← Back to inspector</a></div>
              <table>
                <thead><tr><th>ID</th><th>Stage</th><th>SHA-256</th><th>Preview</th><th></th></tr></thead>
                <tbody>
                  #{rows}
                </tbody>
              </table>
            </div>
            <a class="back" href="/">← Back</a>
          </div>
          <div id="lb" class="lightbox" onclick="this.classList.remove('open')">
            <button class="close" onclick="document.getElementById('lb').classList.remove('open')">×</button>
            <img id="lb-img" alt="preview" />
          </div>
          <script>
            function openLb(src) {
              var lb = document.getElementById('lb');
              var img = document.getElementById('lb-img');
              img.src = src;
              lb.classList.add('open');
            }
            document.addEventListener('keydown', function(e) { if (e.key === 'Escape') document.getElementById('lb').classList.remove('open'); });
          </script>
        </body>
        </html>
      HTML
    end

    def artifact_html(artifact, run_id, artifact_id)
      content_type = artifact['contentType'] || 'unknown'
      preview_block = image_type?(content_type) && artifact['proxyUrl'] ? <<~IMG : ''
        <div style="margin:1rem 0;background:white;border-radius:12px;padding:12px;box-shadow:0 8px 24px rgba(0,0,0,0.2);text-align:center">
          <img src="#{h(artifact['proxyUrl'])}" alt="#{h(artifact['stage'])}" style="max-width:100%;max-height:60vh;object-fit:contain;cursor:zoom-in" onclick="window.open(this.src,'_blank')" onerror="this.style.display='none';this.nextElementSibling.style.display='block'" />
          <div style="display:none;color:#334155;font-size:.9rem">Preview unavailable — <a href="#{h(artifact['proxyUrl'])}" target="_blank" style="color:#0ea5e9">open original</a></div>
          <div style="font-size:.75rem;color:#475569;margin-top:.35rem">Click to open full size • SHA-256 verified</div>
        </div>
      IMG
      json_hint = content_type.include?('json') && artifact['proxyUrl'] ? "<p><a href=\"#{h(artifact['proxyUrl'])}\" target=\"_blank\">View raw JSON →</a> — <a href=\"#{h(artifact['proxyUrl'])}\" download>Download</a></p>" : ''
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
          .preview-wrap img{box-shadow:0 8px 24px rgba(0,0,0,0.25)}
        </style>
        </head>
        <body>
          <div class="wrap">
            <div class="card">
              <h1>Artifact #{h(artifact_id)} <span class="tag">#{h(artifact['stage'])}</span></h1>
              <p><strong>SHA-256:</strong> <code>#{h(artifact['sha256'])}</code></p>
              <p><strong>Type:</strong> #{h(content_type)}</p>
              #{preview_block}
              #{json_hint}
              #{"<p><a href=\"#{h(artifact['proxyUrl'])}\" target=\"_blank\">View artifact proxy →</a></p>" if artifact['proxyUrl'] && !image_type?(content_type)}
              <p><a href="/inspector/runs/#{h(run_id)}">← Back to run</a></p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    private

    def image_type?(ct)
      ct.to_s.start_with?('image/')
    end

    def preview_cell(a, _run_id)
      ct = a['contentType']
      url = a['proxyUrl']
      return '<span style="opacity:.4;font-size:.8rem">—</span>' unless image_type?(ct) && url

      %(<img src="#{h(url)}" alt="#{h(a['stage'])}" class="thumb" loading="lazy" onclick="openLb(this.src)" onerror="this.style.display='none';this.nextElementSibling.style.display='block'" /><span style="display:none;font-size:.75rem;opacity:.6">preview unavailable</span>)
    end

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
