import { useState } from 'react';

interface RunSelectorProps {
  onSelectRun: (runId: string) => void;
  currentRunId: string | null;
}

export function RunSelector({ onSelectRun, currentRunId }: RunSelectorProps) {
  const [inputValue, setInputValue] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = inputValue.trim();
    if (trimmed) {
      onSelectRun(trimmed);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="run-selector">
      <input
        type="text"
        value={inputValue}
        placeholder="Enter run ID..."
        onChange={(e) => setInputValue(e.target.value)}
        disabled={!!currentRunId}
      />
      <button type="submit" disabled={!!currentRunId || !inputValue.trim()}>
        Load Run
      </button>
      {currentRunId && <span className="current-run">Viewing: {currentRunId}</span>}
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
      `}</style>
    </form>
  );
}
