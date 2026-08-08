# frozen_string_literal: true

require 'sinatra'
require_relative 'artifact_inspector'

set :port, ENV.fetch('PORT', 4568)
set :bind, '0.0.0.0'

get '/' do
  content_type :html
  <<~HTML
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Artifact Inspector</title>
    <style>body{font-family:helvetica,arial,sans-serif;margin:2rem;max-width:700px}input{padding:.4rem;width:320px}button{padding:.4rem .8rem;margin-left:.5rem}</style>
    </head><body>
    <h1>Artifact Inspector</h1>
    <p>View intermediate images and metadata for a run.</p>
    <form onsubmit="event.preventDefault();var v=document.getElementById('run').value.trim(); if(v) location.href='/inspector/runs/'+encodeURIComponent(v);">
      <input id="run" placeholder="Enter runId (e.g. from rghw run output)" />
      <button type="submit">Open</button>
    </form>
    <p>API: <code>GET /inspector/runs/:runId/artifacts</code> &middot; Health: <a href="/health">/health</a></p>
    <p>Tip: get a runId from <code>kubectl logs -n rube-goldberg deploy/run-orchestrator</code> or from Web Shell at <a href="http://localhost:3000">http://localhost:3000</a></p>
    </body></html>
  HTML
end

get '/inspector' do
  content_type :html
  <<~HTML
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Artifact Inspector</title>
    <style>body{font-family:helvetica,arial,sans-serif;margin:2rem;max-width:700px}input{padding:.4rem;width:320px}button{padding:.4rem .8rem;margin-left:.5rem}</style>
    </head><body>
    <h1>Artifact Inspector</h1>
    <p>View intermediate images and metadata for a run.</p>
    <form onsubmit="event.preventDefault();var v=document.getElementById('run').value.trim(); if(v) location.href='/inspector/runs/'+encodeURIComponent(v);">
      <input id="run" placeholder="Enter runId" />
      <button type="submit">Open</button>
    </form>
    <p>API: <code>GET /inspector/runs/:runId/artifacts</code> &middot; Health: <a href="/health">/health</a></p>
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
