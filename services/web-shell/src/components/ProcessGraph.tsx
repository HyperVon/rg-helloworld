import { useState } from 'react';
import ReactFlow, { Background, Controls } from 'reactflow';
import 'reactflow/dist/style.css';
import type { GraphNode } from '../types';
import { PROCESS_EDGES, PROCESS_NODE_POSITIONS, getGraphNodes } from '../lib/stages';

interface ProcessGraphProps {
  currentStage: string;
  terminal: boolean;
  runStatus: string;
  glyphCount?: number;
}

export function ProcessGraph({ currentStage, terminal, runStatus, glyphCount }: ProcessGraphProps) {
  const nodes = getGraphNodes(currentStage, terminal, runStatus, glyphCount);

  const reduceMotion =
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const nodeComponents = nodes.map((n) => ({
    id: n.id,
    type: 'default',
    data: {
      label: (
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontWeight: 'bold', fontSize: '12px' }}>{n.label}</div>
          <div style={{ fontSize: '10px', color: statusColor(n.status) }}>{n.status}</div>
          {n.glyphPositions && n.glyphPositions.length > 0 && (
            <div style={{ fontSize: '9px', color: '#666' }}>{n.glyphPositions.length} glyphs</div>
          )}
        </div>
      ),
    },
    position: PROCESS_NODE_POSITIONS[n.id],
    style: {
      border: `2px solid ${statusColor(n.status)}`,
      borderRadius: '8px',
      backgroundColor: statusBg(n.status),
      padding: '8px',
      minWidth: '120px',
    },
  }));

  const edgeComponents = PROCESS_EDGES.map((e) => ({
    id: `e-${e.source}-${e.target}`,
    source: e.source,
    target: e.target,
    animated: !reduceMotion,
    type: 'smoothstep',
    style: { stroke: '#94a3b8', strokeWidth: 1.25 },
    pathOptions: { borderRadius: 14, offset: 12 },
  }));

  const nodeTypes = {}; // placeholder for future custom nodes

  return (
    <div style={{ width: '100%', height: '360px' }}>
      <ReactFlow
        nodes={nodeComponents}
        edges={edgeComponents}
        fitView
        fitViewOptions={{ padding: 0.14, includeHiddenNodes: false }}
        attributionPosition="bottom-left"
        defaultViewport={{ x: 0, y: 0, zoom: 0.95 }}
        minZoom={0.5}
        maxZoom={1.5}
      >
        <Background gap={18} size={1} />
        <Controls />
      </ReactFlow>
    </div>
  );
}

function statusColor(status: GraphNode['status']): string {
  switch (status) {
    case 'completed':
      return '#10b981';
    case 'running':
      return '#f59e0b';
    case 'failed':
      return '#ef4444';
    default:
      return '#9ca3af';
  }
}

function statusBg(status: GraphNode['status']): string {
  switch (status) {
    case 'completed':
      return '#dcfce7';
    case 'running':
      return '#fef3c7';
    case 'failed':
      return '#fee2e2';
    default:
      return '#f3f4f6';
  }
}
