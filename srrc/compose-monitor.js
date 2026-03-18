#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const { execFile, spawn } = require('node:child_process');

const ROOT_DIR = path.resolve(__dirname, '..');
const UPDATE_SCRIPT = path.join(ROOT_DIR, 'update-service.sh');
const REFRESH_INTERVAL_MS = 5000;

const ANSI = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  cyan: '\x1b[36m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  magenta: '\x1b[35m',
  blue: '\x1b[34m',
  white: '\x1b[37m',
  gray: '\x1b[90m',
  bgBlue: '\x1b[44m',
  bgMagenta: '\x1b[45m',
  bgGreen: '\x1b[42m',
  bgYellow: '\x1b[43m',
  bgRed: '\x1b[41m',
  clear: '\x1b[2J',
  home: '\x1b[H',
  hideCursor: '\x1b[?25l',
  showCursor: '\x1b[?25h',
};

const state = {
  services: [],
  selectedIndex: 0,
  loading: true,
  error: null,
  lastRefreshAt: null,
  updateInProgress: false,
  updateService: null,
  updateLog: [],
  updateExitCode: null,
  quitting: false,
};

function color(text, value) {
  return `${value}${text}${ANSI.reset}`;
}

function truncate(text, width) {
  const value = String(text ?? '');
  if (value.length <= width) return value.padEnd(width, ' ');
  if (width <= 1) return value.slice(0, width);
  return `${value.slice(0, width - 1)}…`;
}

