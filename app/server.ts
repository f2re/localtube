// LocalTube 1.4.2 — dependency-free cross-platform Deno backend.
// No npm/jsr imports: the service remains usable offline after installation.

declare const Deno: any;

type Json = Record<string, unknown>;
type Settings = {
  download_dir: string;
  cookies_mode: 'none' | 'browser' | 'file';
  cookies_browser: string;
  cookies_file: string;
  video_container: 'mp4' | 'mkv' | 'auto';
  audio_format: 'm4a' | 'mp3' | 'opus' | 'flac' | 'best';
  audio_quality: '0' | '320K' | '256K' | '192K' | '128K';
  embed_metadata: boolean;
  playlist: boolean;
};

type JobState = 'queued' | 'running' | 'completed' | 'failed' | 'cancelled' | 'interrupted';
type Job = {
  id: string;
  url: string;
  mode: 'video' | 'audio';
  height: 'best' | number;
  title: string;
  settings: Settings;
  state: JobState;
  percent: number;
  speed: string;
  eta: string;
  phase: string;
  playlist_item: string;
  outputs: string[];
  error: string;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
  logs: string[];
  cancel_requested: boolean;
  process?: any;
};

const PLATFORM = Deno.build?.os || 'unknown';
const HOME = Deno.env.get('HOME') || Deno.env.get('USERPROFILE') || '';
const DEFAULT_BASE = PLATFORM === 'windows'
  ? `${Deno.env.get('LOCALAPPDATA') || `${HOME}/AppData/Local`}/LocalTube`
  : PLATFORM === 'linux'
    ? `${Deno.env.get('XDG_DATA_HOME') || `${HOME}/.local/share`}/localtube`
    : `${HOME}/Library/Application Support/LocalTube`;
const BASE_DIR = Deno.env.get('LOCALTUBE_BASE') || DEFAULT_BASE;
const APP_DIR = Deno.env.get('LOCALTUBE_APP_DIR') || `${BASE_DIR}/app`;
const STATIC_DIR = `${APP_DIR}/static`;
const RUNTIME_DIR = Deno.env.get('LOCALTUBE_RUNTIME_DIR') || `${BASE_DIR}/runtime`;
const DATA_DIR = `${BASE_DIR}/data`;
const LOG_DIR = `${BASE_DIR}/logs`;
const SETTINGS_FILE = `${DATA_DIR}/settings.json`;
const HISTORY_FILE = `${DATA_DIR}/history.json`;
const TOKEN_FILE = `${DATA_DIR}/api_token`;
const PORT_RAW = Number.parseInt(Deno.env.get('LOCALTUBE_PORT') || '8765', 10);
const PORT = Number.isInteger(PORT_RAW) && PORT_RAW >= 1024 && PORT_RAW <= 65535 ? PORT_RAW : 8765;
const HOST = '127.0.0.1';
const MAX_BODY = 64 * 1024;
const MAX_HISTORY = 100;
const MAX_LOG_LINES = 180;
const MAX_ACTIVE_JOBS = 50;
const EXE = PLATFORM === 'windows' ? '.exe' : '';
const YTDLP = `${RUNTIME_DIR}/yt-dlp${EXE}`;
const FFMPEG = `${RUNTIME_DIR}/ffmpeg${EXE}`;
const FFPROBE = `${RUNTIME_DIR}/ffprobe${EXE}`;
const DENO_BIN = `${RUNTIME_DIR}/deno${EXE}`;
const TEST_VIDEO_ID = 'YE7VzlLtp-4';
const TEST_VIDEO_URL = `https://www.youtube.com/watch?v=${TEST_VIDEO_ID}&t=1s&end=9`; // current yt-dlp upstream YouTube fixture

