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
- sends the completion request and acceptance telemetry for each run

Current fixture map:
- `fixtures/sample.ts`
- `fixtures/sample.md`
- `fixtures/sample.sh`
- `fixtures/sample.yaml`


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
- add `--accept-first` to simulate accepting the first suggestion

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

That will:
- request inline completions
- mark the first one as shown
- call `workspace/executeCommand` for the first completion item

## What the CLI sends

### Editor identity
The client identifies itself during `initialize` as:

```json
{
  "editorInfo": {
    "name": "neovim",
    "version": "0.10.0"
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

## Raw logs
This CLI prints raw client/server JSON-RPC messages to stdout so you can inspect exactly what happened.

That means it is ugly on purpose. Like a wrench. A beautiful, violent wrench.

## Caveats
- auth success can take a few seconds after the browser flow finishes
- the CLI does not patch the file on disk; it only asks the server for completions
- there is no visual-selection API here; this harness tests cursor-based inline completion
- if the server changes undocumented custom methods, this harness may need small updates
