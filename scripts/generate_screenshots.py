#!/usr/bin/env python3
from pathlib import Path
import tempfile
from weasyprint import HTML, CSS
import fitz
ROOT=Path(__file__).resolve().parents[1]; STATIC=ROOT/'app/static'; OUT=ROOT/'docs/screenshots'; OUT.mkdir(parents=True,exist_ok=True)
base=(STATIC/'index.html').read_text().replace('data-api-token="__LOCALTUBE_TOKEN__"','data-api-token="docs"')
base=base.replace('<link rel="stylesheet" href="/static/styles.css">', '<style>'+ (STATIC/'styles.css').read_text() +'</style>')
# Make a real rendered documentation snapshot from the shipped HTML/CSS; only demo data is injected.
preview='''<div class="video-preview" id="videoPreview"><div class="thumb-wrap"><div style="width:100%;height:100%;background:linear-gradient(135deg,#20242c,#747b87);display:flex;align-items:center;justify-content:center"><svg viewBox="0 0 100 100" style="width:72px;height:72px"><circle cx="50" cy="50" r="42" fill="#fff"/><path d="M42 32l28 18-28 18z" fill="#20242c"/></svg></div><span class="duration-badge" id="durationBadge">12:34</span></div><div class="video-meta"><div class="eyebrow" id="channelName">Демонстрация интерфейса</div><h2 id="videoTitle">Как развивается грозовая ячейка</h2><div class="meta-row" id="videoMeta">до 2160p · 4K · видео</div></div></div>'''
base=base.replace('<div class="video-preview hidden" id="videoPreview">', '<!-- ORIGINAL_PREVIEW_START --><div style="display:none">',1)
# Hide original preview up to its known closing following meta block by a CSS override, and insert docs preview before form.
base=base.replace('<div class="download-form" id="downloadForm">', preview+'<div class="download-form" id="downloadForm">',1)
base=base.replace('<input id="urlInput" type="url" autocomplete="off" spellcheck="false" placeholder="https://www.youtube.com/watch?v=…" aria-label="Ссылка YouTube">','<input id="urlInput" type="url" value="https://www.youtube.com/watch?v=…" aria-label="Ссылка YouTube">')
base=base.replace('<span id="versionText"></span>','<span id="versionText">LocalTube 1.3.0</span>')
base=base.replace('<span class="status-dot"></span><span>Проверка…</span>','<span class="status-dot"></span><span>Окружение готово</span>')
base=base.replace('class="status-pill"','class="status-pill ready"')
base=base.replace('<strong id="downloadDir">—</strong>','<strong id="downloadDir">~/Movies/LocalTube</strong>')
base=base.replace('<span class="muted" id="diskFree"></span>','<span class="muted" id="diskFree">Свободно 296 ГБ</span>')
jobs='''<div class="job running"><div class="job-main"><div class="job-title-line"><span class="job-title">Метеорология: развитие конвективной ячейки</span><span class="job-badge">1080p</span></div><div class="job-meta"><span class="job-state">Загрузка</span><span class="job-extra">8.4 MiB/s · осталось 00:18</span></div></div><div class="job-actions"><button>Отменить</button></div><div class="progress-wrap"><div class="progress-line"><div class="progress-bar" style="width:67%"></div></div><div class="progress-copy"><span>67%</span><span>LocalTube</span></div></div></div><div class="job completed"><div class="job-main"><div class="job-title-line"><span class="job-title">Лекция — атмосферная динамика</span><span class="job-badge">Аудио</span></div><div class="job-meta"><span class="job-state">Готово</span></div></div><div class="job-actions"><button>В Finder</button></div><div class="progress-wrap"><div class="progress-line"><div class="progress-bar" style="width:100%"></div></div><div class="progress-copy"><span>Готово</span><span>Лекция.m4a</span></div></div></div>'''
base=base.replace('<div class="jobs" id="jobs"></div>', '<div class="jobs" id="jobs">'+jobs+'</div>')
base=base.replace('class="empty-state" id="emptyJobs"','class="empty-state hidden" id="emptyJobs"')
# Keep page deterministic for docs.
extra='''<style>@page{size:1440px 1180px;margin:0}html,body{width:1440px;min-height:1180px;background:#f4f5f7!important;color:#1f2329!important}.shell{max-width:1120px!important}.hidden{display:none!important}details.advanced{display:none!important}</style>'''
base=base.replace('</head>',extra+'</head>')

def render(html,name):
    pdf=HTML(string=html,base_url=str(STATIC)).write_pdf()
    doc=fitz.open(stream=pdf,filetype='pdf'); page=doc[0]; pix=page.get_pixmap(matrix=fitz.Matrix(1.0,1.0),alpha=False); pix.save(OUT/name)

render(base,'main.png')
# Audio/settings snapshot: make audio controls and advanced settings visible, hide video groups.
audio=base.replace('class="seg active" data-mode="video"','class="seg" data-mode="video"').replace('class="seg" data-mode="audio"','class="seg active" data-mode="audio"')
audio=audio.replace('class="field-group" id="videoQualityGroup"','class="field-group hidden" id="videoQualityGroup"').replace('class="field-group" id="videoContainerGroup"','class="field-group hidden" id="videoContainerGroup"').replace('class="field-group hidden" id="audioFormatGroup"','class="field-group" id="audioFormatGroup"').replace('class="field-group hidden" id="audioQualityGroup"','class="field-group" id="audioQualityGroup"')
audio=audio.replace('details.advanced{display:none!important}','details.advanced{display:block!important}')
audio=audio.replace('<details class="advanced" id="advancedDetails">','<details class="advanced" id="advancedDetails" open>')
render(audio,'audio-settings.png')
print(OUT)
