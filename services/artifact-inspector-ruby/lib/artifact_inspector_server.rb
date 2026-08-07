# frozen_string_literal: true

require 'sinatra'
require_relative 'artifact_inspector'

set :port, ENV.fetch('PORT', 4568)
set :bind, '0.0.0.0'

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
