import { useEffect, useState } from 'react';
import { ArtifactModal } from './components/ArtifactModal';
import { ProcessGraph } from './components/ProcessGraph';
import { RunSelector } from './components/RunSelector';
import { useSseStream } from './hooks/useSseStream';
import type { ArtifactNode } from './types';
import { parseSseFrame } from './hooks/useSseStream';
import { sanitizeRunId } from './lib/runId';

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'rg-telemetry-panel': React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement> & { 'run-id'?: string }, HTMLElement>;
    }
  }
}

function apiBase(): string {
  if (
    typeof window !== 'undefined' &&
    window.location.hostname === 'localhost' &&
    window.location.port === '3000'
  ) {
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
      return sanitizeRunId(localStorage.getItem('rghw:lastRunId'));
    } catch {
      return null;
    }
  });
  const [availableRuns, setAvailableRuns] = useState<RunListItem[]>([]);
  const [showArtifacts, setShowArtifacts] = useState(false);
  const base = apiBase();
  const streamUrl = runId ? `${base}/api/v1/runs/${encodeURIComponent(runId)}/stream` : '';

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
        if (list.length > 0) {
          const latest = list[0].runId;
          const current = runId;
          const exists = current ? list.some((x) => x.runId === current) : false;
          if (!current) {
            setRunId(latest);
            try {
              localStorage.setItem('rghw:lastRunId', latest);
            } catch {}
          } else if (!exists) {
            let shouldCorrect = true;
            try {
              const vr = await fetch(`${base}/api/v1/runs/${encodeURIComponent(current)}`);
              if (vr.ok) {
                const vdata = (await vr.json()) as { status?: string };
                if (vdata && vdata.status && vdata.status !== 'UNKNOWN') {
                  shouldCorrect = false;
                }
              }
            } catch {}
            if (shouldCorrect) {
              setRunId(latest);
              try {
                localStorage.setItem('rghw:lastRunId', latest);
              } catch {}
            }
          }
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
    let cancelled = false;
    let timer: number | null = null;
    const load = async () => {
      try {
        const r = await fetch(`${base}/api/v1/runs/${encodeURIComponent(runId)}/artifacts`);
        if (!r.ok) return;
        const data = (await r.json()) as { artifacts: ArtifactNode[] };
        if (cancelled) return;
        setArtifacts(data.artifacts || []);
      } catch {}
    };
    load();
    const poll = () => {
      if (summary?.terminal) return;
      timer = window.setTimeout(async () => {
        await load();
        if (!cancelled) poll();
      }, 1500) as unknown as number;
    };
    poll();
    return () => {
      cancelled = true;
      if (timer !== null) window.clearTimeout(timer);
    };
  }, [runId, base, summary?.terminal]);

  useEffect(() => {
    const onArtifact = () => {
      if (!runId) return;
      fetch(`${base}/api/v1/runs/${encodeURIComponent(runId)}/artifacts`)
        .then((r) => r.json())
        .then((data) => setArtifacts((data as { artifacts: ArtifactNode[] }).artifacts || []))
        .catch(() => {});
    };
    window.addEventListener('rghw:artifact-created' as any, onArtifact);
    return () => window.removeEventListener('rghw:artifact-created' as any, onArtifact);
  }, [runId, base]);

  const handleSelectRun = (id: string) => {
    const safe = sanitizeRunId(id);
    if (!safe) return;
    setRunId(safe);
    try {
      localStorage.setItem('rghw:lastRunId', safe);
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

      <RunSelector
        onSelectRun={handleSelectRun}
        currentRunId={runId}
        availableRuns={availableRuns}
      />

      {runId && (
        <>
          <main className="main-layout">
            <section className="telemetry-section telemetry-top">
              <h2>Telemetry</h2>
              <div className="metrics">
                <div>Attempt: {summary?.attempt ?? 0}</div>
                <div>Progress: {summary?.percentage ?? 0}%</div>
                <div>Stage: {currentStage}</div>
                <div>
                  Events received: {Object.values(eventTypeCount).reduce((a, b) => a + b, 0)}
                </div>
                <button onClick={() => setShowArtifacts(true)} disabled={artifacts.length === 0} title={artifacts.length === 0 ? 'No artifacts yet' : `${artifacts.length} artifacts`}>
                  View Artifacts {artifacts.length > 0 ? `(${artifacts.length})` : ''}
                </button>
                {artifacts.length > 0 && <span className="artifact-count-hint">{artifacts.filter((a) => a.contentType?.startsWith('image/')).length} images</span>}
              </div>
            </section>

            <section className="graph-section">
              <h2>Process Graph</h2>
              <ProcessGraph
                currentStage={currentStage}
                terminal={terminal}
                runStatus={runStatus}
                glyphCount={glyphCount}
              />
            </section>

            <section className="telemetry-element-section">
              <h2>Run Ledger — Angular Telemetry</h2>
              <div className="telemetry-element-wrap">
                {/* Spec §19.1: Angular Elements telemetry panel; React supplies run-id, element fetches independently */}
                {/* @ts-ignore custom element */}
                {React.createElement('rg-telemetry-panel', { 'run-id': runId || '' } as any)}
                <div className="telemetry-fallback">
                  <div className="telemetry-fallback-grid">
                    <div><strong>Run:</strong> {runId?.slice(0, 8)}…</div>
                    <div><strong>Status:</strong> {runStatus}</div>
                    <div><strong>Stage:</strong> {currentStage}</div>
                    <div><strong>Artifacts:</strong> {artifacts.length}</div>
                    <div><strong>Images:</strong> {artifacts.filter((a) => a.contentType?.startsWith('image/')).length}</div>
                    <div><strong>SSE:</strong> {connected ? 'connected' : 'disconnected'}</div>
                  </div>
                  <div className="artifact-thumbs">
                    {artifacts
                      .filter((a) => a.contentType?.startsWith('image/'))
                      .slice(0, 8)
                      .map((a) => (
                        <img
                          key={a.id}
                          src={`${base}${a.proxyUrl}`}
                          alt={a.stage}
                          title={`${a.stage} — ${a.sha256.slice(0, 8)}`}
                          loading="lazy"
                          onError={(e) => ((e.target as HTMLImageElement).style.display = 'none')}
                        />
                      ))}
                    {artifacts.filter((a) => a.contentType?.startsWith('image/')).length === 0 && (
                      <span style={{ opacity: 0.6, fontSize: '0.85rem' }}>No images yet — artifacts appear as pipeline progresses (polling every 1.5 s).</span>
                    )}
                  </div>
                </div>
              </div>
              <div className="telemetry-links">
                <a href={`${base}/api/v1/runs/${encodeURIComponent(runId)}/artifacts`} target="_blank" rel="noopener noreferrer">Artifacts JSON</a>
                <span> · </span>
                <a href={`${base}/api/v1/runs/${encodeURIComponent(runId)}/stream`} target="_blank" rel="noopener noreferrer">SSE stream</a>
                <span> · </span>
                <a href={`${base}/metrics`} target="_blank" rel="noopener noreferrer">Orchestrator metrics</a>
                <span> · </span>
                <a href="http://localhost:3001/health" target="_blank" rel="noopener noreferrer">Event gateway</a>
              </div>
            </section>

            <section className="observability-section">
              <h2>Observability</h2>
              <div className="observability-grid">
                <a href="/" className="obs-card" target="_blank" rel="noopener noreferrer"><strong>Web Shell</strong><span>React Flow graph + artifacts</span></a>
                <a href="http://localhost:4568" className="obs-card" target="_blank" rel="noopener noreferrer"><strong>Artifact Inspector</strong><span>Ruby/HTMX gallery with image previews</span></a>
                <a href="http://localhost:9090" className="obs-card" target="_blank" rel="noopener noreferrer"><strong>Prometheus</strong><span>rg_* metrics</span></a>
                <a href="http://localhost:3001" className="obs-card" target="_blank" rel="noopener noreferrer"><strong>Grafana</strong><span>Overview / Deep Dive / OCR Lab / Infra (via ingress grafana.rghw.localhost)</span></a>
                <a href="http://localhost:3100/ready" className="obs-card" target="_blank" rel="noopener noreferrer"><strong>Loki</strong><span>Logs via OTLP</span></a>
                <a href="http://localhost:3200/status" className="obs-card" target="_blank" rel="noopener noreferrer"><strong>Tempo</strong><span>Traces + service graph</span></a>
              </div>
              <div className="observability-hint">If Grafana shows “No data”, check <code>rg_runs_total</code> in Prometheus — orchestrator now exposes <code>/metrics</code> and OTLP metrics via <code>otel-collector:8889</code>. In k8s: <code>http://grafana.rghw.localhost</code>, <code>http://prometheus.rghw.localhost</code>, <code>http://tempo.rghw.localhost:3200</code>.</div>
            </section>
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
        @media (prefers-reduced-motion: reduce){.status-dot{animation:none}}
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
        .main-layout {
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }
        .telemetry-top {
          position: sticky;
          top: 0;
          z-index: 5;
          margin: 0;
          background: rgba(15,23,42,0.82);
          backdrop-filter: blur(14px);
          border: 1px solid rgba(255,255,255,0.12);
          border-radius: 14px;
          padding: 0.9rem 1rem;
          box-shadow: 0 8px 24px rgba(2,6,23,0.4);
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
        .telemetry-top { margin: 0; }
        .graph-section { margin: 0; flex: 1; min-height: 520px; }
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
        .metrics button:disabled { opacity: 0.5; cursor: not-allowed; box-shadow: none; }
        .artifact-count-hint { font-size: 0.75rem; opacity: 0.7; align-self: center; grid-column: span 2; }
        @media (max-height: 820px) {
          .graph-section { min-height: 420px; }
        }
        .telemetry-element-section, .observability-section {
          background: rgba(255,255,255,0.06);
          backdrop-filter: blur(10px);
          border: 1px solid rgba(255,255,255,0.1);
          border-radius: 14px;
          padding: 1rem;
          box-shadow: 0 8px 24px rgba(2,6,23,0.35);
        }
        .telemetry-element-wrap { display: grid; gap: 1rem; }
        .telemetry-fallback-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.5rem; font-size: 0.85rem; }
        .telemetry-fallback-grid > div { background: rgba(15,23,42,0.6); border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; padding: 0.5rem; }
        .artifact-thumbs { display: flex; gap: 0.5rem; flex-wrap: wrap; margin-top: 0.75rem; }
        .artifact-thumbs img { width: 96px; height: 64px; object-fit: contain; background: white; border-radius: 8px; padding: 4px; box-shadow: 0 2px 8px rgba(0,0,0,0.2); }
        .telemetry-links { margin-top: 0.75rem; font-size: 0.8rem; opacity: 0.8; }
        .telemetry-links a { color: #22d3ee; text-decoration: none; font-weight: 600; }
        .telemetry-links code { background: rgba(148,163,184,0.15); padding: 0.1rem 0.3rem; border-radius: 4px; }
        .observability-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.75rem; margin-top: 0.5rem; }
        .obs-card { display: flex; flex-direction: column; background: rgba(15,23,42,0.6); border: 1px solid rgba(255,255,255,0.08); border-radius: 10px; padding: 0.7rem 0.8rem; text-decoration: none; color: #e2e8f0; }
        .obs-card strong { font-size: 0.9rem; }
        .obs-card span { font-size: 0.75rem; opacity: 0.7; }
        .obs-card:hover { border-color: rgba(34,211,238,0.4); box-shadow: 0 4px 16px rgba(34,211,238,0.15); }
        .observability-hint { margin-top: 0.75rem; font-size: 0.8rem; opacity: 0.7; line-height: 1.4; }
        .observability-hint code { background: rgba(148,163,184,0.15); padding: 0.1rem 0.3rem; border-radius: 4px; }
        rg-telemetry-panel { display: block; min-height: 40px; }
      `}</style>
    </div>
  );
}

// Re-export parseSseFrame for potential use
export { parseSseFrame };
