# copilot-lsp-stats

Tiny CLI harness for testing `@github/copilot-language-server` against a TypeScript file.

It does three useful things:
- starts the Copilot language server over stdio
- reports the editor as `neovim`
- lets you authenticate and request inline completions from the CLI

## Requirements
- Bun
- Node.js `>= 20.8`
- A GitHub account with Copilot access
- GitHub CLI authenticated with `gh auth login`, or a `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN` environment variable for `void-run.sh`

## Install

```bash
bun install
```

Normal usage does not require a build step. Bun runs the TypeScript CLI directly.

Optional typecheck:

```bash
bun run typecheck
```

## Commands

### Run random completion tests

```bash
./scripts/run-random-completions.sh 10
```

This script now uses Bun under the hood, so no prebuild is needed.

What it does:
- takes one numeric argument for run count
- randomly picks one fixture each run
- uses weighted selection:
  - 80% TypeScript
  - 10% Markdown
  - 5% Bash
  - 5% YAML
- sends the completion request for each run
- sends acceptance telemetry for about 90% of runs

Current fixture map:
- `fixtures/sample.ts`
- `fixtures/sample.md`
- `fixtures/sample.sh`
- `fixtures/sample.yaml`

### Generate random files with Copilot

```bash
./scripts/void-run.sh
```

What it does:
- picks one output format using weighted selection
- asks Copilot to generate more lines than needed
- runs Copilot from an isolated temporary working directory
- gives Copilot a fresh temporary `COPILOT_HOME`, which is deleted after the run along with its session state, logs, MCP configuration, and installed plugins
- does not load user-installed plugins or custom instruction files
- disables built-in MCP servers and remote session features
- gets authentication from an existing token environment variable or the authenticated GitHub CLI; the token is not written to the temporary Copilot home or debug log
- asks Copilot to write the generated content directly into `void/`
- checks that the written file has at least `TARGET_LINES` lines
- prints the temp work dir, `tree`, `head`, and `tail` for a quick visual check
- writes debug output to `void/void-run-debug.log`

Current format weights:
- 45% TypeScript
- 10% JavaScript
- 10% Python
- 10% Markdown
- 10% Lua
- 8% JSON
- 7% YAML

Environment variables:
- `TARGET_LINES` controls how many lines are required and saved
- `PROMPT_MIN_LINES` controls how many lines the prompt asks Copilot to generate

Examples:

```bash
./scripts/void-run.sh
TARGET_LINES=150 ./scripts/void-run.sh
TARGET_LINES=150 PROMPT_MIN_LINES=180 ./scripts/void-run.sh
```

### Check status

```bash
bun run auth:status
```

### Sign in

```bash
bun run auth:signin
```

What happens:
1. the CLI starts the language server
2. it sends `signIn`
3. the server returns a `userCode`
4. the CLI executes the follow-up command returned by the server
5. the browser should open to GitHub auth
6. once auth finishes, the server should emit a new status

If the browser does not open automatically, copy the `verificationUri` and `userCode` from the printed response and finish the flow manually.

### Sign out

```bash
bun run auth:signout
```

### Request a completion for a TypeScript file

```bash
bun run complete --file fixtures/sample.ts --line 7 --character 2
```

Notes:
- `line` and `character` are **zero-based**
- the file is opened as a TypeScript document
- the client sends `textDocument/didShowCompletion` for the first result
- add `--accept-first` to always accept the first suggestion
- add `--accept-rate <0-100>` to accept the first suggestion at a percentage rate
- add `--accept-mode partial` to simulate partial acceptance; the default mode is `full`
- add `--type-text <text>` to simulate typing at the requested position
- add `--type-delay-ms <ms>` to delay between simulated characters

## Good test example

The sample TypeScript file contains this function:

```ts
export const printGreeting = (name: string): void => {
  const greeting = buildGreeting(name);
  
};
```

The most useful test is to ask for a completion on the blank line after `greeting`.

Run:

```bash
bun run complete --file fixtures/sample.ts --line 8 --character 2
```

You should get a response with an `items` array. A likely suggestion would be something like:

```ts
console.log(greeting);
```

If you want to simulate the user accepting the first suggestion too:

```bash
bun run complete --file fixtures/sample.ts --line 8 --character 2 --accept-first
```

If you want to simulate partial acceptance while keeping a percentage-based acceptance rate:

```bash
bun run complete --file fixtures/sample.ts --line 8 --character 2 --accept-rate 65 --accept-mode partial
```

That will:
- request inline completions
- mark the first one as shown
- accept the first completion 65% of the time
- call `workspace/executeCommand` for full acceptance when the item provides a command
- send `textDocument/didPartiallyAcceptCompletion` for partial acceptance or items without a command
- update the in-memory document and send `textDocument/didChange` after acceptance

To simulate typing before requesting a completion:

```bash
bun run complete \
  --file fixtures/sample.ts \
  --line 8 \
  --character 2 \
  --type-text "const message = " \
  --type-delay-ms 45 \
  --accept-rate 65
```

Each simulated character sends an incremental `textDocument/didChange` notification. The completion request uses the updated document version and cursor position.

## What the CLI sends

### Editor identity
The client identifies itself during `initialize` as:

```json
{
  "editorInfo": {
    "name": "Neovim",
    "version": "0.12.1"
  },
  "editorPluginInfo": {
    "name": "copilot.vim",
    "version": "1.59.0"
  }
}
```

You can override the version:

```bash
bun run complete --file fixtures/sample.ts --line 8 --character 2 --editor-version 0.11.0
```

### LSP flow used by the CLI
For completion testing, the client does this:
1. `initialize`
2. `initialized`
3. `workspace/didChangeConfiguration`
4. `textDocument/didOpen`
5. `textDocument/didFocus`
6. `textDocument/inlineCompletion`
7. `textDocument/didShowCompletion`
8. acceptance telemetry (`workspace/executeCommand` or `textDocument/didPartiallyAcceptCompletion`)
9. `textDocument/didChange` after an accepted completion
10. `textDocument/didClose` and LSP shutdown when the CLI exits

## Raw logs
This CLI prints raw client/server JSON-RPC messages to stdout so you can inspect exactly what happened.

That means it is ugly on purpose. Like a wrench. A beautiful, violent wrench.

## Caveats
- auth success can take a few seconds after the browser flow finishes
- the CLI does not patch the file on disk; accepted completions update the in-memory document and emit `textDocument/didChange`
- there is no visual-selection API here; this harness tests cursor-based inline completion
- if the server changes undocumented custom methods, this harness may need small updates
