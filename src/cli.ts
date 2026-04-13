import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { CopilotLspClient, type InlineCompletionItem } from './copilot-lsp-client';

type CliOptions = {
  file?: string;
  line?: number;
  character?: number;
  workspace?: string;
  editorVersion: string;
  acceptFirst: boolean;
};

const parseArgs = (argv: string[]): { command: string; options: CliOptions } => {
  const [command = 'help', ...rest] = argv;
  const options: CliOptions = {
    editorVersion: '0.12.1',
    acceptFirst: false,
  };

  for (let index = 0; index < rest.length; index += 1) {
    const current = rest[index];
    const next = rest[index + 1];

    if (current === '--file' && next) {
      options.file = next;
      index += 1;
      continue;
    }

    if (current === '--line' && next) {
      options.line = Number(next);
      index += 1;
      continue;
    }

    if (current === '--character' && next) {
      options.character = Number(next);
      index += 1;
      continue;
    }

    if (current === '--workspace' && next) {
      options.workspace = next;
      index += 1;
      continue;
    }

    if (current === '--editor-version' && next) {
      options.editorVersion = next;
      index += 1;
      continue;
    }

    if (current === '--accept-first') {
      options.acceptFirst = true;
      continue;
    }
  }

  return { command, options };
};

const printHelp = (): void => {
  console.log(`Usage:
  node dist/cli.js auth:signin
  node dist/cli.js auth:signout
  node dist/cli.js auth:status
  node dist/cli.js complete --file fixtures/sample.ts --line 13 --character 2 [--accept-first]

Options:
  --workspace <path>       Workspace root. Defaults to current directory.
  --editor-version <ver>   Editor version reported to Copilot. Defaults to 0.10.0.
  --accept-first           Accept the first completion after showing it.
`);
};

const requireFileOption = (filePath: string | undefined): string => {
  if (!filePath) {
    throw new Error('Missing required --file option');
  }

  const absolutePath = resolve(filePath);

  if (!existsSync(absolutePath)) {
    throw new Error(`File does not exist: ${absolutePath}`);
  }

  return absolutePath;
};

const requireNumberOption = (value: number | undefined, flagName: string): number => {
  if (!Number.isInteger(value)) {
    throw new Error(`Missing or invalid ${flagName}`);
  }

  return value as number;
};

const printStatus = (status: unknown): void => {
  console.log('Status:');
  console.log(JSON.stringify(status, null, 2));
};

const pickFirstItem = (items: InlineCompletionItem[]): InlineCompletionItem => {
  if (items.length === 0) {
    throw new Error('No completion items returned');
  }

  return items[0];
};

const run = async (): Promise<void> => {
  const { command, options } = parseArgs(process.argv.slice(2));

  if (command === 'help' || command === '--help' || command === '-h') {
    printHelp();
    return;
  }

  const client = new CopilotLspClient();
  const workspacePath = resolve(options.workspace ?? process.cwd());

  try {
    await client.initialize(workspacePath, options.editorVersion);
    const startupStatus = await client.waitForStatus(3_000);

    if (startupStatus) {
      console.log('Initial status received from server.');
      printStatus(startupStatus);
    }

    if (command === 'auth:status') {
      const status = client.getLastStatus();
      printStatus(status ?? { message: 'No status notification received yet.' });
      return;
    }

    if (command === 'auth:signin') {
      const signInResponse = await client.signIn();
      console.log('signIn response:');
      console.log(JSON.stringify(signInResponse, null, 2));

      const maybeCommand = (signInResponse as { command?: { command: string; arguments?: unknown[] } }).command;

      if (maybeCommand) {
        console.log('Executing sign-in command to finish device flow...');
        await client.executeCommand(maybeCommand);
      }

      const finalStatus = await client.waitForStatus(20_000);
      printStatus(finalStatus ?? { message: 'No post-sign-in status received yet.' });
      return;
    }

    if (command === 'auth:signout') {
      const signOutResponse = await client.signOut();
      console.log('signOut response:');
      console.log(JSON.stringify(signOutResponse, null, 2));
      const finalStatus = await client.waitForStatus(5_000);
      printStatus(finalStatus ?? { message: 'No post-sign-out status received yet.' });
      return;
    }

    if (command === 'complete') {
      const filePath = requireFileOption(options.file);
      const line = requireNumberOption(options.line, '--line');
      const character = requireNumberOption(options.character, '--character');
      const document = await client.openDocument(filePath);
      const result = await client.requestInlineCompletion({
        uri: document.uri,
        version: document.version,
        position: { line, character },
      });

      console.log('Completion response:');
      console.log(JSON.stringify(result, null, 2));

      if (result.items.length > 0) {
        const firstItem = pickFirstItem(result.items);
        client.notifyCompletionShown(firstItem);
        console.log('Marked first completion as shown.');

        if (options.acceptFirst) {
          await client.acceptCompletion(firstItem);
          console.log('Accepted first completion via workspace/executeCommand.');
        }
      }

      const finalStatus = client.getLastStatus();

      if (finalStatus) {
        printStatus(finalStatus);
      }

      return;
    }

    throw new Error(`Unknown command: ${command}`);
  } finally {
    await client.close();
  }
};

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.stack ?? error.message : String(error);
  console.error(message);
  process.exitCode = 1;
});
