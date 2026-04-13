# AGENTS.md

## Commands
- Install dependencies: `bun install`
- Typecheck: `bun run typecheck`
- Optional JS build: `bun run build`
- Auth status smoke test: `bun run auth:status`
- Start device-flow sign-in: `bun run auth:signin`
- Sign out: `bun run auth:signout`
- Request one completion: `bun run complete --file fixtures/sample.ts --line 8 --character 2`
- Request one completion and simulate acceptance: `bun run complete --file fixtures/sample.ts --line 8 --character 2 --accept-first`
- Run repeated weighted completion checks: `./scripts/run-random-completions.sh`

## Important project rules from existing docs
- Runtime is Bun-first. Normal usage should run `src/cli.ts` directly through Bun; do not require a prebuild for local workflows.
- The README examples are the source of truth for how this harness is expected to be used.
- The client reports itself to the Copilot language server as editor `neovim` by default. Preserve that unless the task explicitly changes editor identity behavior.
- Completion positions are zero-based `line` / `character` values.

## High-level architecture
This repo is a thin CLI harness around `@github/copilot-language-server`.

### Main flow
1. `src/cli.ts` parses a tiny command surface (`auth:*`, `complete`).
2. It creates `CopilotLspClient` from `src/copilot-lsp-client.ts`.
3. `CopilotLspClient` spawns the Copilot language server over stdio using the package’s `dist/language-server.js` entrypoint.
4. The client manually speaks LSP/JSON-RPC:
   - writes `Content-Length` framed messages
   - parses framed responses from stdout
   - tracks pending requests by numeric id
   - handles server notifications and selected server requests (`window/showDocument`)
5. For completion tests the client runs this sequence:
   - `initialize`
   - `initialized`
   - `workspace/didChangeConfiguration`
   - `textDocument/didOpen`
   - `textDocument/didFocus`
   - `textDocument/inlineCompletion`
   - optional `textDocument/didShowCompletion`
   - optional `workspace/executeCommand` for acceptance telemetry

### File responsibilities
- `src/cli.ts`
  - command parsing
  - validation of `--file`, `--line`, `--character`
  - top-level orchestration for auth and completion flows
  - prints raw results/status to stdout
- `src/copilot-lsp-client.ts`
  - owns the child process for the Copilot language server
  - implements JSON-RPC framing/parsing and request bookkeeping
  - stores last `didChangeStatus` notification
  - maps file extension to LSP `languageId`
  - wraps custom Copilot calls like `signIn`, `signOut`, `textDocument/didShowCompletion`, and completion acceptance telemetry
- `scripts/run-random-completions.sh`
  - batch runner for smoke-testing
  - uses weighted fixture selection: 80% TypeScript, 10% Markdown, 5% Bash, 5% YAML
- `fixtures/`
  - static sample inputs with known cursor positions for completion requests

## Things that are easy to miss
- The project does not edit files on disk; it only opens documents in-memory via LSP and requests suggestions.
- `complete --accept-first` does not apply the returned text to the fixture. It only sends Copilot “shown” and “accepted” telemetry-style events.
- Language support is extension-based in `detectLanguageId()`. If a new fixture type is added, update that mapping and the shell script together.
- Raw JSON-RPC logging is intentional and useful for debugging protocol regressions. Avoid removing it unless the task is specifically about changing logging behavior.
- `printHelp()` in `src/cli.ts` still mentions `node dist/cli.js`; if updating CLI UX or docs, keep runtime examples aligned with the Bun-first workflow.
- The random completion smoke-test script now defaults to 50 runs. When using it for an agent test run, always pass `1` as the first argument to keep runtime short: `./scripts/run-random-completions.sh 1`.

## When changing behavior
- If you change command names or flags, update both `README.md` and `scripts/run-random-completions.sh`.
- If you change the LSP initialization payload, verify the `editorInfo` / `editorPluginInfo` contract because that is central to this repo’s purpose.
- If you add new completion scenarios, prefer new fixture files plus documented cursor positions over embedding more ad-hoc logic in the CLI.
