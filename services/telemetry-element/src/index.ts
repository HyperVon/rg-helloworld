import type {
  TelemetryData,
  RunStatus,
  StepLedgerEntry,
  AttemptEntry,
  OcrConfidenceEntry,
  RunSummary,
} from './types.js';
import { applyRunResult, applySnapshot, applyStepEvent } from './handlers.js';

export const SERVICE_NAME = 'telemetry-element';
export const SERVICE_VERSION = '0.5.0-milestone11';

export function banner(): string {
  return `${SERVICE_NAME} ${SERVICE_VERSION} (Milestone 11)`;
}

export function formatStepType(stepType: string): string {
  return stepType
    .replace(/_/g, ' ')
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export function isRunning(status: RunStatus): boolean {
  return !['SUCCEEDED', 'FAILED', 'CANCELLED'].includes(status);
}

export function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60000).toFixed(1)}m`;
}

export function averageConfidence(entries: OcrConfidenceEntry[]): number {
  if (entries.length === 0) return 0;
  return entries.reduce((sum, e) => sum + e.confidence, 0) / entries.length;
}

export function minConfidence(entries: OcrConfidenceEntry[]): number {
  if (entries.length === 0) return 0;
  return Math.min(...entries.map((e) => e.confidence));
}

export function renderStepRow(e: StepLedgerEntry): string {
  return `
    <tr>
      <td>${formatStepType(e.stepType)}</td>
      <td>${e.glyphPosition ?? '—'}</td>
      <td>${e.status}</td>
      <td>${formatDuration(e.durationMs)}</td>
    </tr>
  `;
}

export function renderAttemptRow(a: AttemptEntry): string {
  return `
    <tr>
      <td>${a.attempt}</td>
      <td>${new Date(a.startedAt).toLocaleString()}</td>
      <td>${formatDuration(a.durationMs)}</td>
      <td>${a.result}</td>
    </tr>
  `;
}

export function renderTemplate(data: TelemetryData | null): string {
  if (!data) {
    return '<div class="telemetry-panel">Loading run…</div>';
  }
  const stepRows = data.stepLedger.map(renderStepRow).join('');
  const attemptRows = data.attempts.map(renderAttemptRow).join('');
  return `
      <div class="telemetry-panel">
        <h3>Run ${data.runId}</h3>
        <p>Status: <span class="status ${data.status}">${data.status}</span></p>
        <p>Kafka events: ${data.kafkaEventCount}</p>
        <div class="section">
          <h4>Step Ledger</h4>
          <table>
            <thead><tr><th>Step</th><th>Position</th><th>Status</th><th>Duration</th></tr></thead>
            <tbody>
              ${stepRows}
            </tbody>
          </table>
        </div>
        <div class="section">
          <h4>Attempts</h4>
          <table>
            <thead><tr><th>#</th><th>Started</th><th>Duration</th><th>Result</th></tr></thead>
            <tbody>
              ${attemptRows}
            </tbody>
          </table>
        </div>
        <div class="section">
          <h4>OCR Confidence</h4>
          <p>Min: ${minConfidence(data.ocrConfidences).toFixed(2)} | Avg: ${averageConfidence(data.ocrConfidences).toFixed(2)}</p>
        </div>
        <div class="section">
          <h4>Resource Usage</h4>
          <p>CPU: ${data.resourceUsage.cpu}% | Memory: ${data.resourceUsage.memory}%</p>
        </div>
        <style>
          .telemetry-panel { font-family: sans-serif; padding: 1rem; }
          .section { margin: 1rem 0; }
          .status { font-weight: bold; }
          .status.SUCCEEDED { color: #10b981; }
          .status.FAILED { color: #ef4444; }
          table { width: 100%; border-collapse: collapse; }
          th, td { text-align: left; padding: 0.25rem; border-bottom: 1px solid #e5e7eb; }
        </style>
      </div>
    `;
}

type TelemetryPanelBase = {
  new (): {
    attachShadow: (opts: { mode: string }) => { innerHTML: string };
    getAttribute: (name: string) => string | null;
    setAttribute: (name: string, value: string) => void;
  };
  prototype: {
    attachShadow: (opts: { mode: string }) => { innerHTML: string };
    getAttribute: (name: string) => string | null;
    setAttribute: (name: string, value: string) => void;
  };
};

let HTMLElementBase: TelemetryPanelBase;
let _customElements: { define?: (name: string, ctor: TelemetryPanelBase) => void };

class _StubElement {
  private _attrs: Record<string, string> = {};
  attachShadow(_opts: { mode: string }): { innerHTML: string } {
    return { innerHTML: '' };
  }
  getAttribute(name: string): string | null {
    return this._attrs[name] ?? null;
  }
  setAttribute(name: string, value: string): void {
    this._attrs[name] = value;
  }
}

if (typeof HTMLElement !== 'undefined') {
  HTMLElementBase = HTMLElement as unknown as TelemetryPanelBase;
  _customElements = customElements as any;
} else {
  HTMLElementBase = _StubElement as unknown as TelemetryPanelBase;
  _customElements = { define: () => {} };
}

export class TelemetryPanel extends HTMLElementBase {
  static get observedAttributes() {
    return ['run-id'];
  }

  private runId: string | null = null;
  private data: TelemetryData | null = null;
  private sse: any = null;

  connectedCallback() {
    this.render();
    this.runId = this.getAttribute('run-id');
    if (this.runId !== null && typeof EventSource !== 'undefined') {
      this.connectStream();
    }
  }

  disconnectedCallback() {
    if (this.sse) {
      this.sse.close();
      this.sse = null;
    }
  }

  attributeChangedCallback(name: string, _oldValue: string | null, newValue: string | null) {
    if (name === 'run-id') {
      this.runId = newValue;
      if (this.runId !== null && typeof EventSource !== 'undefined') {
        this.connectStream();
      }
    }
  }

  private connectStream() {
    if (!this.runId) return;
    if (this.sse) this.sse.close();
    this.sse = new EventSource(`/api/v1/runs/${this.runId}/stream`);

    this.sse.addEventListener('snapshot', (ev: MessageEvent) => {
      const summary = JSON.parse(ev.data) as RunSummary;
      this.updateData((prev) => applySnapshot(prev, summary, this.runId!));
    });

    this.sse.addEventListener('step-status-changed', (ev: MessageEvent) => {
      const msg = JSON.parse(ev.data) as Record<string, unknown>;
      this.updateData((prev) => applyStepEvent(prev, msg));
    });

    this.sse.addEventListener('run-succeeded', () => {
      this.updateData((prev) => applyRunResult(prev, 'SUCCEEDED'));
    });

    this.sse.addEventListener('run-failed', () => {
      this.updateData((prev) => applyRunResult(prev, 'FAILED'));
    });

    this.sse.addEventListener('heartbeat', () => {});
  }

  private updateData(updater: (prev: TelemetryData | null) => TelemetryData | null) {
    this.data = updater(this.data);
    this.render();
  }

  private render() {
    const shadow = this.attachShadow({ mode: 'open' });
    shadow.innerHTML = renderTemplate(this.data);
  }
}

const _global = globalThis as Record<string, unknown> & { __rgTelemetryRegistered?: boolean };

if (typeof customElements !== 'undefined' && typeof customElements.define === 'function') {
  if (!_global.__rgTelemetryRegistered) {
    _global.__rgTelemetryRegistered = true;
    try {
      (_customElements.define as any)('rg-telemetry-panel', TelemetryPanel);
    } catch {
      // already defined or environment doesn't support it
    }
  }
}
