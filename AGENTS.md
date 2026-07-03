# AGENTS.md

## Commands

```bash
# Backend (run from backend/)
go test ./...
go build -o /tmp/algoroute .

# Frontend (run from frontend/)
npm test        # vitest watch mode
npm run typecheck
```

## Critical Skills (apply without asking)

- **clean-code**: descriptive naming, self-documenting code
- **test-driven-development**: write failing test first, then minimal code to pass

## Conventions

- Test packages use `_test` suffix; external tests in `tests/` subdirectories
- Test helpers prefixed `must` (e.g., `mustAddNode`)
- Errors wrapped: `fmt.Errorf("context: %w", err)`
- All Go source formatted with `gofmt`

## Running the App

```bash
# Terminal 1 — backend
cd backend && go build -o /tmp/algoroute . && /tmp/algoroute -serve -port 8080

# Terminal 2 — frontend dev
cd frontend && npm run dev
```

## Project State

See `PROJECT_STATE.md` for component status and test counts.