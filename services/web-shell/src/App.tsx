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

function apiBase(): string {
  if (typeof window !== 'undefined' && window.location.hostname === 'localhost' && window.location.port === '3000') {
    return 'http://localhost:8080';
  }
  return '';
}

interface RunListItem {
  runId: string;
  status: string;
  createdAt: string;
  message?: string;
}

export function App() {
  const [runId, setRunId] = useState<string | null>(() => {
    try {
      return localStorage.getItem('rghw:lastRunId');
    } catch {
      return null;
    }
  });
  const [availableRuns, setAvailableRuns] = useState<RunListItem[]>([]);
  const [showArtifacts, setShowArtifacts] = useState(false);
  const base = apiBase();
  const streamUrl = runId ? `${base}/api/v1/runs/${runId}/stream` : '';

  const { summary, connected, error, eventTypeCount } = useSseStream(streamUrl, 5000);

  const [artifacts, setArtifacts] = useState<ArtifactNode[]>([]);

  useEffect(() => {
    let cancelled = false;
    const loadRuns = async () => {
      try {
        const r = await fetch(`${base}/api/v1/runs`);
        if (!r.ok) return;
        const data = (await r.json()) as { runs: RunListItem[] };
        if (cancelled) return;
        const list = data.runs || [];
        setAvailableRuns(list);
        if (!runId && list.length > 0) {
          const latest = list[0].runId;
          setRunId(latest);
          try {
            localStorage.setItem('rghw:lastRunId', latest);
          } catch {}
        }
      } catch {}
    };
    loadRuns();
    const id = window.setInterval(loadRuns, 5000);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [base, runId]);

  useEffect(() => {
    if (!runId) return;
    fetch(`${base}/api/v1/runs/${runId}/artifacts`)
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
    try {
      localStorage.setItem('rghw:lastRunId', id);
    } catch {}
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

      <RunSelector onSelectRun={handleSelectRun} currentRunId={runId} availableRuns={availableRuns} />

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
          font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          max-width: 1280px;
          margin: 0 auto;
          padding: 1.5rem;
          background: radial-gradient(1200px 600px at 20% -10%, #a78bfa 0%, transparent 60%),
                      radial-gradient(1000px 500px at 90% 0%, #22d3ee 0%, transparent 55%),
                      linear-gradient(180deg, #0f172a 0%, #0b1220 100%);
          color: #e2e8f0;
          border-radius: 16px;
          box-shadow: 0 20px 60px rgba(2,6,23,0.6);
        }
        header {
          display: flex;
          align-items: center;
          gap: 1rem;
          padding: 1rem 1.25rem;
          margin: -0.5rem -0.5rem 1rem;
          background: rgba(255,255,255,0.06);
          backdrop-filter: blur(12px);
          border: 1px solid rgba(255,255,255,0.12);
          border-radius: 14px;
          box-shadow: 0 8px 24px rgba(2,6,23,0.4);
        }
        header h1 {
          font-size: 1.6rem;
          font-weight: 800;
          letter-spacing: -0.02em;
          background: linear-gradient(90deg, #f8fafc, #a78bfa 30%, #22d3ee 70%, #f8fafc);
          -webkit-background-clip: text;
          background-clip: text;
          color: transparent;
          margin: 0;
        }
        .status-dot {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          display: inline-block;
          box-shadow: 0 0 0 4px rgba(16,185,129,0.25);
          animation: pulse 1.8s infinite;
        }
        @keyframes pulse { 0%{box-shadow:0 0 0 0 rgba(16,185,129,0.45)} 70%{box-shadow:0 0 0 8px rgba(16,185,129,0)} 100%{box-shadow:0 0 0 0 rgba(16,185,129,0)} }
        .connected { background: #10b981; }
        .connection-state { font-weight: 600; opacity: 0.9; }
        .error {
          color: #f87171;
          margin-left: auto;
          background: rgba(248,113,113,0.12);
          padding: 0.25rem 0.6rem;
          border-radius: 8px;
          border: 1px solid rgba(248,113,113,0.3);
        }
        .graph-section, .telemetry-section, .success-section {
          margin: 1rem 0;
          background: rgba(255,255,255,0.06);
          backdrop-filter: blur(10px);
          border: 1px solid rgba(255,255,255,0.1);
          border-radius: 14px;
          padding: 1rem;
          box-shadow: 0 8px 24px rgba(2,6,23,0.35);
        }
        .graph-section h2, .telemetry-section h2 { margin: 0 0 0.75rem; font-size: 1.1rem; letter-spacing: -0.01em; color: #f1f5f9; }
        .metrics {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 0.75rem;
        }
        .metrics > div {
          background: rgba(15,23,42,0.6);
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 10px;
          padding: 0.7rem 0.8rem;
          font-weight: 600;
        }
        .metrics button {
          background: linear-gradient(90deg, #8b5cf6, #06b6d4);
          color: white;
          border: none;
          border-radius: 10px;
          padding: 0.6rem 1rem;
          font-weight: 700;
          cursor: pointer;
          box-shadow: 0 6px 16px rgba(139,92,246,0.35);
        }
      `}</style>
    </div>
  );
}

// Re-export parseSseFrame for potential use
export { parseSseFrame };
