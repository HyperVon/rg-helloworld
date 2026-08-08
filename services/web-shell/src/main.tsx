import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';
import 'reactflow/dist/style.css';
import { initTelemetry } from './telemetry.js';

void initTelemetry('web-shell');

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
