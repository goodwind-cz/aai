function status(args) {
  if (args.includes('--json')) return JSON.stringify({ status: 'ok' });
  return 'ok';
}

if (require.main === module) process.stdout.write(`${status(process.argv.slice(2))}\n`);

module.exports = { status };