function shellExec(file, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(file, args, { cwd: ROOT_DIR, maxBuffer: 1024 * 1024, ...options }, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

async function getComposeServices() {
  const { stdout } = await shellExec('docker-compose', ['config', '--services']);
  return stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

function parseComposePsTable(output) {
  const lines = output.split('\n').map((line) => line.trimEnd()).filter(Boolean);
  if (lines.length <= 1) return new Map();

  const rows = new Map();
  for (const line of lines.slice(1)) {
    const cols = line.split(/\s{2,}/).map((part) => part.trim());
    if (cols.length < 4) continue;

    const [name, image, command, service, ...rest] = cols;
    const status = rest[1] || rest[0] || 'Unknown';
    rows.set(service, { name, image, command, service, status });
  }
  return rows;
}

async function getComposeStatuses() {
  try {
    const { stdout } = await shellExec('docker', ['compose', 'ps', '--all']);
    return parseComposePsTable(stdout);
  } catch (error) {
    const stderr = (error.stderr || '').trim();
    if (stderr) throw new Error(stderr);
    throw error;
  }
}

function statusTone(status) {
  const value = String(status || '').toLowerCase();
  if (value.includes('healthy') || value.startsWith('up')) {
    return ANSI.green;
  }
  if (value.includes('restarting') || value.includes('created')) {
    return ANSI.yellow;
  }
  if (value.includes('exited') || value.includes('dead') || value.includes('error')) {
    return ANSI.red;
  }
  return ANSI.gray;
}

function renderHeader(width) {
  const title = color(' Compose Control Deck ', `${ANSI.bold}${ANSI.bgMagenta}${ANSI.white}`);
  const subtitle = color('monitor | refresh | single-service update', `${ANSI.cyan}${ANSI.bold}`);
  return `${title}\n${subtitle}\n${color('Arrows/J-K navigate  Enter/U update  R refresh  Q quit', ANSI.gray)}\n${'='.repeat(Math.max(48, Math.min(width, 100)))}`;
}

function renderTable(width) {
  const indexWidth = 4;
  const nameWidth = 28;
  const serviceWidth = 24;
  const statusWidth = Math.max(24, width - indexWidth - nameWidth - serviceWidth - 10);
  const header = [
    color(truncate('#', indexWidth), ANSI.gray),
    color(truncate('Container', nameWidth), ANSI.gray),
    color(truncate('Service', serviceWidth), ANSI.gray),
    color(truncate('Status', statusWidth), ANSI.gray),
  ].join(' ');

  const lines = [header];
  state.services.forEach((service, index) => {
    const marker = index === state.selectedIndex ? color('›', `${ANSI.bold}${ANSI.cyan}`) : ' ';
    const selected = index === state.selectedIndex;
    const rowColor = selected ? ANSI.bold : '';
    const tone = statusTone(service.status);
    const parts = [
      `${marker} ${truncate(String(index + 1), indexWidth - 2)}`,
      truncate(service.containerName || '-', nameWidth),
      truncate(service.serviceName, serviceWidth),
      color(truncate(service.status || 'Not created', statusWidth), `${rowColor}${tone}`),
    ];
    lines.push(parts.join(' '));
  });

  if (state.services.length === 0) {
    lines.push(color('No services found in docker-compose configuration.', ANSI.red));
  }
  return lines.join('\n');
}

function renderFooter() {
  const selected = state.services[state.selectedIndex];
  const refreshText = state.lastRefreshAt
    ? `Last refresh: ${state.lastRefreshAt.toLocaleTimeString()}`
    : 'Last refresh: never';
  const selectedText = selected
    ? `Selected: ${selected.serviceName}`
    : 'Selected: -';

  const lines = [
    '',
    `${color(refreshText, ANSI.gray)}    ${color(selectedText, ANSI.gray)}`,
  ];

  if (state.loading) {
    lines.push(color('Refreshing compose status…', ANSI.cyan));
  } else if (state.error) {
    lines.push(color(`Compose status unavailable: ${state.error}`, `${ANSI.bold}${ANSI.red}`));
  }

  if (state.updateInProgress) {
    lines.push(color(`Updating ${state.updateService} via update-service.sh…`, `${ANSI.bold}${ANSI.yellow}`));
  } else if (state.updateService && state.updateExitCode !== null) {
    const tone = state.updateExitCode === 0 ? `${ANSI.bold}${ANSI.green}` : `${ANSI.bold}${ANSI.red}`;
    const message = state.updateExitCode === 0
      ? `Update completed for ${state.updateService}`
      : `Update failed for ${state.updateService} (exit ${state.updateExitCode})`;
    lines.push(color(message, tone));
  }

  if (state.updateLog.length > 0) {
    lines.push('');
    lines.push(color('Update log', `${ANSI.bold}${ANSI.blue}`));
    for (const line of state.updateLog.slice(-10)) {
      lines.push(truncate(line, process.stdout.columns || 120));
    }
  }

  return lines.join('\n');
}

function render() {
  const width = process.stdout.columns || 120;
  const output = [
    ANSI.hideCursor,
    ANSI.clear,
    ANSI.home,
    renderHeader(width),
    '',
    renderTable(width),
    renderFooter(),
  ].join('\n');
  process.stdout.write(output);
}

async function refreshServices() {
  if (state.updateInProgress) return;
  state.loading = true;
  state.error = null;
  render();

  try {
    const [serviceNames, statuses] = await Promise.all([getComposeServices(), getComposeStatuses()]);
    state.services = serviceNames.map((serviceName) => {
      const row = statuses.get(serviceName);
      return {
        serviceName,
        containerName: row?.name || '-',
        status: row?.status || 'Not created',
      };
    });
    state.selectedIndex = Math.max(0, Math.min(state.selectedIndex, Math.max(state.services.length - 1, 0)));
    state.lastRefreshAt = new Date();
  } catch (error) {
    state.error = error.message || String(error);
    if (state.services.length === 0) {
      try {
        const serviceNames = await getComposeServices();
        state.services = serviceNames.map((serviceName) => ({
          serviceName,
          containerName: '-',
          status: 'Status unavailable',
        }));
      } catch {
        state.services = [];
      }
    }
  } finally {
    state.loading = false;
    render();
  }
}

function appendUpdateLog(chunk) {
  const text = String(chunk || '').replace(/\r/g, '');
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    state.updateLog.push(line);
  }
  state.updateLog = state.updateLog.slice(-100);
  render();
}

function runUpdateForSelectedService() {
  if (state.updateInProgress || state.services.length === 0) return;

  const selected = state.services[state.selectedIndex];
  if (!selected) return;

  state.updateInProgress = true;
  state.updateService = selected.serviceName;
  state.updateExitCode = null;
  state.updateLog = [`$ ${path.relative(ROOT_DIR, UPDATE_SCRIPT) || 'update-service.sh'} ${selected.serviceName}`];
  render();

  const child = spawn(UPDATE_SCRIPT, [selected.serviceName], {
    cwd: ROOT_DIR,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  child.stdout.on('data', appendUpdateLog);
  child.stderr.on('data', appendUpdateLog);
  child.on('error', (error) => {
    appendUpdateLog(`Failed to start update: ${error.message}`);
  });
  child.on('close', async (code) => {
    state.updateInProgress = false;
    state.updateExitCode = code ?? 1;
    await refreshServices();
  });
}

function moveSelection(delta) {
  if (state.services.length === 0) return;
  state.selectedIndex = (state.selectedIndex + delta + state.services.length) % state.services.length;
  render();
}

function cleanupAndExit(code = 0) {
  if (state.quitting) return;
  state.quitting = true;
  process.stdout.write(`${ANSI.showCursor}${ANSI.reset}\n`);
  process.exit(code);
}

function ensureEnvironment() {
  if (!fs.existsSync(UPDATE_SCRIPT)) {
    throw new Error(`Missing update script: ${UPDATE_SCRIPT}`);
  }
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error('This program requires an interactive terminal.');
  }
}

async function main() {
  ensureEnvironment();

  readline.emitKeypressEvents(process.stdin);
  process.stdin.setRawMode(true);
  process.stdin.resume();

  process.stdin.on('keypress', async (_str, key) => {
    if (!key) return;
    if (key.sequence === '\u0003' || key.name === 'q') {
      cleanupAndExit(0);
      return;
    }
    if (key.name === 'up' || key.name === 'k') {
      moveSelection(-1);
      return;
    }
    if (key.name === 'down' || key.name === 'j') {
      moveSelection(1);
      return;
    }
    if (key.name === 'return' || key.name === 'u') {
      runUpdateForSelectedService();
      return;
    }
    if (key.name === 'r') {
      await refreshServices();
    }
  });

  process.stdout.on('resize', render);
  process.on('SIGINT', () => cleanupAndExit(0));
  process.on('SIGTERM', () => cleanupAndExit(0));
  process.on('uncaughtException', (error) => {
    process.stdout.write(`${ANSI.showCursor}${ANSI.reset}`);
    console.error(error.message || error);
    process.exit(1);
  });

  render();
  await refreshServices();
  setInterval(refreshServices, REFRESH_INTERVAL_MS);
}

main().catch((error) => {
  process.stdout.write(`${ANSI.showCursor}${ANSI.reset}`);
  console.error(error.message || error);
  process.exit(1);
});
