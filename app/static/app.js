(() => {
  'use strict';
  const token = document.body.dataset.apiToken || '';
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => [...document.querySelectorAll(s)];
  const state = { mode: 'video', settings: null, video: null, inspectTimer: null, lastInspected: '', poll: null };

  const els = {
    url: $('#urlInput'), paste: $('#pasteBtn'), inspect: $('#inspectBtn'), urlMsg: $('#urlMessage'), preview: $('#videoPreview'),
    thumb: $('#thumb'), duration: $('#durationBadge'), channel: $('#channelName'), title: $('#videoTitle'), meta: $('#videoMeta'),
    quality: $('#qualitySelect'), videoContainer: $('#videoContainer'), audioFormat: $('#audioFormat'), audioQuality: $('#audioQuality'),
    vq: $('#videoQualityGroup'), vc: $('#videoContainerGroup'), af: $('#audioFormatGroup'), aq: $('#audioQualityGroup'),
    downloadDir: $('#downloadDir'), disk: $('#diskFree'), chooseFolder: $('#chooseFolderBtn'), openFolder: $('#openFolderTop'),
    cookiesMode: $('#cookiesMode'), cookiesBrowser: $('#cookiesBrowser'), browserCookieGroup: $('#browserCookieGroup'),
    cookieFileGroup: $('#cookieFileGroup'), chooseCookie: $('#chooseCookieBtn'), cookieFileName: $('#cookieFileName'),
    playlist: $('#playlistToggle'), metadata: $('#metadataToggle'), download: $('#downloadBtn'), dlMsg: $('#downloadMessage'),
    jobs: $('#jobs'), empty: $('#emptyJobs'), clear: $('#clearHistoryBtn'), runtime: $('#runtimeStatus'), version: $('#versionText'),
    diagnose: $('#diagnoseBtn'), updateYtdlp: $('#updateYtdlpBtn'), toasts: $('#toasts')
  };

  async function api(path, options = {}) {
    const opts = { ...options, headers: { ...(options.headers || {}), 'X-LocalTube-Token': token } };
    if (options.body && typeof options.body !== 'string') {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(options.body);
    }
    const r = await fetch(path, opts);
    let data = null;
    try { data = await r.json(); } catch (_) {}
    if (!r.ok || data?.ok === false) throw new Error(data?.error || `HTTP ${r.status}`);
    return data;
  }

  function fmtBytes(n) {
    if (!Number.isFinite(n) || n <= 0) return '';
    const u = ['Б','КБ','МБ','ГБ','ТБ']; let i = 0; let v = n;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return `${v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)} ${u[i]}`;
  }
  function fmtDuration(sec) {
    if (!Number.isFinite(sec) || sec < 0) return '';
    const s = Math.floor(sec % 60), m0 = Math.floor(sec / 60), m = m0 % 60, h = Math.floor(m0 / 60);
    return h ? `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}` : `${m}:${String(s).padStart(2,'0')}`;
  }
  function basename(p) { return (p || '').replace(/[\\\/]$/, '').split(/[\\\/]/).pop() || p || ''; }
  function toast(text) {
    const el = document.createElement('div'); el.className = 'toast'; el.textContent = text; els.toasts.appendChild(el);
    setTimeout(() => el.remove(), 3600);
  }
  function showMsg(el, text, success = false) {
    el.textContent = text || ''; el.classList.toggle('hidden', !text); el.classList.toggle('success', !!success);
  }

  function collectSettings() {
    return {
      download_dir: state.settings?.download_dir,
      cookies_mode: els.cookiesMode.value,
      cookies_browser: els.cookiesBrowser.value,
      cookies_file: state.settings?.cookies_file || '',
      video_container: els.videoContainer.value,
      audio_format: els.audioFormat.value,
      audio_quality: els.audioQuality.value,
      embed_metadata: els.metadata.checked,
      playlist: els.playlist.checked
    };
  }

  function applySettings(s, disk) {
    state.settings = s;
    els.downloadDir.textContent = s.download_dir || '—';
    els.downloadDir.title = s.download_dir || '';
    if (disk !== undefined) els.disk.textContent = disk?.free ? `Свободно ${fmtBytes(disk.free)}` : '';
    els.cookiesMode.value = s.cookies_mode || 'none';
    els.cookiesBrowser.value = s.cookies_browser || 'chrome';
    els.videoContainer.value = s.video_container || 'mp4';
    els.audioFormat.value = s.audio_format || 'm4a';
    els.audioQuality.value = s.audio_quality || '192K';
    els.metadata.checked = s.embed_metadata !== false;
    els.playlist.checked = !!s.playlist;
    els.cookieFileName.textContent = s.cookies_file ? basename(s.cookies_file) : 'Файл не выбран';
    updateCookieFields(); updateAudioQuality();
  }

  function updateCookieFields() {
    const m = els.cookiesMode.value;
    els.browserCookieGroup.classList.toggle('hidden', m !== 'browser');
    els.cookieFileGroup.classList.toggle('hidden', m !== 'file');
  }
  function updateAudioQuality() {
    els.aq.classList.toggle('hidden', state.mode !== 'audio' || els.audioFormat.value !== 'mp3');
  }
  function setMode(mode) {
    state.mode = mode;
    $$('.seg').forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
    els.vq.classList.toggle('hidden', mode !== 'video');
    els.vc.classList.toggle('hidden', mode !== 'video');
    els.af.classList.toggle('hidden', mode !== 'audio');
    updateAudioQuality();
  }

  async function loadInitial() {
    try {
      const [s, h] = await Promise.all([api('/api/settings'), api('/api/health')]);
      applySettings(s.settings, s.disk); applyHealth(h.runtime);
    } catch (e) { showMsg(els.urlMsg, e.message); }
    await refreshJobs();
    state.poll = setInterval(refreshJobs, 1000);
    setInterval(checkHealth, 30000);
  }

  function applyHealth(rt) {
    els.runtime.classList.toggle('ready', !!rt?.ready); els.runtime.classList.toggle('error', !rt?.ready);
    els.runtime.querySelector('span:last-child').textContent = rt?.ready ? 'Окружение готово' : 'Нужна установка';
    els.runtime.title = rt?.ready ? `yt-dlp ${rt.yt_dlp?.version || ''} · Deno ${rt.deno?.version || ''}` : 'Не найдены yt-dlp, ffmpeg/ffprobe или Deno';
    els.version.textContent = rt?.app_version ? `LocalTube ${rt.app_version}` : '';
    els.download.disabled = !rt?.ready;
  }
  async function checkHealth() { try { applyHealth((await api('/api/health')).runtime); } catch (_) {} }

  function renderPreview(v) {
    state.video = v;
    els.preview.classList.remove('hidden');
    els.thumb.src = v.thumbnail || '';
    els.thumb.style.visibility = v.thumbnail ? 'visible' : 'hidden';
    els.duration.textContent = fmtDuration(v.duration);
    els.duration.classList.toggle('hidden', !v.duration);
    els.channel.textContent = v.channel || 'YouTube';
    els.title.textContent = v.title || 'Без названия';
    const hs = (v.heights || []).filter(n => Number.isFinite(n));
    if (v.is_playlist) els.playlist.checked = true;
    els.meta.textContent = [v.is_playlist ? `Плейлист${v.playlist_count ? ` · ${v.playlist_count} видео` : ''}` : '', v.is_live ? 'Прямая трансляция' : '', hs.length ? `до ${Math.max(...hs)}p` : '', v.is_playlist && v.first_video_title ? `качество по первому: ${v.first_video_title}` : ''].filter(Boolean).join(' · ');
    if (hs.length) {
      const current = els.quality.value;
      const vals = ['best', ...hs.map(String)];
      els.quality.innerHTML = '';
      for (const val of vals) {
        const o = document.createElement('option'); o.value = val;
        o.textContent = val === 'best' ? 'Лучшее доступное' : `${val}p`;
        els.quality.appendChild(o);
      }
      if (vals.includes(current)) els.quality.value = current;
      else if (vals.includes('1080')) els.quality.value = '1080';
      else els.quality.value = 'best';
    }
  }

  async function inspectUrl(force = false) {
    const url = els.url.value.trim();
    if (!url) { showMsg(els.urlMsg, 'Вставьте ссылку YouTube.'); return; }
    if (!force && url === state.lastInspected) return;
    showMsg(els.urlMsg, ''); els.inspect.disabled = true; els.inspect.textContent = 'Определяю…';
    try {
      const data = await api('/api/inspect', { method: 'POST', body: { url, ...collectSettings() } });
      state.lastInspected = url; renderPreview(data.video);
    } catch (e) {
      state.video = null; els.preview.classList.add('hidden'); showMsg(els.urlMsg, e.message);
    } finally { els.inspect.disabled = false; els.inspect.textContent = 'Определить'; }
  }

  function scheduleInspect() {
    clearTimeout(state.inspectTimer);
    const url = els.url.value.trim();
    if (url !== state.lastInspected) state.video = null;
    if (!/^https?:\/\//i.test(url)) return;
    state.inspectTimer = setTimeout(() => inspectUrl(false), 650);
  }

  async function startDownload() {
    const url = els.url.value.trim();
    if (!url) return showMsg(els.dlMsg, 'Вставьте ссылку YouTube.');
    els.download.disabled = true; showMsg(els.dlMsg, '');
    try {
      const payload = { url, mode: state.mode, height: els.quality.value, title: state.video?.title || '', ...collectSettings() };
      await api('/api/jobs', { method: 'POST', body: payload });
      showMsg(els.dlMsg, 'Добавлено в очередь.', true); toast('Загрузка добавлена в очередь');
      await refreshJobs();
      setTimeout(() => showMsg(els.dlMsg, ''), 2200);
    } catch (e) { showMsg(els.dlMsg, e.message); }
    finally { const h = await api('/api/health').catch(() => null); els.download.disabled = h ? !h.runtime.ready : false; }
  }

  function jobLabel(j) {
    if (j.mode === 'audio') return 'Аудио';
    return j.height === 'best' ? 'Лучшее' : `${j.height}p`;
  }
  function stateText(j) {
    return ({queued:'В очереди',running:j.phase || 'Загрузка',completed:'Готово',failed:'Ошибка',cancelled:'Отменено',interrupted:'Прервано'})[j.state] || j.state;
  }
  function renderJobs(rows) {
    els.jobs.innerHTML = ''; els.empty.classList.toggle('hidden', rows.length > 0); els.clear.classList.toggle('hidden', rows.length === 0);
    for (const j of rows) {
      const card = document.createElement('div'); card.className = `job ${j.state}`;
      const pct = Number.isFinite(j.percent) ? Math.max(0, Math.min(100, j.percent)) : 0;
      const title = j.title || 'YouTube — загрузка';
      card.innerHTML = `
        <div class="job-main">
          <div class="job-title-line"><span class="job-title"></span><span class="job-badge"></span></div>
          <div class="job-meta"><span class="job-state"></span><span class="job-extra"></span></div>
        </div>
        <div class="job-actions"></div>
        <div class="progress-wrap">
          <div class="progress-line"><div class="progress-bar"></div></div>
          <div class="progress-copy"><span class="progress-left"></span><span class="progress-right"></span></div>
        </div>`;
      card.querySelector('.job-title').textContent = title;
      card.querySelector('.job-badge').textContent = jobLabel(j);
      card.querySelector('.job-state').textContent = stateText(j);
      const sizeText = j.state === 'completed' && j.final_size_bytes
        ? fmtBytes(j.final_size_bytes)
        : j.total_bytes ? `${fmtBytes(j.downloaded_bytes)} / ${j.total_is_estimate ? '≈' : ''}${fmtBytes(j.total_bytes)}`
        : j.downloaded_bytes ? fmtBytes(j.downloaded_bytes) : '';
      const extra = [j.playlist_item ? `Видео ${j.playlist_item}` : '', j.speed || '', j.eta ? `осталось ${j.eta}` : ''].filter(Boolean).join(' · ');
      card.querySelector('.job-extra').textContent = extra;
      card.classList.toggle('postprocessing', j.state === 'running' && !!j.postprocessing);
      card.querySelector('.progress-bar').style.width = `${j.state === 'completed' ? 100 : pct}%`;
      card.querySelector('.progress-left').textContent = j.state === 'running'
        ? (j.postprocessing ? stateText(j) : `${Math.round(pct)}%${sizeText ? ` · ${sizeText}` : ''}`)
        : `${stateText(j)}${sizeText ? ` · ${sizeText}` : ''}`;
      card.querySelector('.progress-right').textContent = j.outputs?.length ? basename(j.outputs[j.outputs.length - 1]) : (j.current_file ? basename(j.current_file) : basename(j.download_dir || ''));
      const actions = card.querySelector('.job-actions');
      if (['queued','running'].includes(j.state)) {
        const b = document.createElement('button'); b.textContent = 'Отменить'; b.onclick = () => cancelJob(j.id); actions.appendChild(b);
      } else if (j.outputs?.length || j.download_dir) {
        const b = document.createElement('button'); b.textContent = 'Показать файл'; b.onclick = () => revealJob(j.id); actions.appendChild(b);
      }
      if (j.error) { const e = document.createElement('div'); e.className = 'error-copy'; e.textContent = j.error; card.appendChild(e); }
      els.jobs.appendChild(card);
    }
  }
  async function refreshJobs() { try { renderJobs((await api('/api/jobs')).jobs || []); } catch (_) {} }
  async function cancelJob(id) { try { await api(`/api/jobs/${id}/cancel`, {method:'POST', body:{}}); await refreshJobs(); } catch(e) { toast(e.message); } }
  async function revealJob(id) { try { await api(`/api/jobs/${id}/reveal`, {method:'POST', body:{}}); } catch(e) { toast(e.message); } }

  async function runDiagnostics() {
    els.diagnose.disabled = true;
    try {
      const d = (await api('/api/diagnostics', {method:'POST', body:{}})).diagnostics;
      const ok = !!d?.local?.ready && !!d?.youtube?.ok;
      toast(ok ? 'Окружение и извлечение YouTube работают' : `Проверка: ${d?.youtube?.detail || 'есть проблема с окружением'}`);
      await checkHealth();
    } catch (e) { toast(e.message); }
    finally { els.diagnose.disabled = false; }
  }

  async function updateYtdlp() {
    els.updateYtdlp.disabled = true;
    const old = els.updateYtdlp.textContent; els.updateYtdlp.textContent = 'Обновляю…';
    try {
      const d = await api('/api/update-ytdlp', {method:'POST', body:{}});
      toast(d.before === d.after ? `yt-dlp уже актуален: ${d.after || ''}` : `yt-dlp обновлён: ${d.before || '?'} → ${d.after || '?'}`);
      await checkHealth();
    } catch (e) { toast(e.message); }
    finally { els.updateYtdlp.disabled = false; els.updateYtdlp.textContent = old; }
  }

  $$('.seg').forEach(b => b.addEventListener('click', () => setMode(b.dataset.mode)));
  els.audioFormat.addEventListener('change', updateAudioQuality);
  els.cookiesMode.addEventListener('change', updateCookieFields);
  els.url.addEventListener('input', scheduleInspect);
  els.url.addEventListener('keydown', e => { if (e.key === 'Enter') inspectUrl(true); });
  els.inspect.addEventListener('click', () => inspectUrl(true));
  els.paste.addEventListener('click', async () => {
    try { els.url.value = await navigator.clipboard.readText(); scheduleInspect(); }
    catch (_) { els.url.focus(); toast('Вставьте ссылку стандартным сочетанием вставки'); }
  });
  els.download.addEventListener('click', startDownload);
  els.chooseFolder.addEventListener('click', async () => {
    els.chooseFolder.disabled = true;
    try { const d = await api('/api/select-folder', {method:'POST', body:{}}); if (!d.cancelled) applySettings(d.settings, d.disk); }
    catch(e) { toast(e.message); } finally { els.chooseFolder.disabled = false; }
  });
  els.chooseCookie.addEventListener('click', async () => {
    try { const d = await api('/api/select-cookie-file', {method:'POST', body:{}}); if (!d.cancelled) applySettings(d.settings); }
    catch(e) { toast(e.message); }
  });
  els.openFolder.addEventListener('click', () => api('/api/open-folder', {method:'POST', body:{}}).catch(e => toast(e.message)));
  els.clear.addEventListener('click', async () => { try { await api('/api/jobs/completed', {method:'DELETE'}); await refreshJobs(); } catch(e) { toast(e.message); } });
  els.runtime.addEventListener('click', runDiagnostics);
  els.diagnose.addEventListener('click', runDiagnostics);
  els.updateYtdlp.addEventListener('click', updateYtdlp);

  loadInitial();
})();
