#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const childProcess = require('child_process');
const execFile = childProcess.execFile;
const spawn = childProcess.spawn;

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
  showLogs: false,
  logFollower: null,
  logServiceName: null,
  quitting: false,
};

function color(text, value) {
  return `${value}${text}${ANSI.reset}`;
}

function truncate(text, width) {
  const value = String(text == null ? '' : text);
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

function parseSingleServicePs(output, serviceName) {
  const lines = output.split('\n').map((line) => line.trimRight()).filter(Boolean);
  if (lines.length <= 1) {
    return {
      serviceName,
      containerName: '-',
      containerId: '',
      status: 'Inactive',
      topSummary: '0 proc',
      topLines: [],
    };
  }

  const line = lines[1];
  const cols = line.split(/\s{2,}/).map((part) => part.trim());
  if (cols.length < 3) {
    return {
      serviceName,
      containerName: '-',
      containerId: '',
      status: 'Unknown',
      topSummary: 'n/a',
      topLines: [],
    };
  }

  return {
    serviceName,
    containerName: cols[0] || '-',
    containerId: '',
    status: cols[2] || 'Unknown',
    topSummary: 'n/a',
    topLines: [],
  };
}

async function getContainerId(serviceName) {
  const result = await shellExec('docker-compose', ['ps', '-q', serviceName]);
  return result.stdout.trim();
}

function summarizeStatus(inspectData) {
  const stateInfo = inspectData && inspectData.State ? inspectData.State : {};
  const rawStatus = String(stateInfo.Status || 'unknown').toUpperCase();
  const health = stateInfo.Health && stateInfo.Health.Status ? String(stateInfo.Health.Status).toUpperCase() : '';

  if (rawStatus === 'RUNNING' && health) {
    return `${rawStatus}/${health}`;
  }
  return rawStatus;
}

function parseTopOutput(output) {
  const lines = output.split('\n').map((line) => line.trimRight()).filter(Boolean);
  if (lines.length <= 1) {
    return {
      topSummary: '0 proc',
      topLines: [],
    };
  }

  const dataLines = lines.slice(1);
  return {
    topSummary: `${dataLines.length} proc`,
    topLines: dataLines.slice(0, 5),
  };
}

function formatBytes(bytes) {
  const value = Number(bytes);
  if (!isFinite(value) || value < 0) return 'n/a';

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = value;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  const precision = size >= 10 || unitIndex === 0 ? 0 : 1;
  return `${size.toFixed(precision)} ${units[unitIndex]}`;
}

async function getMemoryUsage(containerId) {
  try {
    const result = await shellExec('docker', ['stats', '--no-stream', '--format', '{{.MemUsage}}', containerId]);
    const line = result.stdout.trim();
    return line || 'n/a';
  } catch (_error) {
    return 'n/a';
  }
}

async function getDiskUsage(containerId) {
  try {
    const result = await shellExec('docker', ['inspect', '--size', containerId]);
    const rows = JSON.parse(result.stdout);
    const row = rows && rows[0] ? rows[0] : null;
    if (!row) return 'n/a';

    const sizeRw = formatBytes(row.SizeRw);
    const sizeRootFs = formatBytes(row.SizeRootFs);

    if (sizeRw === 'n/a' && sizeRootFs === 'n/a') {
      return 'n/a';
    }

    return `rw ${sizeRw} | fs ${sizeRootFs}`;
  } catch (_error) {
    return 'n/a';
  }
}

async function getComposeStatus(serviceName) {
  try {
    const containerId = await getContainerId(serviceName);
    if (!containerId) {
      return parseSingleServicePs('', serviceName);
    }

    const inspectResult = await shellExec('docker', ['inspect', containerId]);
    const inspectRows = JSON.parse(inspectResult.stdout);
    const inspectData = inspectRows && inspectRows[0] ? inspectRows[0] : null;
    let topData = {
      topSummary: '0 proc',
      topLines: [],
    };
    let logLines = [];

    try {
      const topResult = await shellExec('docker', ['top', containerId]);
      topData = parseTopOutput(topResult.stdout);
    } catch (_error) {
      topData = {
        topSummary: '0 proc',
        topLines: [],
      };
    }

    try {
      const logsResult = await shellExec('docker', ['logs', '--tail', '5', containerId]);
      logLines = logsResult.stdout
        .replace(/\r/g, '')
        .split('\n')
        .filter(Boolean)
        .slice(-5);
    } catch (_error) {
      logLines = [];
    }

    const runtimeData = await Promise.all([
      getMemoryUsage(containerId),
      getDiskUsage(containerId),
    ]);

    return {
      serviceName,
      containerName: inspectData && inspectData.Name ? inspectData.Name.replace(/^\/+/, '') : containerId.slice(0, 12),
      containerId,
      status: summarizeStatus(inspectData),
      topSummary: topData.topSummary,
      topLines: topData.topLines,
      logLines: logLines,
      memoryUsage: runtimeData[0],
      diskUsage: runtimeData[1],
    };
  } catch (error) {
    const stderr = (error.stderr || '').trim();
    if (stderr) throw new Error(stderr);
    throw error;
  }
}

function statusTone(status) {
  const value = String(status || '').toLowerCase();
  if (value.includes('healthy') || value.startsWith('up') || value.startsWith('running')) {
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
  return `${title}\n${subtitle}\n${color('Arrows/J-K navigate  Enter/U update  L logs  R refresh  Q quit', ANSI.gray)}\n${'='.repeat(Math.max(48, Math.min(width, 100)))}`;
}

function renderTable(width) {
  const indexWidth = 4;
  const nameWidth = 28;
  const serviceWidth = 22;
  const statusWidth = 20;
  const topWidth = Math.max(18, width - indexWidth - nameWidth - serviceWidth - statusWidth - 12);
  const header = [
    color(truncate('#', indexWidth), ANSI.gray),
    color(truncate('Container', nameWidth), ANSI.gray),
    color(truncate('Service', serviceWidth), ANSI.gray),
    color(truncate('Status', statusWidth), ANSI.gray),
    color(truncate('Top', topWidth), ANSI.gray),
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
      truncate(service.topSummary || '-', topWidth),
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

  if (selected) {
    lines.push('');
    lines.push(color('Container top', `${ANSI.bold}${ANSI.blue}`));
    lines.push(color(`Container: ${selected.containerName || '-'}    Status: ${selected.status || '-'}`, ANSI.gray));
    lines.push(color(`RAM: ${selected.memoryUsage || 'n/a'}    Disk: ${selected.diskUsage || 'n/a'}`, ANSI.gray));
    if (selected.topLines && selected.topLines.length > 0) {
      for (const line of selected.topLines) {
        lines.push(truncate(line, process.stdout.columns || 120));
      }
    } else {
      lines.push(color('No process data available for this service.', ANSI.gray));
    }

    if (state.showLogs) {
      lines.push('');
      lines.push(color('Last 5 log lines', `${ANSI.bold}${ANSI.blue}`));
      if (selected.logLines && selected.logLines.length > 0) {
        for (const line of selected.logLines) {
          lines.push(truncate(line, process.stdout.columns || 120));
        }
      } else {
        lines.push(color('No log data available for this service.', ANSI.gray));
      }
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

function getSelectedService() {
  return state.services[state.selectedIndex] || null;
}

function stopLogFollower() {
  if (!state.logFollower) return;

  try {
    state.logFollower.removeAllListeners();
    state.logFollower.kill('SIGTERM');
  } catch (_error) {
    // ignore cleanup errors
  }

  state.logFollower = null;
  state.logServiceName = null;
}

function appendServiceLog(chunk) {
  const selected = getSelectedService();
  if (!selected) return;

  const lines = String(chunk || '')
    .replace(/\r/g, '')
    .split('\n')
    .filter(Boolean);

  if (lines.length === 0) return;

  selected.logLines = (selected.logLines || []).concat(lines).slice(-5);
  render();
}

function syncLogFollower() {
  const selected = getSelectedService();

  if (!state.showLogs || !selected || !selected.containerId) {
    stopLogFollower();
    return;
  }

  if (state.logFollower && state.logServiceName === selected.serviceName) {
    return;
  }

  stopLogFollower();
  selected.logLines = (selected.logLines || []).slice(-5);

  const child = spawn('docker', ['logs', '-f', '--tail', '5', selected.containerId], {
    cwd: ROOT_DIR,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  state.logFollower = child;
  state.logServiceName = selected.serviceName;

  child.stdout.on('data', appendServiceLog);
  child.stderr.on('data', appendServiceLog);
  child.on('close', function () {
    if (state.logFollower === child) {
      state.logFollower = null;
      state.logServiceName = null;
      render();
    }
  });
}

async function refreshServices() {
  if (state.updateInProgress) return;
  state.loading = true;
  state.error = null;
  render();

  try {
    const serviceNames = await getComposeServices();
    const statuses = await Promise.all(serviceNames.map(getComposeStatus));
    state.services = statuses;
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
    syncLogFollower();
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

  const selected = getSelectedService();
  if (!selected) return;

  stopLogFollower();
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
    state.updateExitCode = code == null ? 1 : code;
    await refreshServices();
    state.updateLog = [];
    syncLogFollower();
  });
}

function moveSelection(delta) {
  if (state.services.length === 0) return;
  state.selectedIndex = (state.selectedIndex + delta + state.services.length) % state.services.length;
  syncLogFollower();
  render();
}

function cleanupAndExit(code = 0) {
  if (state.quitting) return;
  state.quitting = true;
  stopLogFollower();
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
      return;
    }
    if (key.name === 'l') {
      state.showLogs = !state.showLogs;
      syncLogFollower();
      render();
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