function join(...parts: string[]): string {
  return parts.filter(Boolean).join('/').replace(/\/+/g, '/');
}
function dirname(path: string): string {
  const p = path.replace(/\/+$/, '');
  const i = p.lastIndexOf('/');
  return i <= 0 ? '/' : p.slice(0, i);
}
function expandUser(path: string): string {
  if (path === '~') return HOME;
  if (path.startsWith('~/')) return `${HOME}/${path.slice(2)}`;
  return path;
}
function nowIso(): string { return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'); }
function safeString(v: unknown, max = 1000): string { return String(v ?? '').slice(0, max); }
function clamp(v: number, lo: number, hi: number): number { return Math.max(lo, Math.min(hi, v)); }
function delay(ms: number): Promise<void> { return new Promise((resolve) => setTimeout(resolve, ms)); }

async function existsFile(path: string): Promise<boolean> {
  try { return (await Deno.stat(path)).isFile; } catch { return false; }
}
async function existsDir(path: string): Promise<boolean> {
  try { return (await Deno.stat(path)).isDirectory; } catch { return false; }
}
async function ensureDir(path: string): Promise<void> { await Deno.mkdir(path, { recursive: true }); }
async function readText(path: string, fallback = ''): Promise<string> {
  try { return await Deno.readTextFile(path); } catch { return fallback; }
}
async function readJson<T>(path: string, fallback: T): Promise<T> {
  try { return JSON.parse(await Deno.readTextFile(path)) as T; } catch { return fallback; }
}
async function atomicWriteJson(path: string, value: unknown): Promise<void> {
  await ensureDir(dirname(path));
  const tmp = `${path}.tmp.${crypto.randomUUID()}`;
  await Deno.writeTextFile(tmp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  try { await Deno.chmod(tmp, 0o600); } catch { /* ignore */ }
  await Deno.rename(tmp, path);
}

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
async function getToken(): Promise<string> {
  const existing = (await readText(TOKEN_FILE)).trim();
  if (existing.length >= 32) return existing;
  const token = randomToken();
  await ensureDir(DATA_DIR);
  await Deno.writeTextFile(TOKEN_FILE, `${token}\n`, { mode: 0o600 });
  try { await Deno.chmod(TOKEN_FILE, 0o600); } catch { /* ignore */ }
  return token;
}

const DEFAULT_DOWNLOAD_DIR = PLATFORM === 'darwin'
  ? `${HOME}/Movies/LocalTube`
  : `${HOME}/Downloads/LocalTube`;

const DEFAULT_SETTINGS: Settings = {
  download_dir: DEFAULT_DOWNLOAD_DIR,
  cookies_mode: 'none',
  cookies_browser: 'chrome',
  cookies_file: '',
  video_container: 'mp4',
  audio_format: 'm4a',
  audio_quality: '192K',
  embed_metadata: true,
  playlist: false,
};

const COOKIE_BROWSERS = new Set(['brave', 'chrome', 'chromium', 'edge', 'firefox', 'opera', 'safari', 'vivaldi']);
const AUDIO_FORMATS = new Set(['m4a', 'mp3', 'opus', 'flac', 'best']);
const AUDIO_QUALITIES = new Set(['0', '320K', '256K', '192K', '128K']);
const VIDEO_CONTAINERS = new Set(['mp4', 'mkv', 'auto']);

async function sanitizeSettings(raw: Partial<Settings>): Promise<Settings> {
  const s = { ...DEFAULT_SETTINGS, ...raw } as Settings;
  let folder = expandUser(safeString(s.download_dir, 4096));
  const absolute = PLATFORM === 'windows'
    ? (/^[A-Za-z]:[\\/]/.test(folder) || /^\\\\[^\\]+\\[^\\]+/.test(folder))
    : folder.startsWith('/');
  if (!absolute || folder.includes('\0')) folder = DEFAULT_SETTINGS.download_dir;
  if (PLATFORM === 'windows') {
    folder = folder.replace(/\//g, '\\');
    if (!/^[A-Za-z]:\\$/.test(folder)) folder = folder.replace(/\\+$/, '');
    s.download_dir = folder;
  } else {
    s.download_dir = folder.replace(/\/$/, '') || '/';
  }
  if (!['none', 'browser', 'file'].includes(s.cookies_mode)) s.cookies_mode = 'none';
  if (!COOKIE_BROWSERS.has(s.cookies_browser)) s.cookies_browser = 'chrome';
  if (!VIDEO_CONTAINERS.has(s.video_container)) s.video_container = 'mp4';
  if (!AUDIO_FORMATS.has(s.audio_format)) s.audio_format = 'm4a';
  if (!AUDIO_QUALITIES.has(s.audio_quality)) s.audio_quality = '192K';
  s.embed_metadata = s.embed_metadata !== false;
  s.playlist = s.playlist === true;
  s.cookies_file = safeString(s.cookies_file, 4096);
  return s;
}

async function ensureWritableFolder(folder: string): Promise<void> {
  try {
    await ensureDir(folder);
    if (!(await existsDir(folder))) throw new Error('not a directory');
    const test = join(folder, `.localtube-write-test-${crypto.randomUUID()}`);
    await Deno.writeTextFile(test, 'ok', { createNew: true, mode: 0o600 });
    await Deno.remove(test);
  } catch {
    throw new Error(`Нет доступа на запись в папку: ${folder}. Проверьте права доступа или выберите другую папку.`);
  }
}

async function loadSettings(): Promise<Settings> {
  const raw = await readJson<Partial<Settings>>(SETTINGS_FILE, {});
  return await sanitizeSettings(raw && typeof raw === 'object' ? raw : {});
}
async function saveSettings(patch: Partial<Settings>): Promise<Settings> {
  const current = await loadSettings();
  const allowed: Partial<Settings> = {};
  for (const k of Object.keys(DEFAULT_SETTINGS) as (keyof Settings)[]) {
    if (Object.prototype.hasOwnProperty.call(patch, k)) (allowed as any)[k] = (patch as any)[k];
  }
  const next = await sanitizeSettings({ ...current, ...allowed });
  if (Object.prototype.hasOwnProperty.call(allowed, 'download_dir')) await ensureWritableFolder(next.download_dir);
  await atomicWriteJson(SETTINGS_FILE, next);
  return next;
}

function youtubeUrlKind(input: string): 'video' | 'playlist' | null {
  if (!input || input.length > 4096) return null;
  try {
    const u = new URL(input.trim());
    if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) return null;
    const host = u.hostname.toLowerCase().replace(/\.$/, '');
    const youtubeHost = host === 'youtube.com' || host.endsWith('.youtube.com') ||
      host === 'youtube-nocookie.com' || host.endsWith('.youtube-nocookie.com');
    if (host === 'youtu.be') return u.pathname.split('/').filter(Boolean).length >= 1 ? 'video' : null;
    if (!youtubeHost) return null;
    const path = u.pathname.replace(/\/+$/, '') || '/';
    if (path === '/watch' && u.searchParams.get('v')) return 'video';
    if (path === '/playlist' && u.searchParams.get('list')) return 'playlist';
    if (/^\/(shorts|live|embed|clip)\/[^/]+/.test(path)) return 'video';
    return null;
  } catch { return null; }
}
function youtubeUrlOk(input: string): boolean { return youtubeUrlKind(input) !== null; }

async function runCapture(cmd: string, args: string[], timeoutMs = 30_000): Promise<{ code: number; stdout: string; stderr: string }> {
  const command = new Deno.Command(cmd, { args, stdin: 'null', stdout: 'piped', stderr: 'piped' });
  const child = command.spawn();
  const outputPromise = child.output();
  const result: any = await Promise.race([
    outputPromise.then((out: any) => ({ out })),
    delay(timeoutMs).then(() => ({ timeout: true })),
  ]);
  if (result.timeout) {
    await terminateProcessTree(child);
    try { await Promise.race([outputPromise, delay(2500)]); } catch { /* ignore */ }
    throw new Error('timeout');
  }
  const out = result.out;
  return {
    code: out.code,
    stdout: new TextDecoder().decode(out.stdout),
    stderr: new TextDecoder().decode(out.stderr),
  };
}

async function terminateProcessTree(child: any): Promise<void> {
  if (!child) return;
  const pid = Number(child.pid);
  if (PLATFORM === 'windows' && Number.isInteger(pid) && pid > 1) {
    const root = Deno.env.get('SystemRoot') || 'C:/Windows';
    try {
      const p = new Deno.Command(`${root}/System32/taskkill.exe`, {
        args: ['/PID', String(pid), '/T', '/F'], stdin: 'null', stdout: 'null', stderr: 'null',
      }).spawn();
      await Promise.race([p.status, delay(2500)]);
    } catch { /* process may already be gone */ }
    return;
  }
  const pkill = await existsFile('/usr/bin/pkill') ? '/usr/bin/pkill' : '/bin/pkill';
  if (Number.isInteger(pid) && pid > 1 && await existsFile(pkill)) {
    try {
      const p = new Deno.Command(pkill, { args: ['-TERM', '-P', String(pid)], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn();
      await Promise.race([p.status, delay(800)]);
    } catch { /* ignore */ }
  }
  try { child.kill('SIGTERM'); } catch { /* already exited */ }
  await delay(700);
  if (Number.isInteger(pid) && pid > 1 && await existsFile(pkill)) {
    try { new Deno.Command(pkill, { args: ['-KILL', '-P', String(pid)], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn(); } catch { /* ignore */ }
  }
  try { child.kill('SIGKILL'); } catch { /* already exited */ }
}

async function versionOf(path: string, args = ['--version']): Promise<string | null> {
  if (!(await existsFile(path))) return null;
  try {
    const r = await runCapture(path, args, 8000);
    return (r.stdout || r.stderr).trim().split(/\r?\n/)[0]?.slice(0, 180) || null;
  } catch { return null; }
}

async function isExternalToolWrapper(path: string, tool: string): Promise<boolean> {
  try {
    const data = await Deno.readFile(path);
    const head = new TextDecoder().decode(data.subarray(0, Math.min(data.length, 512)));
    return head.includes(`LOCALTUBE_EXTERNAL_TOOL=${tool}`);
  } catch {
    return false;
  }
}

async function transactionalUpdateYtdlp(): Promise<{ before: string | null; after: string | null; detail: string }> {
  if (await isExternalToolWrapper(YTDLP, 'yt-dlp')) {
    throw new Error('Используется внешний yt-dlp. Для безопасного обновления запустите полное обновление окружения.');
  }
  const before = await versionOf(YTDLP);
  if (!before) throw new Error('Текущий yt-dlp не запускается. Используйте полное обновление окружения.');
  const suffix = crypto.randomUUID().replace(/-/g, '');
  const backup = `${RUNTIME_DIR}/.yt-dlp.rollback.${suffix}`;
  let detail = '';
  try {
    await Deno.copyFile(YTDLP, backup);
    if (PLATFORM !== 'windows') { try { await Deno.chmod(backup, 0o700); } catch { /* ignore */ } }
    const update = await runCapture(YTDLP, ['--ignore-config', '--update-to', 'nightly'], 180_000);
    detail = (update.stdout || update.stderr).trim().slice(0, 1200);
    if (update.code !== 0) throw new Error((update.stderr || update.stdout || 'Не удалось обновить yt-dlp').trim().split(/\r?\n/).at(-1)?.slice(0, 900));
    const after = await versionOf(YTDLP);
    if (!after) throw new Error('Обновлённый yt-dlp не запускается.');
    try { await Deno.remove(backup); } catch { /* ignore */ }
    runtimeStatusCache = null;
    return { before, after, detail };
  } catch (e) {
    try {
      await Deno.copyFile(backup, YTDLP);
      if (PLATFORM !== 'windows') await Deno.chmod(YTDLP, 0o755);
    } catch { /* diagnostics will report a damaged runtime if restoration also fails */ }
    runtimeStatusCache = null;
    throw e;
  } finally {
    try { await Deno.remove(backup); } catch { /* ignore */ }
  }
}

let runtimeStatusCache: { at: number; value: Json } | null = null;
async function runtimeStatus(force = false): Promise<Json> {
  const cacheTtl = runtimeStatusCache?.value.ready === true ? 30_000 : 1_000;
  if (!force && runtimeStatusCache && Date.now() - runtimeStatusCache.at < cacheTtl) return runtimeStatusCache.value;
  const [yt, ff, fp, appVersion] = await Promise.all([
    versionOf(YTDLP), versionOf(FFMPEG, ['-version']), versionOf(FFPROBE, ['-version']),
    readText(`${APP_DIR}/VERSION`, 'dev'),
  ]);
  const deno = Deno.version?.deno ? `deno ${safeString(Deno.version.deno, 80)}` : null;
  const value: Json = {
    ready: Boolean(yt && ff && fp && deno), platform: PLATFORM,
    yt_dlp: { path: (await existsFile(YTDLP)) ? YTDLP : null, version: yt },
    ffmpeg: { path: (await existsFile(FFMPEG)) ? FFMPEG : null, version: ff },
    ffprobe: { path: (await existsFile(FFPROBE)) ? FFPROBE : null, version: fp },
    deno: { path: (await existsFile(DENO_BIN)) ? DENO_BIN : null, version: deno },
    app_version: appVersion.trim(),
  };
  runtimeStatusCache = { at: Date.now(), value };
  return value;
}

async function cookieArgs(settings: Settings): Promise<string[]> {
  if (settings.cookies_mode === 'browser' && COOKIE_BROWSERS.has(settings.cookies_browser)) {
    return ['--cookies-from-browser', settings.cookies_browser];
  }
  if (settings.cookies_mode === 'file') {
    const p = expandUser(settings.cookies_file);
    if (!(await existsFile(p))) throw new Error('Выбран cookies.txt, но файл больше не найден. Выберите его заново.');
    return ['--cookies', p];
  }
  return [];
}

async function commonYtdlpArgs(settings: Settings): Promise<string[]> {
  const missing: string[] = [];
  for (const [name, path] of [['yt-dlp', YTDLP], ['ffmpeg', FFMPEG], ['ffprobe', FFPROBE], ['Deno', DENO_BIN]]) {
    if (!(await existsFile(path))) missing.push(name);
  }
  if (missing.length) throw new Error(`Не найдено окружение: ${missing.join(', ')}. Запустите платформенное обновление/установщик LocalTube.`);
  return [
    '--ignore-config', '--no-colors',
    '--js-runtimes', `deno:${DENO_BIN}`,
    '--remote-components', 'ejs:github',
    '--ffmpeg-location', RUNTIME_DIR,
    ...(await cookieArgs(settings)),
  ];
}

async function inspectVideo(url: string, settings: Settings): Promise<Json> {
  if (!youtubeUrlOk(url)) throw new Error('Разрешены только ссылки YouTube / youtu.be.');
  const purePlaylist = youtubeUrlKind(url) === 'playlist';
  const args = [
    ...(await commonYtdlpArgs(settings)), '--socket-timeout', '20', '--retries', '3', '--skip-download',
    '--dump-single-json', '--no-warnings', ...(purePlaylist ? ['--playlist-items', '1'] : ['--no-playlist']), url,
  ];
  let r;
  try { r = await runCapture(YTDLP, args, 75_000); }
  catch (e) { if (String(e).includes('timeout')) throw new Error('YouTube отвечает слишком долго. Повторите попытку.'); throw e; }
  if (r.code !== 0) {
    const lines = (r.stderr || r.stdout || '').trim().split(/\r?\n/).filter(Boolean);
    throw new Error((lines.at(-1) || 'Не удалось получить данные видео').replace(/^ERROR:\s*/, '').slice(0, 900));
  }
  let outer: any;
  try { outer = JSON.parse(r.stdout); } catch { throw new Error('yt-dlp вернул некорректные метаданные.'); }
  const isPlaylist = ['playlist', 'multi_video'].includes(outer?._type) && Array.isArray(outer?.entries);
  const playlistCount = Number.isFinite(outer?.playlist_count) ? Number(outer.playlist_count) :
    Number.isFinite(outer?.n_entries) ? Number(outer.n_entries) : (isPlaylist ? outer.entries.length : null);
  let info: any = outer;
  if (isPlaylist) info = outer.entries.find((x: unknown) => x && typeof x === 'object') || outer;
  const heights = [...new Set<number>((Array.isArray(info?.formats) ? info.formats : [])
    .filter((f: any) => Number.isFinite(f?.height) && f?.vcodec !== 'none')
    .map((f: any) => Number(f.height)))].sort((a, b) => b - a);
  const thumbs = Array.isArray(info?.thumbnails) ? info.thumbnails : [];
  const thumbnail = info?.thumbnail || thumbs.at(-1)?.url || '';
  return {
    id: info?.id || '', title: (isPlaylist ? outer?.title : info?.title) || info?.title || 'Без названия',
    channel: (isPlaylist ? outer?.channel || outer?.uploader : info?.channel || info?.uploader) || '',
    duration: Number.isFinite(info?.duration) ? info.duration : null, thumbnail,
    webpage_url: info?.webpage_url || url, heights, is_live: Boolean(info?.is_live),
    is_playlist: isPlaylist, playlist_count: playlistCount, first_video_title: isPlaylist ? safeString(info?.title, 300) : '',
  };
}

async function validateJobPayload(payload: Json, base: Settings): Promise<{ url: string; mode: 'video' | 'audio'; height: 'best' | number; title: string; settings: Settings }> {
  const url = safeString(payload.url, 4096).trim();
  if (!youtubeUrlOk(url)) throw new Error('Укажите корректную ссылку YouTube.');
  const mode = payload.mode === 'audio' ? 'audio' : payload.mode === 'video' || payload.mode === undefined ? 'video' : null;
  if (!mode) throw new Error('Некорректный режим загрузки.');
  const patch: Partial<Settings> = {};
  for (const k of Object.keys(DEFAULT_SETTINGS) as (keyof Settings)[]) {
    if (Object.prototype.hasOwnProperty.call(payload, k)) (patch as any)[k] = (payload as any)[k];
  }
  const settings = await sanitizeSettings({ ...base, ...patch });
  const purePlaylist = youtubeUrlKind(url) === 'playlist';
  if (purePlaylist) settings.playlist = true;
  await ensureWritableFolder(settings.download_dir);
  let height: 'best' | number = 'best';
  if (payload.height !== undefined && payload.height !== 'best') {
    const n = Number(payload.height);
    if (!Number.isInteger(n) || n < 144 || n > 8640) throw new Error('Некорректное разрешение.');
    height = n;
  }
  return { url, mode, height, title: safeString(payload.title, 300), settings };
}

async function buildDownloadCommand(spec: { url: string; mode: 'video' | 'audio'; height: 'best' | number; title: string; settings: Settings }): Promise<string[]> {
  const s = spec.settings;
  const args = [
    ...(await commonYtdlpArgs(s)), '--newline', '--progress', '--progress-delta', '0.5',
    '--progress-template', 'download:__LOCALTUBE_PROGRESS__:%(progress._percent_str)s\t%(progress._speed_str)s\t%(progress._eta_str)s',
    '--retries', '10', '--fragment-retries', '10', '--file-access-retries', '3', '--retry-sleep', '2',
    '--concurrent-fragments', '4', '--continue', '--part', '--no-overwrites', '--trim-filenames', '180',
    '--paths', s.download_dir, '--print', 'after_move:__LOCALTUBE_FINAL__:%(filepath)s',
  ];
  if (s.playlist) {
    args.push('--yes-playlist', '--output', '%(playlist_title|Playlist).120B/%(playlist_index)03d - %(title).150B [%(id)s].%(ext)s');
  } else {
    args.push('--no-playlist', '--output', '%(title).180B [%(id)s].%(ext)s');
  }

  if (spec.mode === 'video') {
    const cap = spec.height === 'best' ? '' : `[height<=?${spec.height}]`;
    // The requested height is a hard upper bound. For the compatibility MP4 preset, prefer
    // native H.264 + AAC first, then native MP4/M4A, then fall back to any codec if YouTube
    // does not expose a compatible stream at or below the selected resolution. No transcoding
    // is forced, so downloads stay fast and do not degrade quality.
    if (s.video_container === 'mp4') {
      const selector = `bv*${cap}[vcodec^=avc]+ba[acodec^=mp4a]/bv*${cap}[ext=mp4]+ba[ext=m4a]/bv*${cap}+ba/b${cap}`;
      args.push('--format', selector, '--merge-output-format', 'mp4', '--remux-video', 'mp4');
    } else {
      args.push('--format', `bv*${cap}+ba/b${cap}`);
      if (s.video_container === 'mkv') args.push('--merge-output-format', 'mkv', '--remux-video', 'mkv');
    }
    if (s.embed_metadata) args.push('--embed-metadata');
  } else {
    args.push('--extract-audio', '--format', 'ba/b');
    if (s.audio_format !== 'best') args.push('--audio-format', s.audio_format);
    args.push('--audio-quality', s.audio_format === 'mp3' ? s.audio_quality : '0');
    if (s.embed_metadata) args.push('--embed-metadata', '--embed-thumbnail');
  }
  args.push(spec.url);
  return args;
}

function publicJob(j: Job, includeLogs = false): Json {
  const x: Json = {
    id: j.id, url: j.url, mode: j.mode, height: j.height, title: j.title, state: j.state, percent: j.percent,
    speed: j.speed, eta: j.eta, phase: j.phase, playlist_item: j.playlist_item, outputs: [...j.outputs], error: j.error,
    created_at: j.created_at, started_at: j.started_at, finished_at: j.finished_at, download_dir: j.settings.download_dir,
  };
  if (includeLogs) x.logs = [...j.logs.slice(-MAX_LOG_LINES)];
  return x;
}

class JobManager {
  jobs = new Map<string, Job>();
  order: string[] = [];
  queue: string[] = [];
  workerActive = false;
  persistChain: Promise<void> = Promise.resolve();

  async init(): Promise<void> {
    const rows = await readJson<any[]>(HISTORY_FILE, []);
    if (Array.isArray(rows)) {
      for (const item of rows.slice(-MAX_HISTORY)) {
        if (!item || typeof item !== 'object' || !item.id) continue;
        const persistedState = ['completed', 'failed', 'cancelled', 'interrupted'].includes(item.state) ? item.state as JobState : 'failed';
        const state: JobState = ['queued', 'running'].includes(item.state) ? 'interrupted' : persistedState;
        const settings = await sanitizeSettings({ download_dir: item.download_dir || DEFAULT_SETTINGS.download_dir });
        const j: Job = {
          id: safeString(item.id, 64), url: safeString(item.url, 4096), mode: item.mode === 'audio' ? 'audio' : 'video',
          height: item.height === 'best' ? 'best' : Number(item.height) || 'best', title: safeString(item.title, 300), settings,
          state, percent: Number(item.percent) || 0, speed: safeString(item.speed, 80), eta: safeString(item.eta, 80),
          phase: safeString(item.phase, 120), playlist_item: safeString(item.playlist_item, 80),
          outputs: Array.isArray(item.outputs) ? item.outputs.map((x: unknown) => safeString(x, 4096)) : [],
          error: safeString(item.error, 1000), created_at: safeString(item.created_at, 80) || nowIso(),
          started_at: item.started_at || null, finished_at: item.finished_at || null, logs: [], cancel_requested: false,
        };
        this.jobs.set(j.id, j); this.order.push(j.id);
      }
    }
  }
  async persist(): Promise<void> {
    const snapshot = this.order.slice(-MAX_HISTORY).map((id) => publicJob(this.jobs.get(id)!, false)).filter(Boolean);
    this.persistChain = this.persistChain.catch(() => undefined).then(() => atomicWriteJson(HISTORY_FILE, snapshot));
    await this.persistChain;
  }
  hasActive(): boolean {
    return this.order.some((id) => { const j = this.jobs.get(id); return Boolean(j && ['queued', 'running'].includes(j.state)); });
  }
  activeCount(): number {
    return this.order.reduce((n, id) => { const j = this.jobs.get(id); return n + (j && ['queued', 'running'].includes(j.state) ? 1 : 0); }, 0);
  }
  async create(spec: Awaited<ReturnType<typeof validateJobPayload>>): Promise<Job> {
    if (this.activeCount() >= MAX_ACTIVE_JOBS) throw new Error(`В очереди уже ${MAX_ACTIVE_JOBS} активных загрузок. Дождитесь завершения части очереди.`);
    const j: Job = {
      id: crypto.randomUUID().replace(/-/g, '').slice(0, 12), ...spec,
      state: 'queued', percent: 0, speed: '', eta: '', phase: 'В очереди', playlist_item: '', outputs: [], error: '',
      created_at: nowIso(), started_at: null, finished_at: null, logs: [], cancel_requested: false,
    };
    this.jobs.set(j.id, j); this.order.push(j.id);
    while (this.order.length > MAX_HISTORY) {
      const old = this.order[0]; const oj = this.jobs.get(old);
      if (oj && ['queued', 'running'].includes(oj.state)) break;
      this.order.shift(); this.jobs.delete(old);
    }
    this.queue.push(j.id); await this.persist(); void this.work(); return j;
  }
  list(): Json[] { return [...this.order].reverse().map((id) => publicJob(this.jobs.get(id)!, false)); }
  get(id: string): Job | undefined { return this.jobs.get(id); }
  async cancel(id: string): Promise<boolean> {
    const j = this.jobs.get(id); if (!j || !['queued', 'running'].includes(j.state)) return false;
    j.cancel_requested = true;
    if (j.state === 'running') j.phase = 'Отмена…';
    if (j.state === 'queued') { j.state = 'cancelled'; j.phase = 'Отменено'; j.finished_at = nowIso(); }
    if (j.process) void terminateProcessTree(j.process);
    await this.persist(); return true;
  }
  async clearFinished(): Promise<void> {
    this.order = this.order.filter((id) => {
      const j = this.jobs.get(id); if (j && ['queued', 'running'].includes(j.state)) return true;
      this.jobs.delete(id); return false;
    });
    await this.persist();
  }
  log(j: Job, line: string): void {
    const s = line.trimEnd(); if (!s) return;
    j.logs.push(s.slice(-1400)); if (j.logs.length > MAX_LOG_LINES) j.logs.splice(0, j.logs.length - MAX_LOG_LINES);
    if (s.startsWith('__LOCALTUBE_FINAL__:')) {
      const p = s.slice('__LOCALTUBE_FINAL__:'.length).trim(); if (p) j.outputs.push(p); j.percent = 100; j.phase = 'Готово'; return;
    }
    if (s.startsWith('__LOCALTUBE_PROGRESS__:')) {
      const [pct = '', speed = '', eta = ''] = s.slice('__LOCALTUBE_PROGRESS__:'.length).split('\t');
      const n = Number.parseFloat(pct.replace('%', '').trim()); if (Number.isFinite(n)) j.percent = clamp(n, 0, 100);
      j.speed = speed.trim(); j.eta = eta.trim(); j.phase = 'Загрузка'; return;
    }
    const pm = s.match(/\[download\]\s+Downloading item\s+(\d+)\s+of\s+(\d+)/);
    if (pm) { j.playlist_item = `${pm[1]}/${pm[2]}`; j.percent = 0; j.phase = 'Загрузка плейлиста'; return; }
    if (/\[(Merger|VideoRemuxer|VideoConvertor)\]/.test(s)) j.phase = 'Обработка видео';
    else if (/\[(ExtractAudio|Metadata|EmbedThumbnail)\]/.test(s)) j.phase = 'Обработка аудио';
    if (s.startsWith('ERROR:')) j.error = s.slice(6).trim().slice(0, 1000);
  }
  async readLines(stream: ReadableStream<Uint8Array>, j: Job): Promise<void> {
    const reader = stream.pipeThrough(new TextDecoderStream()).getReader();
    let buf = '';
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      buf += value;
      let idx;
      while ((idx = buf.indexOf('\n')) >= 0) { this.log(j, buf.slice(0, idx).replace(/\r$/, '')); buf = buf.slice(idx + 1); }
    }
    if (buf) this.log(j, buf.replace(/\r$/, ''));
  }
  async run(j: Job): Promise<void> {
    j.state = 'running'; j.started_at = nowIso(); j.phase = 'Подготовка'; await this.persist();
    try {
      const args = await buildDownloadCommand(j);
      const root = PLATFORM === 'windows' ? (Deno.env.get('SystemRoot') || 'C:/Windows') : '';
      const childPath = PLATFORM === 'windows'
        ? `${RUNTIME_DIR};${root}/System32;${root}/System32/WindowsPowerShell/v1.0`
        : `${RUNTIME_DIR}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`;
      const childEnv: Record<string, string> = {
        HOME, PATH: childPath,
        USER: Deno.env.get('USER') || Deno.env.get('USERNAME') || '',
        LOGNAME: Deno.env.get('LOGNAME') || Deno.env.get('USER') || Deno.env.get('USERNAME') || '',
        TMPDIR: Deno.env.get('TMPDIR') || Deno.env.get('TEMP') || '/tmp',
        LANG: Deno.env.get('LANG') || 'en_US.UTF-8',
      };
      if (PLATFORM === 'windows') {
        childEnv.USERPROFILE = Deno.env.get('USERPROFILE') || HOME;
        childEnv.SystemRoot = root;
        childEnv.TEMP = Deno.env.get('TEMP') || childEnv.TMPDIR;
      }
      const child = new Deno.Command(YTDLP, {
        args, stdin: 'null', stdout: 'piped', stderr: 'piped', cwd: j.settings.download_dir, env: childEnv,
      }).spawn();
      j.process = child;
      await Promise.all([this.readLines(child.stdout, j), this.readLines(child.stderr, j)]);
      const status = await child.status; j.process = undefined;
      if (j.cancel_requested) { if ((j.state as JobState) !== 'interrupted') { j.state = 'cancelled'; j.phase = 'Отменено'; } }
      else if (status.success) { j.state = 'completed'; j.percent = 100; j.phase = 'Готово'; }
      else {
        j.state = 'failed'; j.phase = 'Ошибка';
        if (!j.error) {
          const tail = [...j.logs].reverse().find((x) => x.includes('ERROR:')) || '';
          j.error = (tail.includes('ERROR:') ? tail.split('ERROR:').at(-1)! : `yt-dlp завершился с кодом ${status.code}`).trim().slice(0, 1000);
        }
      }
    } catch (e) {
      if (!(j.cancel_requested && (j.state as JobState) === 'interrupted')) {
        j.state = 'failed'; j.phase = 'Ошибка'; j.error = safeString(e instanceof Error ? e.message : e, 1000);
      }
    }
    finally { j.finished_at = nowIso(); j.process = undefined; await this.persist(); }
  }
  async shutdown(): Promise<void> {
    const running: Job[] = [];
    for (const id of this.order) {
      const j = this.jobs.get(id); if (!j) continue;
      if (j.state === 'queued') {
        j.cancel_requested = true; j.state = 'interrupted'; j.phase = 'Остановлено вместе с сервисом'; j.finished_at = nowIso();
      } else if (j.state === 'running') {
        j.cancel_requested = true; j.state = 'interrupted'; j.phase = 'Остановлено вместе с сервисом'; j.finished_at = nowIso(); running.push(j);
      }
    }
    this.queue = [];
    await Promise.all(running.map((j) => terminateProcessTree(j.process)));
    await this.persist();
  }
  async work(): Promise<void> {
    if (this.workerActive) return; this.workerActive = true;
    try {
      while (this.queue.length) {
        const id = this.queue.shift()!; const j = this.jobs.get(id);
        if (j && j.state === 'queued' && !j.cancel_requested) await this.run(j);
      }
    } finally { this.workerActive = false; }
  }
}

function windowsPowerShell(): string {
  const root = Deno.env.get('SystemRoot') || 'C:/Windows';
  return `${root}/System32/WindowsPowerShell/v1.0/powershell.exe`;
}
function windowsExplorer(): string {
  const root = Deno.env.get('SystemRoot') || 'C:/Windows';
  return `${root}/explorer.exe`;
}
async function chooseFolder(): Promise<string> {
  if (PLATFORM === 'darwin') {
    const script = 'POSIX path of (choose folder with prompt "Выберите папку для загрузок LocalTube")';
    const r = await runCapture('/usr/bin/osascript', ['-e', script], 120_000);
    if (r.code !== 0) { if (r.stderr.includes('User canceled')) return ''; throw new Error(r.stderr.trim() || 'Не удалось открыть выбор папки.'); }
    return r.stdout.trim().replace(/\/$/, '') || '/';
  }
  if (PLATFORM === 'windows') {
    const script = "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description='Выберите папку для загрузок LocalTube'; if($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){[Console]::Out.Write($d.SelectedPath)}";
    const r = await runCapture(windowsPowerShell(), ['-NoProfile', '-NonInteractive', '-Command', script], 120_000);
    if (r.code !== 0) throw new Error(r.stderr.trim() || 'Не удалось открыть выбор папки.');
    return r.stdout.trim();
  }
  for (const candidate of ['/usr/bin/zenity', '/usr/bin/kdialog']) {
    if (!(await existsFile(candidate))) continue;
    const args = candidate.endsWith('zenity')
      ? ['--file-selection', '--directory', '--title=Выберите папку для загрузок LocalTube']
      : ['--getexistingdirectory', HOME, '--title', 'Выберите папку для загрузок LocalTube'];
    const r = await runCapture(candidate, args, 120_000);
    if (r.code === 0) return r.stdout.trim().replace(/\/$/, '') || '/';
    if (r.code === 1) return '';
  }
  throw new Error('Для выбора папки в Linux установите zenity или kdialog.');
}
async function chooseCookieFile(): Promise<string> {
  if (PLATFORM === 'darwin') {
    const script = 'POSIX path of (choose file with prompt "Выберите cookies.txt для LocalTube")';
    const r = await runCapture('/usr/bin/osascript', ['-e', script], 120_000);
    if (r.code !== 0) { if (r.stderr.includes('User canceled')) return ''; throw new Error(r.stderr.trim() || 'Не удалось открыть выбор файла.'); }
    return r.stdout.trim();
  }
  if (PLATFORM === 'windows') {
    const script = "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Title='Выберите cookies.txt для LocalTube'; $d.Filter='cookies.txt|*.txt|Все файлы|*.*'; if($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){[Console]::Out.Write($d.FileName)}";
    const r = await runCapture(windowsPowerShell(), ['-NoProfile', '-NonInteractive', '-Command', script], 120_000);
    if (r.code !== 0) throw new Error(r.stderr.trim() || 'Не удалось открыть выбор файла.');
    return r.stdout.trim();
  }
  for (const candidate of ['/usr/bin/zenity', '/usr/bin/kdialog']) {
    if (!(await existsFile(candidate))) continue;
    const args = candidate.endsWith('zenity')
      ? ['--file-selection', '--title=Выберите cookies.txt для LocalTube', '--file-filter=*.txt']
      : ['--getopenfilename', HOME, '*.txt', '--title', 'Выберите cookies.txt для LocalTube'];
    const r = await runCapture(candidate, args, 120_000);
    if (r.code === 0) return r.stdout.trim();
    if (r.code === 1) return '';
  }
  throw new Error('Для выбора cookies.txt в Linux установите zenity или kdialog.');
}
async function diskInfo(path: string): Promise<Json> {
  try {
    if (PLATFORM === 'windows') {
      const script = "$p=$args[0]; $full=(Resolve-Path -LiteralPath $p).Path; $root=[System.IO.Path]::GetPathRoot($full); $d=New-Object System.IO.DriveInfo($root); [Console]::Out.Write(('{0}|{1}' -f $d.TotalSize,$d.AvailableFreeSpace))";
      const r = await runCapture(windowsPowerShell(), ['-NoProfile', '-NonInteractive', '-Command', script, path], 8000);
      const [totalRaw, freeRaw] = r.stdout.trim().split('|');
      const total = Number(totalRaw), free = Number(freeRaw);
      if (Number.isFinite(total) && Number.isFinite(free)) return { total, used: total - free, free };
    } else {
      const df = await existsFile('/bin/df') ? '/bin/df' : '/usr/bin/df';
      const r = await runCapture(df, ['-kP', path], 5000);
      const line = r.stdout.trim().split(/\r?\n/).at(-1) || '';
      const parts = line.trim().split(/\s+/); if (parts.length >= 6) {
        const total = Number(parts[1]) * 1024, used = Number(parts[2]) * 1024, free = Number(parts[3]) * 1024;
        if ([total, used, free].every(Number.isFinite)) return { total, used, free };
      }
    }
  } catch { /* ignore */ }
  return { total: 0, used: 0, free: 0 };
}
function openFolderPath(path: string): void {
  try {
    if (PLATFORM === 'darwin') new Deno.Command('/usr/bin/open', { args: [path], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn();
    else if (PLATFORM === 'windows') new Deno.Command(windowsExplorer(), { args: [path], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn();
    else new Deno.Command('/usr/bin/xdg-open', { args: [path], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn();
  } catch { /* ignore */ }
}
function revealPath(path: string): void {
  try {
    if (PLATFORM === 'darwin') new Deno.Command('/usr/bin/open', { args: ['-R', path], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn();
    else if (PLATFORM === 'windows') new Deno.Command(windowsExplorer(), { args: [`/select,${path}`], stdin: 'null', stdout: 'null', stderr: 'null' }).spawn();
    else openFolderPath(dirname(path));
  } catch { /* ignore */ }
}

function securityHeaders(): Headers {
  const h = new Headers();
  h.set('X-Content-Type-Options', 'nosniff'); h.set('X-Frame-Options', 'DENY'); h.set('Referrer-Policy', 'no-referrer');
  h.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  h.set('Content-Security-Policy', "default-src 'self'; img-src 'self' https: data:; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
  return h;
}
function jsonResponse(data: unknown, status = 200): Response {
  const h = securityHeaders(); h.set('Content-Type', 'application/json; charset=utf-8'); h.set('Cache-Control', 'no-store');
  return new Response(JSON.stringify(data), { status, headers: h });
}
function errorResponse(message: string, status = 400): Response { return jsonResponse({ ok: false, error: message }, status); }
function hostOk(req: Request): boolean {
  const host = req.headers.get('host') || '';
  return new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`, '127.0.0.1', 'localhost']).has(host);
}
function apiAllowed(req: Request, token: string): boolean {
  if (!hostOk(req)) return false;
  const origin = req.headers.get('origin');
  if (origin && !new Set([`http://127.0.0.1:${PORT}`, `http://localhost:${PORT}`]).has(origin)) return false;
  const supplied = req.headers.get('x-localtube-token') || '';
  if (supplied.length !== token.length) return false;
  let diff = 0; for (let i = 0; i < token.length; i++) diff |= token.charCodeAt(i) ^ supplied.charCodeAt(i);
  return diff === 0;
}
async function bodyJson(req: Request): Promise<Json> {
  const rawCl = req.headers.get('content-length');
  if (rawCl) {
    const cl = Number(rawCl);
    if (!Number.isFinite(cl) || cl < 0 || cl > MAX_BODY) throw new Error('Некорректный размер запроса.');
  }
  if (!req.body) throw new Error('Пустой запрос.');
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = []; let total = 0;
  while (true) {
    const { value, done } = await reader.read(); if (done) break;
    if (value) {
      total += value.byteLength;
      if (total > MAX_BODY) { try { await reader.cancel(); } catch { /* ignore */ } throw new Error('Запрос слишком большой.'); }
      chunks.push(value);
    }
  }
  if (!total) throw new Error('Пустой запрос.');
  const bytes = new Uint8Array(total); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const text = new TextDecoder().decode(bytes);
  const obj = JSON.parse(text); if (!obj || typeof obj !== 'object' || Array.isArray(obj)) throw new Error('Ожидался JSON-объект.');
  return obj as Json;
}
function contentType(path: string): string {
  if (path.endsWith('.html')) return 'text/html; charset=utf-8';
  if (path.endsWith('.js')) return 'application/javascript; charset=utf-8';
  if (path.endsWith('.css')) return 'text/css; charset=utf-8';
  if (path.endsWith('.svg')) return 'image/svg+xml';
  if (path.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

async function deepDiagnostic(settings: Settings): Promise<Json> {
  const local = await runtimeStatus(true);
  const result: Json = { local, youtube: { ok: false, detail: '' } };
  if (!(local.ready as boolean)) return result;
  try {
    const args = [...(await commonYtdlpArgs(settings)), '--socket-timeout', '15', '--retries', '1', '--skip-download', '--no-playlist', '--dump-single-json', '--no-warnings', TEST_VIDEO_URL];
    const r = await runCapture(YTDLP, args, 60_000);
    (result.youtube as any).ok = r.code === 0;
    (result.youtube as any).detail = r.code === 0 ? 'YouTube extraction OK' : (r.stderr || r.stdout).trim().split(/\r?\n/).at(-1)?.slice(0, 800) || `exit ${r.code}`;
  } catch (e) { (result.youtube as any).detail = safeString(e instanceof Error ? e.message : e, 800); }
  return result;
}

async function main(): Promise<void> {
  await Promise.all([ensureDir(DATA_DIR), ensureDir(LOG_DIR)]);
  const token = await getToken();
  let initialSettings = await loadSettings();
  try {
    await ensureWritableFolder(initialSettings.download_dir);
  } catch {
    initialSettings = await sanitizeSettings({ ...initialSettings, download_dir: DEFAULT_DOWNLOAD_DIR });
    await ensureWritableFolder(initialSettings.download_dir);
  }
  await atomicWriteJson(SETTINGS_FILE, initialSettings);
  const jobs = new JobManager(); await jobs.init();
  console.log(`LocalTube ${(await readText(`${APP_DIR}/VERSION`, 'dev')).trim()} — http://${HOST}:${PORT}`);

  let shuttingDown = false;
  const stopGracefully = (): void => {
    if (shuttingDown) return;
    shuttingDown = true;
    const hardStop = setTimeout(() => Deno.exit(0), 5000);
    void jobs.shutdown().finally(() => { clearTimeout(hardStop); Deno.exit(0); });
  };
  try { Deno.addSignalListener('SIGTERM', stopGracefully); } catch { /* platform without SIGTERM */ }
  try { Deno.addSignalListener('SIGINT', stopGracefully); } catch { /* platform without SIGINT */ }

  Deno.serve({ hostname: HOST, port: PORT }, async (req: Request) => {
    try {
      const url = new URL(req.url);
      if (url.pathname === '/' && req.method === 'GET') {
        if (!hostOk(req)) return errorResponse('Forbidden', 403);
        let html = await Deno.readTextFile(`${STATIC_DIR}/index.html`); html = html.replace('__LOCALTUBE_TOKEN__', token);
        const h = securityHeaders(); h.set('Content-Type', 'text/html; charset=utf-8'); h.set('Cache-Control', 'no-store');
        return new Response(html, { headers: h });
      }
      if (url.pathname.startsWith('/static/') && req.method === 'GET') {
        const rel = decodeURIComponent(url.pathname.slice('/static/'.length));
        if (!rel || rel.includes('..') || rel.startsWith('/') || !/^[A-Za-z0-9._\/-]+$/.test(rel)) return errorResponse('Not found', 404);
        const path = join(STATIC_DIR, rel); if (!(await existsFile(path))) return errorResponse('Not found', 404);
        const h = securityHeaders(); h.set('Content-Type', contentType(path)); h.set('Cache-Control', 'public, max-age=3600');
        return new Response(await Deno.readFile(path), { headers: h });
      }
      if (!url.pathname.startsWith('/api/') || !apiAllowed(req, token)) return errorResponse('Forbidden', 403);

      if (req.method === 'GET' && url.pathname === '/api/health') return jsonResponse({ ok: true, runtime: await runtimeStatus(url.searchParams.get('refresh') === '1') });
      if (req.method === 'GET' && url.pathname === '/api/settings') {
        const s = await loadSettings(); return jsonResponse({ ok: true, settings: s, disk: await diskInfo(s.download_dir) });
      }
      if (req.method === 'GET' && url.pathname === '/api/jobs') return jsonResponse({ ok: true, jobs: jobs.list() });
      let m = url.pathname.match(/^\/api\/jobs\/([a-f0-9]{12})$/);
      if (req.method === 'GET' && m) { const j = jobs.get(m[1]); return j ? jsonResponse({ ok: true, job: publicJob(j, true) }) : errorResponse('Загрузка не найдена', 404); }

      if (req.method === 'POST' && url.pathname === '/api/inspect') {
        const p = await bodyJson(req); const patch: Partial<Settings> = {};
        for (const k of Object.keys(DEFAULT_SETTINGS) as (keyof Settings)[]) if (k in p) (patch as any)[k] = (p as any)[k];
        const settings = await sanitizeSettings({ ...(await loadSettings()), ...patch });
        return jsonResponse({ ok: true, video: await inspectVideo(safeString(p.url, 4096), settings) });
      }
      if (req.method === 'POST' && url.pathname === '/api/settings') {
        const s = await saveSettings(await bodyJson(req) as Partial<Settings>); return jsonResponse({ ok: true, settings: s, disk: await diskInfo(s.download_dir) });
      }
      if (req.method === 'POST' && url.pathname === '/api/select-folder') {
        await bodyJson(req); const folder = await chooseFolder(); if (!folder) return jsonResponse({ ok: true, cancelled: true });
        const s = await saveSettings({ download_dir: folder }); return jsonResponse({ ok: true, settings: s, disk: await diskInfo(s.download_dir) });
      }
      if (req.method === 'POST' && url.pathname === '/api/select-cookie-file') {
        await bodyJson(req); const file = await chooseCookieFile(); if (!file) return jsonResponse({ ok: true, cancelled: true });
        const s = await saveSettings({ cookies_mode: 'file', cookies_file: file }); return jsonResponse({ ok: true, settings: s });
      }
      if (req.method === 'POST' && url.pathname === '/api/jobs') {
        const spec = await validateJobPayload(await bodyJson(req), await loadSettings()); await saveSettings(spec.settings);
        const j = await jobs.create(spec); return jsonResponse({ ok: true, job: publicJob(j, false) }, 201);
      }
      m = url.pathname.match(/^\/api\/jobs\/([a-f0-9]{12})\/cancel$/);
      if (req.method === 'POST' && m) { await bodyJson(req); return jsonResponse({ ok: await jobs.cancel(m[1]) }); }
      m = url.pathname.match(/^\/api\/jobs\/([a-f0-9]{12})\/reveal$/);
      if (req.method === 'POST' && m) {
        await bodyJson(req); const j = jobs.get(m[1]); if (!j) return errorResponse('Загрузка не найдена', 404);
        const target = j.outputs.at(-1) || j.settings.download_dir; if (await existsFile(target)) revealPath(target); else openFolderPath(target); return jsonResponse({ ok: true });
      }
      if (req.method === 'POST' && url.pathname === '/api/open-folder') { await bodyJson(req); openFolderPath((await loadSettings()).download_dir); return jsonResponse({ ok: true }); }
      if (req.method === 'POST' && url.pathname === '/api/update-ytdlp') {
        await bodyJson(req);
        if (jobs.hasActive()) return errorResponse('Обновление загрузчика недоступно, пока есть активные загрузки.', 409);
        return jsonResponse({ ok: true, ...(await transactionalUpdateYtdlp()) });
      }
      if (req.method === 'POST' && url.pathname === '/api/diagnostics') { await bodyJson(req); return jsonResponse({ ok: true, diagnostics: await deepDiagnostic(await loadSettings()) }); }
      if (req.method === 'DELETE' && url.pathname === '/api/jobs/completed') { await jobs.clearFinished(); return jsonResponse({ ok: true }); }
      return errorResponse('Not found', 404);
    } catch (e) {
      const msg = e instanceof SyntaxError ? 'Некорректный JSON.' : safeString(e instanceof Error ? e.message : e, 1200);
      console.error(msg); return errorResponse(msg, msg.includes('слишком долго') ? 504 : 400);
    }
  });
}

if (Deno.args.includes('--self-test')) {
  (async () => {
    await Promise.all([ensureDir(DATA_DIR), ensureDir(LOG_DIR)]);
    const staticOk = await Promise.all(['index.html', 'app.js', 'styles.css'].map((f) => existsFile(`${STATIC_DIR}/${f}`)));
    const status = await runtimeStatus(true);
    const testSettings = await sanitizeSettings({ ...DEFAULT_SETTINGS, cookies_mode: 'none', download_dir: DEFAULT_DOWNLOAD_DIR });
    const videoArgs = await buildDownloadCommand({ url: TEST_VIDEO_URL, mode: 'video', height: 1080, title: 'self-test', settings: testSettings });
    const audioArgs = await buildDownloadCommand({ url: TEST_VIDEO_URL, mode: 'audio', height: 'best', title: 'self-test', settings: testSettings });
    const commandOk = videoArgs.includes('[height<=?1080]') || videoArgs.some((v) => v.includes('[height<=?1080]'));
    const mp4CompatibilityOk = videoArgs.some((v) => v.includes('[vcodec^=avc]')) && videoArgs.some((v) => v.includes('[acodec^=mp4a]'));
    const denoRuntimeOk = videoArgs.includes(`deno:${DENO_BIN}`) && videoArgs.includes('ejs:github');
    const audioOk = audioArgs.includes('--extract-audio') && audioArgs.includes('--audio-format');
    const urlValidationOk = youtubeUrlOk(TEST_VIDEO_URL) && youtubeUrlOk(`https://youtu.be/${TEST_VIDEO_ID}`) &&
      youtubeUrlOk(`https://www.youtube.com/shorts/${TEST_VIDEO_ID}`) && youtubeUrlOk('https://www.youtube.com/playlist?list=PL123') &&
      !youtubeUrlOk('https://www.youtube.com/@channel') && !youtubeUrlOk('https://youtube.com.evil.example/watch?v=x') && !youtubeUrlOk('file:///etc/passwd');
    const ok = Boolean(status.ready) && staticOk.every(Boolean) && commandOk && mp4CompatibilityOk && denoRuntimeOk && audioOk && urlValidationOk;
    console.log(JSON.stringify({
      ok, runtime: status, static_files: staticOk,
      command_builder: { video_cap: commandOk, mp4_compatibility: mp4CompatibilityOk, deno_ejs_runtime: denoRuntimeOk, audio: audioOk },
      url_validation: urlValidationOk,
    }, null, 2));
    Deno.exit(ok ? 0 : 2);
  })().catch((e) => { console.error(e?.stack || e); Deno.exit(2); });
} else {
  main().catch((e) => { console.error(e?.stack || e); Deno.exit(2); });
}
