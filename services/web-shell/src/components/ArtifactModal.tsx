import { useState } from 'react';
import type { ArtifactNode } from '../types';

interface ArtifactModalProps {
  artifacts: ArtifactNode[];
  onClose: () => void;
}

export function ArtifactModal({ artifacts, onClose }: ArtifactModalProps) {
  const [selected, setSelected] = useState<ArtifactNode | null>(null);

  return (
    <div className="artifact-modal-backdrop" onClick={onClose}>
      <div className="artifact-modal" onClick={(e) => e.stopPropagation()}>
        <h3>Artifacts {artifacts.length > 0 ? `(${artifacts.length})` : ''}</h3>
        {artifacts.length === 0 ? (
          <div className="artifact-empty">
            No artifacts returned — orchestrator may still be finalizing or the run has no
            stored artifacts. Try the Artifact Inspector or check that the run reached
            SUCCEEDED.
          </div>
        ) : (
          <div className="artifact-list">
            {artifacts.map((a) => (
              <div
                key={a.id}
                className={`artifact-item ${selected?.id === a.id ? 'selected' : ''}`}
                onClick={() => setSelected(a)}
              >
                <span className="artifact-id">{a.id}</span>
                <span className="artifact-stage">{a.stage}</span>
                <span className="artifact-sha" title={a.sha256}>
                  {a.sha256.slice(0, 8)}…
                </span>
              </div>
            ))}
          </div>
        )}
        {selected && (
          <div className="artifact-detail">
            <p>
              <strong>ID:</strong> {selected.id}
            </p>
            <p>
              <strong>Stage:</strong> {selected.stage}
            </p>
            <p>
              <strong>SHA-256:</strong> {selected.sha256}
            </p>
            <p>
              <strong>Type:</strong> {selected.contentType || 'application/octet-stream'}
            </p>
            {selected.proxyUrl && (
              <a href={selected.proxyUrl} target="_blank" rel="noopener noreferrer">
                View artifact
              </a>
            )}
          </div>
        )}
        <button onClick={onClose}>Close</button>
        <style>{`
          .artifact-modal-backdrop {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
          }
          .artifact-modal {
            background: #0f172a;
            color: #e2e8f0;
            border: 1px solid rgba(255,255,255,0.12);
            border-radius: 12px;
            padding: 1.5rem;
            max-width: 640px;
            width: min(92vw, 640px);
            max-height: 70vh;
            overflow: auto;
            box-shadow: 0 20px 60px rgba(0,0,0,0.6);
          }
          .artifact-modal h3 { margin: 0 0 0.75rem; }
          .artifact-empty {
            padding: 1rem;
            background: rgba(255,255,255,0.06);
            border: 1px dashed rgba(255,255,255,0.14);
            border-radius: 8px;
            font-size: 0.9rem;
            opacity: 0.85;
            line-height: 1.45;
          }
          .artifact-list {
            max-height: 300px;
            overflow-y: auto;
            border: 1px solid #e5e7eb;
            border-radius: 4px;
          }
          .artifact-item {
            display: flex;
            gap: 0.5rem;
            padding: 0.5rem;
            cursor: pointer;
            border-bottom: 1px solid #f3f4f6;
          }
          .artifact-item:hover {
            background: #f9fafb;
          }
          .artifact-item.selected {
            background: #dbeafe;
          }
          .artifact-id {
            font-family: monospace;
            font-size: 0.8rem;
          }
          .artifact-stage {
            font-size: 0.8rem;
            color: #6b7280;
          }
          .artifact-sha {
            font-family: monospace;
            font-size: 0.8rem;
            color: #9ca3af;
            margin-left: auto;
          }
          .artifact-detail {
            margin-top: 1rem;
            padding-top: 1rem;
            border-top: 1px solid #e5e7eb;
          }
        `}</style>
      </div>
    </div>
  );
}
