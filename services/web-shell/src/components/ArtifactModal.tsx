import { useState, useEffect } from 'react';
import type { ArtifactNode } from '../types';

interface ArtifactModalProps {
  artifacts: ArtifactNode[];
  onClose: () => void;
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

function resolvedUrl(proxyUrl: string | null): string | null {
  if (!proxyUrl) return null;
  if (proxyUrl.startsWith('http://') || proxyUrl.startsWith('https://')) return proxyUrl;
  return `${apiBase()}${proxyUrl}`;
}

function isImageType(ct: string | null): boolean {
  if (!ct) return false;
  return ct.startsWith('image/');
}

function isSvgType(ct: string | null, url: string | null): boolean {
  if (ct === 'image/svg+xml') return true;
  if (url && url.endsWith('.svg')) return true;
  return false;
}

export function ArtifactModal({ artifacts, onClose }: ArtifactModalProps) {
  const [selected, setSelected] = useState<ArtifactNode | null>(null);
  const [lightbox, setLightbox] = useState<string | null>(null);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });

  useEffect(() => {
    if (selected) return;
    if (artifacts.length > 0 && !selected) setSelected(artifacts[0]);
  }, [artifacts, selected]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (lightbox) setLightbox(null);
        else onClose();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [lightbox, onClose]);

  return (
    <div className="artifact-modal-backdrop" onClick={onClose}>
      <div className="artifact-modal" onClick={(e) => e.stopPropagation()}>
        <h3>Artifacts {artifacts.length > 0 ? `(${artifacts.length})` : ''}</h3>
        {artifacts.length === 0 ? (
          <div className="artifact-empty">
            No artifacts returned — orchestrator may still be finalizing or the run has no stored
            artifacts. Try the Artifact Inspector or check that the run reached SUCCEEDED.
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
            <div className="artifact-detail-grid">
              <div className="artifact-meta">
                <p>
                  <strong>ID:</strong> {selected.id}
                </p>
                <p>
                  <strong>Stage:</strong> {selected.stage}
                </p>
                <p>
                  <strong>SHA-256:</strong> <code title={selected.sha256}>{selected.sha256}</code>
                </p>
                <p>
                  <strong>Type:</strong> {selected.contentType || 'application/octet-stream'}
                </p>
                {selected.proxyUrl && (
                  <p className="artifact-actions">
                    <a
                      href={resolvedUrl(selected.proxyUrl) || selected.proxyUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Open original ↗
                    </a>
                    {isImageType(selected.contentType) && (
                      <button
                        type="button"
                        className="lightbox-btn"
                        onClick={() => {
                          setZoom(1);
                          setOffset({ x: 0, y: 0 });
                          setLightbox(resolvedUrl(selected.proxyUrl) || selected.proxyUrl);
                        }}
                      >
                        Zoom / Lightbox
                      </button>
                    )}
                  </p>
                )}
              </div>
              {isImageType(selected.contentType) && selected.proxyUrl && (
                <div className="artifact-preview">
                  <img
                    src={resolvedUrl(selected.proxyUrl) || selected.proxyUrl}
                    alt={`${selected.stage} preview`}
                    className={
                      isSvgType(selected.contentType, selected.proxyUrl)
                        ? 'preview-svg'
                        : 'preview-img'
                    }
                    loading="lazy"
                    onClick={() => {
                      setZoom(1);
                      setOffset({ x: 0, y: 0 });
                      setLightbox(resolvedUrl(selected.proxyUrl) || selected.proxyUrl);
                    }}
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = 'none';
                      const fallback = (e.target as HTMLImageElement)
                        .nextElementSibling as HTMLElement | null;
                      if (fallback) fallback.style.display = 'block';
                    }}
                  />
                  <div className="preview-error" style={{ display: 'none' }}>
                    Preview unavailable —{' '}
                    <a
                      href={resolvedUrl(selected.proxyUrl) || selected.proxyUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      open original
                    </a>
                  </div>
                  <div className="preview-hint">Click image to enlarge</div>
                </div>
              )}
              {!isImageType(selected.contentType) &&
                selected.contentType?.includes('json') &&
                selected.proxyUrl && (
                  <div className="artifact-preview artifact-json-hint">
                    JSON artifact —{' '}
                    <a
                      href={resolvedUrl(selected.proxyUrl) || selected.proxyUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      view raw
                    </a>
                  </div>
                )}
            </div>
          </div>
        )}
        <div className="artifact-modal-actions">
          <span className="artifact-hint">
            {artifacts.length} artifact{artifacts.length === 1 ? '' : 's'} • click list to inspect •
            images open in lightbox with zoom/pan
          </span>
          <button onClick={onClose}>Close</button>
        </div>
        {lightbox && (
          <div className="lightbox-backdrop" onClick={() => setLightbox(null)}>
            <div
              className="lightbox"
              onClick={(e) => e.stopPropagation()}
              onWheel={(e) => {
                const delta = e.deltaY > 0 ? -0.1 : 0.1;
                setZoom((z) => Math.min(4, Math.max(0.5, +(z + delta).toFixed(1))));
              }}
            >
              <div className="lightbox-bar">
                <span>Zoom: {zoom.toFixed(1)}× • scroll to zoom • drag to pan • Esc to close</span>
                <button type="button" onClick={() => setLightbox(null)}>
                  ×
                </button>
              </div>
              <div
                className="lightbox-stage"
                onMouseDown={(e) => {
                  setDragging(true);
                  setDragStart({ x: e.clientX - offset.x, y: e.clientY - offset.y });
                }}
                onMouseMove={(e) => {
                  if (!dragging) return;
                  setOffset({ x: e.clientX - dragStart.x, y: e.clientY - dragStart.y });
                }}
                onMouseUp={() => setDragging(false)}
                onMouseLeave={() => setDragging(false)}
              >
                <img
                  src={lightbox}
                  alt="lightbox"
                  style={{
                    transform: `translate(${offset.x}px, ${offset.y}px) scale(${zoom})`,
                    cursor: dragging ? 'grabbing' : 'grab',
                  }}
                  draggable={false}
                />
              </div>
              <div className="lightbox-controls">
                <button
                  type="button"
                  onClick={() => setZoom((z) => Math.max(0.5, +(z - 0.2).toFixed(1)))}
                >
                  −
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setZoom(1);
                    setOffset({ x: 0, y: 0 });
                  }}
                >
                  Reset
                </button>
                <button
                  type="button"
                  onClick={() => setZoom((z) => Math.min(4, +(z + 0.2).toFixed(1)))}
                >
                  +
                </button>
                <a
                  href={lightbox}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="lightbox-open"
                >
                  Open original ↗
                </a>
              </div>
            </div>
          </div>
        )}
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
            border-top: 1px solid rgba(255,255,255,0.12);
          }
          .artifact-detail-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            align-items: start;
          }
          @media (max-width: 720px) { .artifact-detail-grid { grid-template-columns: 1fr; } }
          .artifact-meta p { margin: 0.25rem 0; font-size: 0.9rem; word-break: break-all; }
          .artifact-meta code { background: rgba(148,163,184,0.15); padding: 0.1rem 0.35rem; border-radius: 4px; font-size: 0.8rem; }
          .artifact-actions { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
          .artifact-actions a { color: #22d3ee; font-weight: 600; text-decoration: none; }
          .lightbox-btn { background: linear-gradient(90deg,#8b5cf6,#06b6d4); color: white; border: 0; border-radius: 8px; padding: 0.35rem 0.7rem; font-weight: 700; cursor: pointer; }
          .artifact-preview { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.1); border-radius: 10px; padding: 0.5rem; text-align: center; }
          .artifact-preview img { max-width: 100%; max-height: 260px; object-fit: contain; border-radius: 8px; background: white; cursor: zoom-in; box-shadow: 0 4px 16px rgba(0,0,0,0.25); }
          .preview-svg { background: white; padding: 8px; }
          .preview-error { font-size: 0.85rem; opacity: 0.8; margin-top: 0.5rem; }
          .preview-hint { font-size: 0.75rem; opacity: 0.6; margin-top: 0.35rem; }
          .artifact-json-hint { font-size: 0.85rem; opacity: 0.8; padding: 0.75rem; }
          .artifact-json-hint a { color: #22d3ee; }
          .artifact-modal-actions { display: flex; justify-content: space-between; align-items: center; margin-top: 1rem; gap: 1rem; }
          .artifact-hint { font-size: 0.75rem; opacity: 0.6; }
          .artifact-modal-actions button { background: linear-gradient(90deg,#334155,#475569); color: white; border: 0; border-radius: 8px; padding: 0.5rem 1rem; font-weight: 700; cursor: pointer; white-space: nowrap; }
          .lightbox-backdrop { position: fixed; inset: 0; background: rgba(2,6,23,0.88); display: flex; align-items: center; justify-content: center; z-index: 1100; padding: 1rem; }
          .lightbox { background: #0f172a; border: 1px solid rgba(255,255,255,0.12); border-radius: 14px; overflow: hidden; width: min(96vw, 1100px); max-height: 92vh; display: flex; flex-direction: column; box-shadow: 0 20px 60px rgba(0,0,0,0.6); }
          .lightbox-bar { display: flex; justify-content: space-between; align-items: center; padding: 0.6rem 0.8rem; background: rgba(255,255,255,0.06); border-bottom: 1px solid rgba(255,255,255,0.1); font-size: 0.85rem; }
          .lightbox-bar button { background: rgba(255,255,255,0.12); border: 0; color: #e2e8f0; border-radius: 8px; width: 32px; height: 32px; font-size: 1.1rem; cursor: pointer; }
          .lightbox-stage { flex: 1; overflow: hidden; display: grid; place-items: center; background: #020617; min-height: 400px; padding: 1rem; user-select: none; }
          .lightbox-stage img { max-width: 100%; max-height: 70vh; object-fit: contain; background: white; border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.35); }
          .lightbox-controls { display: flex; gap: 0.5rem; align-items: center; justify-content: center; padding: 0.6rem; background: rgba(255,255,255,0.04); border-top: 1px solid rgba(255,255,255,0.08); }
          .lightbox-controls button { background: rgba(255,255,255,0.12); border: 0; color: #e2e8f0; border-radius: 8px; padding: 0.45rem 0.75rem; font-weight: 700; cursor: pointer; }
          .lightbox-open { margin-left: 0.5rem; color: #22d3ee; font-weight: 600; text-decoration: none; font-size: 0.85rem; }
        `}</style>
      </div>
    </div>
  );
}
