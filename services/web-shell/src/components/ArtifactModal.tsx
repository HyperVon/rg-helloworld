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
        <h3>Artifacts</h3>
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
            background: white;
            border-radius: 8px;
            padding: 1.5rem;
            max-width: 600px;
            max-height: 70vh;
            overflow: auto;
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
