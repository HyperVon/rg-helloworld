# frozen_string_literal: true

require 'sinatra'
require_relative 'artifact_inspector'

set :port, ENV.fetch('PORT', 4568)
set :bind, '0.0.0.0'

# rubocop:disable Metrics/BlockLength
get '/' do
  content_type :html
  <<~HTML
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Artifact Inspector — Rube Goldberg Hello World</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      *{box-sizing:border-box}
      body{font-family:Inter,system-ui,helvetica,arial,sans-serif;margin:0;min-height:100vh;background:radial-gradient(1200px 600px at 20% -10%, #6d28d9 0%, transparent 60%),radial-gradient(1000px 500px at 100% 0%, #06b6d4 0%, transparent 55%),linear-gradient(180deg,#0f172a 0%,#020617 100%);color:#e2e8f0;display:flex;align-items:center;justify-content:center;padding:2rem}
      .card{width:min(720px,100%);background:rgba(15,23,42,0.7);backdrop-filter:blur(12px);border:1px solid rgba(148,163,184,0.15);border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.08);overflow:hidden}
      .header{padding:1.25rem 1.5rem;display:flex;align-items:center;gap:.75rem;background:linear-gradient(90deg,rgba(109,40,217,0.5),rgba(6,182,214,0.4));border-bottom:1px solid rgba(148,163,184,0.15)}
      .logo{width:36px;height:36px;border-radius:10px;background:linear-gradient(135deg,#8b5cf6,#22d3ee);display:grid;place-items:center;font-weight:900;color:white;box-shadow:0 4px 16px rgba(109,40,217,0.5)}
      h1{margin:0;font-size:1.15rem;letter-spacing:-.02em}
      .sub{font-size:.85rem;opacity:.7;margin:0}
      .body{padding:1.5rem}
      .hero{font-size:.95rem;line-height:1.6;opacity:.85;margin:0 0 1rem}
      .glass{display:flex;gap:.5rem;background:rgba(30,41,59,0.6);border:1px solid rgba(148,163,184,0.15);border-radius:12px;padding:.5rem}
      input{flex:1;background:rgba(2,6,23,0.6);border:1px solid rgba(148,163,184,0.2);color:#f1f5f9;border-radius:8px;padding:.6rem .8rem;outline:none}
      input:focus{border-color:#22d3ee;box-shadow:0 0 0 3px rgba(34,211,238,0.2)}
      button{background:linear-gradient(135deg,#8b5cf6,#06b6d4);color:white;border:0;border-radius:8px;padding:.6rem 1rem;font-weight:700;cursor:pointer;box-shadow:0 4px 16px rgba(109,40,217,0.4)}
      button:hover{filter:brightness(1.05)}
      .meta{margin-top:1rem;display:flex;gap:1rem;flex-wrap:wrap;font-size:.8rem;opacity:.6}
      .meta code{background:rgba(148,163,184,0.15);padding:.15rem .35rem;border-radius:4px}
      .tip{margin-top:1rem;background:rgba(6,182,214,0.08);border:1px solid rgba(6,182,214,0.2);border-radius:10px;padding:.75rem 1rem;font-size:.85rem}
      .tip a{color:#22d3ee}
      .particles{position:fixed;inset:0;pointer-events:none;overflow:hidden}
      .dot{position:absolute;width:4px;height:4px;background:rgba(34,211,238,0.5);border-radius:50%;animation:float 12s infinite}
      @keyframes float{from{transform:translateY(110vh)}to{transform:translateY(-10vh)}}
    </style>
    </head><body>
    <div class="particles"><div class="dot" style="left:12%;animation-delay:0s"></div><div class="dot" style="left:28%;animation-delay:2s"></div><div class="dot" style="left:45%;animation-delay:4s"></div><div class="dot" style="left:68%;animation-delay:1s"></div><div class="dot" style="left:84%;animation-delay:3s"></div></div>
    <div class="card">
      <div class="header"><div class="logo">RG</div><div><h1>Artifact Inspector</h1><p class="sub">Rube Goldberg Hello World — 11 services → one line</p></div></div>
      <div class="body">
        <p class="hero">Inspect every intermediate artifact: vector glyphs → geometry → SVG → raster → phrase image → OCR → assembly. Dark glass, live data, zero cloud.</p>
        <form class="glass" onsubmit="event.preventDefault();var v=document.getElementById('run').value.trim(); if(v) location.href='/inspector/runs/'+encodeURIComponent(v);">
          <input id="run" placeholder="Enter runId (auto-listed in Web Shell)" />
          <button type="submit">Open →</button>
        </form>
        <div class="meta"><span>API: <code>GET /inspector/runs/:runId/artifacts</code></span><span><a href="/health" style="color:#22d3ee;text-decoration:none">/health</a></span></div>
        <div class="tip">Tip: grab a runId from <a href="http://localhost:3000">Web Shell</a> (dropdown at top) — no manual copy-paste needed. Or <code>go -C cmd/rghw run . run --api-url http://localhost:8080</code></div>
      </div>
    </div>
    </body></html>
  HTML
end

get '/inspector' do # rubocop:disable Metrics/BlockLength
  content_type :html
  <<~HTML
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Artifact Inspector — Rube Goldberg Hello World</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      *{box-sizing:border-box}
      body{font-family:Inter,system-ui,sans-serif;margin:0;min-height:100vh;background:radial-gradient(1200px 600px at 20% -10%, #6d28d9 0%, transparent 60%),radial-gradient(1000px 500px at 100% 0%, #06b6d4 0%, transparent 55%),linear-gradient(180deg,#0f172a 0%,#020617 100%);color:#e2e8f0;display:flex;align-items:center;justify-content:center;padding:2rem}
      .card{width:min(720px,100%);background:rgba(15,23,42,0.7);backdrop-filter:blur(12px);border:1px solid rgba(148,163,184,0.15);border-radius:16px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,0.5)}
      .header{padding:1.2rem 1.5rem;background:linear-gradient(90deg,rgba(109,40,217,0.5),rgba(6,182,214,0.4));display:flex;gap:.75rem;align-items:center}
      .logo{width:36px;height:36px;border-radius:10px;background:linear-gradient(135deg,#8b5cf6,#22d3ee);display:grid;place-items:center;font-weight:900;color:white}
      h1{margin:0;font-size:1.1rem}
      .body{padding:1.5rem}
      .glass{display:flex;gap:.5rem;background:rgba(30,41,59,0.6);border-radius:12px;padding:.5rem}
      input{flex:1;background:rgba(2,6,23,0.6);border:1px solid rgba(148,163,184,0.2);color:#f1f5f9;border-radius:8px;padding:.6rem .8rem}
      button{background:linear-gradient(135deg,#8b5cf6,#06b6d4);color:white;border:0;border-radius:8px;padding:.6rem 1rem;font-weight:700;cursor:pointer}
    </style>
    </head><body>
    <div class="card">
      <div class="header"><div class="logo">RG</div><div><h1>Artifact Inspector</h1><p style="margin:0;opacity:.7;font-size:.85rem">11 services → one line</p></div></div>
      <div class="body">
        <p style="opacity:.85">Inspect every intermediate artifact live.</p>
        <form class="glass" onsubmit="event.preventDefault();var v=document.getElementById('run').value.trim(); if(v) location.href='/inspector/runs/'+encodeURIComponent(v);">
          <input id="run" placeholder="Enter runId" />
          <button type="submit">Open →</button>
        </form>
        <p style="font-size:.8rem;opacity:.6">API: <code>GET /inspector/runs/:runId/artifacts</code> · <a href="/health" style="color:#22d3ee">/health</a></p>
      </div>
    </div>
    </body></html>
  HTML
end

get '/health' do
  content_type :json
  { status: 'ok', service: ArtifactInspector::SERVICE_NAME, version: ArtifactInspector::VERSION }.to_json
end

get '/inspector/runs/:run_id/artifacts' do
  lister = ArtifactInspector::ArtifactLister.new(ENV['ORCHESTRATOR_URL'] || 'http://localhost:4567')
  artifacts = lister.list(params[:run_id])
  content_type :json
  { runId: params[:run_id], artifacts: artifacts }.to_json
end

get '/inspector/runs/:run_id/artifacts/:artifact_id' do
  lister = ArtifactInspector::ArtifactLister.new(ENV['ORCHESTRATOR_URL'] || 'http://localhost:4567')
  artifact = lister.find(params[:run_id], params[:artifact_id])
  if artifact
    content_type :json
    artifact.to_json
  else
    status 404
    { error: 'not_found' }.to_json
  end
end

get '/inspector/runs/:run_id' do
  lister = ArtifactInspector::ArtifactLister.new(ENV['ORCHESTRATOR_URL'] || 'http://localhost:4567')
  artifacts = lister.list(params[:run_id])
  lister.to_html(artifacts, params[:run_id])
end

# rubocop:enable Metrics/BlockLength
get '/inspector/runs/:run_id/artifacts/:artifact_id/view' do
  lister = ArtifactInspector::ArtifactLister.new(ENV['ORCHESTRATOR_URL'] || 'http://localhost:4567')
  artifact = lister.find(params[:run_id], params[:artifact_id])
  if artifact
    lister.artifact_html(artifact, params[:run_id], params[:artifact_id])
  else
    status 404
    'Not found'
  end
end
