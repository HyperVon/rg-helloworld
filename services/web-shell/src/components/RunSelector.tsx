import { useState } from 'react';

interface RunListItem {
  runId: string;
  status: string;
  createdAt: string;
  message?: string;
}

interface RunSelectorProps {
  onSelectRun: (runId: string) => void;
  currentRunId: string | null;
  availableRuns?: RunListItem[];
}

export function RunSelector({ onSelectRun, currentRunId, availableRuns = [] }: RunSelectorProps) {
  const [inputValue, setInputValue] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = inputValue.trim();
    if (trimmed) {
      onSelectRun(trimmed);
    }
  };

  const handleSelectChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const v = e.target.value;
    if (v) onSelectRun(v);
  };

  const handleClear = () => {
    setInputValue('');
    try {
      localStorage.removeItem('rghw:lastRunId');
    } catch {}
    // reload to clear selection; parent will clear runId on next render if we force
    // for now, just reload page to reset
    window.location.reload();
  };

  return (
    <div className="run-selector">
      {availableRuns.length > 0 ? (
        <>
          <select value={currentRunId ?? ''} onChange={handleSelectChange} aria-label="Select run">
            <option value="" disabled>
              {currentRunId ? `Viewing: ${currentRunId.slice(0, 8)}…` : 'Select a run — auto-loaded latest'}
            </option>
            {availableRuns.map((r) => (
              <option key={r.runId} value={r.runId}>
                {r.runId.slice(0, 8)}… — {r.status} — {new Date(r.createdAt).toLocaleString()}
              </option>
            ))}
          </select>
          <span className="current-run" title={currentRunId ?? ''}>
            {currentRunId ? `Viewing: ${currentRunId}` : `Auto-selected latest of ${availableRuns.length}`}
          </span>
          {currentRunId && (
            <button type="button" onClick={handleClear} className="clear-btn">
              Clear
            </button>
          )}
        </>
      ) : null}
      {availableRuns.length > 0 ? (
        <details style={{ flex: 1 }}>
          <summary style={{ cursor: 'pointer', fontSize: '0.85rem', opacity: 0.7 }}>Or enter run ID manually</summary>
          <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem' }}>
            <input
              type="text"
              value={inputValue}
              placeholder="Enter run ID..."
              onChange={(e) => setInputValue(e.target.value)}
            />
            <button type="submit" disabled={!inputValue.trim()}>
              Go →
            </button>
          </form>
        </details>
      ) : (
        <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '0.5rem', flex: 1 }}>
          <input
            type="text"
            value={inputValue}
            placeholder="Enter run ID..."
            onChange={(e) => setInputValue(e.target.value)}
          />
          <button type="submit" disabled={!inputValue.trim()}>
            Load Run
          </button>
        </form>
      )}
      {!availableRuns.length && !currentRunId && (
        <span className="hint">No runs yet — run <code>./rghw.sh</code> or <code>rghw run</code></span>
      )}
      <style>{`
        .run-selector {
          display: flex;
          gap: 0.5rem;
          align-items: center;
          padding: 0.5rem;
          border-bottom: 1px solid #e5e7eb;
        }
        .run-selector input {
          flex: 1;
          padding: 0.5rem;
          border: 1px solid #d1d5db;
          border-radius: 4px;
        }
        .run-selector button {
          padding: 0.5rem 1rem;
          background: #3b82f6;
          color: white;
          border: none;
          border-radius: 4px;
          cursor: pointer;
        }
        .run-selector button:disabled {
          background: #9ca3af;
          cursor: not-allowed;
        }
        .current-run {
          font-size: 0.875rem;
          color: #6b7280;
        }
        .hint { font-size: 0.8rem; color: #6b7280; }
        select { padding: 0.4rem; border: 1px solid #d1d5db; border-radius: 4px; }
        .clear-btn { background: #ef4444; }
      `}</style>
    </div>
  );
}
