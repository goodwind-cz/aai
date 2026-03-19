export const COMMANDS = [
  '/intake','/new','/status','/usage','/provider','/projects','/register',
  '/approve','/resume','/stop','/logs','/agents','/schedule','/context','/debug','/restart'
] as const;

export const PRIMARY_INLINE_ACTIONS = [
  'Approve implementation',
  'Approve validation',
  'Pause',
  'Resume',
  'Stop',
  'Use Claude',
  'Use Codex',
  'Use Auto Router',
  'Switch Project',
  'Open Latest Report'
] as const;
