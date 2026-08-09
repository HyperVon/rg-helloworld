# Documentation Diagrams

This directory contains rendered PNG images of architecture diagrams
referenced from the project documentation.

## Source files

- `high-level-architecture.mmd` — Mermaid flowchart of the full system
- `orchestrator-state-machine.mmd` — Mermaid state diagram of the orchestrator

## Regenerating images

If you update a diagram in `docs/architecture.md`, regenerate its PNG with:

```bash
mmdc -i docs/diagrams/high-level-architecture.mmd -o docs/diagrams/high-level-architecture.png
mmdc -i docs/diagrams/orchestrator-state-machine.mmd -o docs/diagrams/orchestrator-state-machine.png
```

Requires `@mermaid-js/mermaid-cli` (`mmdc`).

## Adding new diagrams

1. Add the Mermaid source block to `docs/architecture.md`.
2. Extract it to a `.mmd` file in this directory (strip the ```mermaid fences).
3. Render the PNG with `mmdc`.
4. Reference the PNG from the markdown with a relative path like `![...](high-level-architecture.png)`.
5. Add a regeneration note next to the markdown diagram block.
