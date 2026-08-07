import { useEffect, useState } from 'react';
import { SuccessAnimation } from './components/SuccessAnimation';
import { ArtifactModal } from './components/ArtifactModal';
import { ProcessGraph } from './components/ProcessGraph';
import { RunSelector } from './components/RunSelector';
import { useSseStream } from './hooks/useSseStream';
import type { RunSummary, ArtifactNode } from './types';
import { parseSseFrame } from './hooks/useSseStream';

function prefersReducedMotion(): boolean {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export function App() {
  const [runId, setRunId] = useState<string | null>(null);
  const [showArtifacts, setShowArtifacts] = useState(false);
  const streamUrl = runId ? `/api/v1/runs/${runId}/stream` : '';

  const { summary, connected, error, eventTypeCount } = useSseStream(streamUrl, 5000);

  const [artifacts, setArtifacts] = useState<ArtifactNode[]>([]);

  useEffect(() => {
    if (!runId) return;
    fetch(`/api/v1/runs/${runId}/artifacts`)
      .then((r) => r.json())
      .then((data) => setArtifacts((data as { artifacts: ArtifactNode[] }).artifacts || []))
      .catch(() => {});
  }, [runId]);

  const [reducedMotion, setReducedMotion] = useState(false);
  useEffect(() => {
    setReducedMotion(prefersReducedMotion());
  }, []);

  const handleSelectRun = (id: string) => {
    setRunId(id);
  };

  const currentStage = summary?.currentStage ?? 'CREATED';
  const terminal = summary?.terminal ?? false;
  const runStatus = summary?.status ?? 'CREATED';
  const glyphCount = summary?.percentage ? Math.ceil(summary.percentage / 10) : 11;

  return (
    <div className="app">
      <header>
        <h1>Rube Goldberg Hello World</h1>
        {connected && <span className="status-dot connected" />}
        <span className="connection-state">{connected ? 'Connected' : 'Disconnected'}</span>
        {error && <span className="error">{error}</span>}
      </header>

      <RunSelector onSelectRun={handleSelectRun} currentRunId={runId} />

      {runId && (
        <>
          <main>
            <section className="graph-section">
              <h2>Process Graph</h2>
              <ProcessGraph
                currentStage={currentStage}
                terminal={terminal}
                runStatus={runStatus}
                glyphCount={glyphCount}
              />
            </section>

            <section className="telemetry-section">
              <h2>Telemetry</h2>
              <div className="metrics">
                <div>Attempt: {summary?.attempt ?? 0}</div>
                <div>Progress: {summary?.percentage ?? 0}%</div>
                <div>Stage: {currentStage}</div>
                <div>
                  Events received: {Object.values(eventTypeCount).reduce((a, b) => a + b, 0)}
                </div>
                {runStatus === 'SUCCEEDED' && (
                  <button onClick={() => setShowArtifacts(true)}>View Artifacts</button>
                )}
              </div>
            </section>

            {runStatus === 'SUCCEEDED' && (
              <section className="success-section">
                <SuccessAnimation status="SUCCEEDED" prefersReducedMotion={reducedMotion} />
              </section>
            )}
          </main>

          {showArtifacts && (
            <ArtifactModal artifacts={artifacts} onClose={() => setShowArtifacts(false)} />
          )}
        </>
      )}

      <style>{`
        .app {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          max-width: 1200px;
          margin: 0 auto;
          padding: 1rem;
        }
        header {
          display: flex;
          align-items: center;
          gap: 1rem;
          padding-bottom: 1rem;
          border-bottom: 2px solid #e5e7eb;
        }
        .status-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          display: inline-block;
        }
        .connected {
          background: #10b981;
        }
        .error {
          color: #ef4444;
          margin-left: auto;
        }
        .graph-section, .telemetry-section, .success-section {
          margin: 1rem 0;
        }
        .metrics {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 0.5rem;
        }
      `}</style>
    </div>
  );
}

// Re-export parseSseFrame for potential use
export { parseSseFrame };
