// cli-pipe-guard.mjs — the ONE pipe-safe exit discipline for .aai/scripts
// CLIs (cli-exit-truncates-pipe-sweep, follow-up on
// docs/specs/SPEC-0139-spec-cli-output-survives-a-pipe.md D7).
//
// PROBLEM this exists to prevent — measured on follow-ups.mjs `list --json`:
// `console.log(...); process.exit(code)` is fine to a FILE (stdout is
// synchronous there) but to a PIPE stdout is asynchronous, `process.exit`
// runs before the queued remainder is handed to the kernel, and the reader
// gets exactly whatever the pipe buffer already took — 65536 bytes of an
// 87012-byte payload, `JSON.parse` failing at byte 65522. TWO CLIs
// (follow-ups.mjs, sync-harness-skills.mjs) independently hand-rolled the
// same fix before this extraction; this file is that fix, written once.
//
// THE FIX IS STRUCTURAL, NOT PER-CALL-SITE: a CLI's `main()` must never call
// `process.exit()` directly. It calls `exit(code)` instead, which THROWS an
// `ExitSignal` — an ordinary JS exception, not a real exit — that unwinds the
// call stack (through any awaits) up to `runMain()`, which turns it into
// `process.exitCode` and returns normally. Node then exits on its own once
// the event loop drains, which is only after every queued stdout/stderr byte
// has been handed to the kernel. Nothing a CLI here opens (no timer, no
// socket, no stdin read) keeps the process alive past that drain.
//
// EPIPE is the other half: a reader that closes early (`| head -1`) makes a
// LATER write fail with EPIPE. That is the reader's choice, not a tool
// failure, and must not surface as an unhandled 'error' event (crash plus a
// stack trace on stderr). There is nothing left to flush once the far end is
// gone, so `installPipeGuard` ends the process immediately with whatever
// exit code was already decided — this ONE raw `process.exit()` call in the
// whole file is deliberate: by the time it runs, the write it guards has
// already failed, so there is no buffered output left to lose.
//
// USAGE — a CLI using this library:
//   import { exit, runMain } from './lib/cli-pipe-guard.mjs';
//   function main(argv) { ...; exit(0); }
//   runMain(() => main(process.argv.slice(2)));
// A CLI that needs its own fallback for a non-ExitSignal (unexpected) error
// instead of runMain's default re-throw passes onError:
//   runMain(() => main(), { onError(err) {
//     process.stderr.write(`mytool: unexpected error: ${err.stack}\n`);
//     process.exitCode = 2;
//   } });
//
// Node stdlib only, zero network, no LLM (docs/TECHNOLOGY.md).

export class ExitSignal extends Error {
  constructor(code) {
    super(`exit ${code}`);
    this.name = 'ExitSignal';
    this.code = code;
  }
}

// The ONLY sanctioned way a CLI built on this library ends its own `main()`.
// Never call `process.exit()` from inside `main()` — throw this instead.
export function exit(code) {
  throw new ExitSignal(code);
}

// Install once per stream, before `main()` runs. See EPIPE note above for
// why the one raw `process.exit()` here is safe.
export function installPipeGuard(stream) {
  stream.on('error', (err) => {
    const code = err && err.code;
    if (code === 'EPIPE' || code === 'ERR_STREAM_DESTROYED') {
      process.exit(typeof process.exitCode === 'number' ? process.exitCode : 0);
    }
    throw err;
  });
}

// Installs both stream guards, runs `mainFn` (sync or async), and turns a
// thrown ExitSignal into `process.exitCode` so Node exits the ordinary way
// after stdout/stderr have drained. A non-ExitSignal error is handed to
// `opts.onError` if given, else re-thrown (matching follow-ups.mjs's
// original behavior: an unexpected bug is a hard crash, not a silent exit).
export async function runMain(mainFn, opts = {}) {
  installPipeGuard(process.stdout);
  installPipeGuard(process.stderr);
  try {
    await mainFn();
  } catch (err) {
    if (err instanceof ExitSignal) {
      process.exitCode = err.code;
      return;
    }
    if (typeof opts.onError === 'function') {
      opts.onError(err);
      return;
    }
    throw err;
  }
}
