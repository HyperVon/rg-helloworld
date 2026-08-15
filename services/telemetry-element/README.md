# rg-telemetry-element

TypeScript Web Component telemetry custom element for Rube Goldberg Hello World.

Renders as `<rg-telemetry-panel run-id="...">` in the browser, independently
fetching telemetry data from the event gateway's SSE stream.

## Usage

```html
<rg-telemetry-panel run-id="01J..."></rg-telemetry-panel>
```

## Build & Test

```bash
npm install
npm run build
npm test
```
