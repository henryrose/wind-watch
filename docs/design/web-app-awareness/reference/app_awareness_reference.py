"""Web → iOS app awareness: options board + three web boards with the chosen treatments applied."""
import re, sys, os, segno, io
sys.path.insert(0, os.path.dirname(__file__))
from brand3 import icon
P = '/tmp/claude-0/-home-claude/a384ae73-6c1a-562c-b643-469c860f5b26/scratchpad/ww/project/'
TXT = "-apple-system, 'SF Pro Text', system-ui, sans-serif"
RND = "-apple-system, 'SF Pro Rounded', system-ui, sans-serif"
RAMP = {0:'#5C6B7A',1:'#5C6B7A',2:'#4FA3D8',3:'#3FC2A0',4:'#8DD44A',5:'#F2D13D',6:'#F59A2B',7:'#EC5A2A',8:'#E0245E'}
def bft(k):
    for b,hi in [(0,0.5),(1,3.5),(2,6.5),(3,10.5),(4,16.5),(5,21.5),(6,27.5),(7,33.5),(8,40.5)]:
        if k<hi: return b
    return 8
STRIP = [(3,4),(4,5),(2,3),(3,3),(4,4),(6,8),(9,12),(12,16),(14,19),(15,22),(15,25),(13,21)]

def qr_svg(size=96, url='https://windwatch.app/ios'):
    q = segno.make(url, error='m'); m = q.matrix; n = len(m); quiet = 2
    cell = size/(n+2*quiet); o=[f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" role="img" aria-label="QR code: {url}"><rect width="{size}" height="{size}" rx="6" fill="#FFFFFF"/>']
    for y,row in enumerate(m):
        for x,v in enumerate(row):
            if v: o.append(f'<rect x="{(x+quiet)*cell:.2f}" y="{(y+quiet)*cell:.2f}" width="{cell+0.05:.2f}" height="{cell+0.05:.2f}" fill="#0B0E12"/>')
    return ''.join(o)+'</svg>'

def comp_mini(W=172, H=64, scale=1.0):
    """A small rendering of the rectangular complication — the thing the web can't do."""
    top=28; plotH=H-top-4; ymax=30; slot=W/12
    o=[f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" aria-hidden="true" style="display:block">',
       f'<rect width="{W}" height="{H}" rx="10" fill="#000000"/>',
       f'<text x="8" y="21" font-family="{RND}" font-weight="800" font-size="20" fill="#FFFFFF">3</text>',
       f'<text x="22" y="21" font-family="{RND}" font-weight="700" font-size="10" fill="#FFFFFF" fill-opacity="0.9">G4</text>',
       f'<g transform="translate(48,16) rotate(110)"><path d="M0,-4 L3,4 L0,1.6 L-3,4 Z" fill="#FFFFFF"/></g>',
       f'<text x="55" y="20" font-family="{TXT}" font-weight="600" font-size="9" fill="#FFFFFF">from W</text>',
       f'<text x="{W-8}" y="20" text-anchor="end" font-family="{TXT}" font-weight="500" font-size="10" fill="#9AA4B1">as of 09:00</text>']
    for i,(k,g) in enumerate(STRIP):
        x=i*slot+4; bw=slot*0.72-1; y=top+plotH-(k/ymax)*plotH; gy=top+plotH-(g/ymax)*plotH
        o.append(f'<rect x="{x+(slot*0.72-bw)/2:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{top+plotH-y:.1f}" rx="1.5" fill="{RAMP[bft(k)]}"/>')
        o.append(f'<line x1="{x-1:.1f}" x2="{x+bw+1:.1f}" y1="{gy:.1f}" y2="{gy:.1f}" stroke="#FFFFFF" stroke-width="1"/>')
    pts=' '.join(f'{i*slot+4+slot*0.36:.1f},{top+plotH-(g/ymax)*plotH:.1f}' for i,(k,g) in enumerate(STRIP))
    o.append(f'<polyline points="{pts}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="1"/>')
    return ''.join(o)+'</svg>'

def store_link(size=14, pad='8px 14px'):
    return (f'<a href="https://apps.apple.com" style="display: inline-flex; align-items: center; gap: 8px; padding: {pad}; border-radius: 999px; background: #FFFFFF; color: #0B0E12; text-decoration: none; font-size: {size}px; font-weight: 700; white-space: nowrap">'
            f'<svg width="{size}" height="{size}" viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.5 L8 10.5 M4.5 7 L8 10.5 L11.5 7 M2.5 13.5 L13.5 13.5" fill="none" stroke="#0B0E12" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>Get it on the App Store</a>')

def promo_card(desktop=True):
    """Persistent card above the footer: 'the same forecast, on your wrist'. Never dismissed; it's part of the page."""
    body='The same forecast, on your wrist: the next 12 hours as a watch-face complication, the now readout a glance away, up to 12 saved spots. Free.'
    if desktop:
        return f'''<section aria-label="Wind Watch for iPhone and Apple Watch" style="display: flex; align-items: center; gap: 24px; background: #171C23; border-radius: 10px; padding: 20px 24px; flex-wrap: wrap">
      {icon(48, label='Wind Watch app icon')}
      <div style="display: flex; flex-direction: column; gap: 6px; flex: 1 1 260px; min-width: 0">
        <div style="font-size: 17px; line-height: 22px; font-weight: 700">Wind Watch for iPhone and Apple Watch</div>
        <div style="font-size: 14px; line-height: 19px; color: #9AA4B1">{body}</div>
        <div style="margin-top: 4px; font-size: 13px; color: #9AA4B1">windwatch.app/ios</div>
      </div>
      <div style="display: flex; align-items: center; gap: 22px">
        <div style="display: flex; flex-direction: column; gap: 6px; align-items: center">{comp_mini()}<span style="font-size: 11px; color: #5C6B7A">on the watch face</span></div>
        <div style="display: flex; flex-direction: column; align-items: center; gap: 6px">{qr_svg(96)}<span style="font-size: 11px; color: #5C6B7A">scan on your iPhone</span></div>
      </div>
    </section>'''
    return f'''<section aria-label="Wind Watch for iPhone and Apple Watch" style="display: flex; flex-direction: column; gap: 12px; background: #171C23; border-radius: 10px; padding: 16px">
      <div style="display: flex; align-items: center; gap: 12px">{icon(40, label='Wind Watch app icon')}<div style="font-size: 16px; line-height: 21px; font-weight: 700">Wind Watch for iPhone and Apple Watch</div></div>
      <div style="font-size: 13px; line-height: 18px; color: #9AA4B1">{body}</div>
      <div style="display: flex; flex-direction: column; gap: 6px; align-items: center">{comp_mini(W=326, H=76)}<span style="font-size: 11px; color: #5C6B7A">the rectangular complication, 12 hours</span></div>
      <div style="display: flex; justify-content: center; margin-top: 2px">{store_link(15, '10px 18px')}</div>
    </section>'''

def smart_banner():
    """Apple's Smart App Banner as Safari draws it (light system UI; not ours to style)."""
    return f'''<div aria-label="Safari Smart App Banner (system UI)" style="display: flex; align-items: center; gap: 12px; height: 84px; padding: 0 12px 0 10px; background: #F2F2F7; color: #000000; border-bottom: 1px solid #C6C6C8; font-family: {TXT}">
      <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 4 L12 12 M12 4 L4 12" stroke="#8E8E93" stroke-width="1.6" stroke-linecap="round"/></svg>
      <svg width="56" height="56" viewBox="0 0 180 180" aria-hidden="true"><defs><clipPath id="sbq"><rect width="180" height="180" rx="40"/></clipPath></defs><g clip-path="url(#sbq)"><rect width="180" height="180" fill="#0B0E12"/></g><g transform="translate(115.2,101.8) rotate(103)"><line x1="-22" x2="-22" y1="58" y2="80" stroke="#4FA3D8" stroke-width="11" stroke-linecap="round"/><line x1="0" x2="0" y1="58" y2="92" stroke="#3FC2A0" stroke-width="11" stroke-linecap="round"/><line x1="22" x2="22" y1="58" y2="84" stroke="#8DD44A" stroke-width="11" stroke-linecap="round"/><path d="M0,-46 L34.5,46 L0,18.4 L-34.5,46 Z" fill="#FFFFFF"/></g></svg>
      <div style="display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0"><span style="font-size: 15px; font-weight: 600">Wind Watch</span><span style="font-size: 12px; color: #6C6C70">The bay's wind, on your wrist</span><span style="font-size: 12px; color: #6C6C70">FREE · On the App Store</span></div>
      <span style="font-size: 15px; font-weight: 600; color: #007AFF; padding: 6px 14px; border-radius: 999px; background: #E5E5EA">View</span>
    </div>'''

def own_strip():
    """Our own one-line strip for iOS browsers that don't draw the Smart Banner (Chrome, Firefox, in-app browsers). Dismissable, remembered 30 days."""
    return f'''<div role="region" aria-label="Also on iPhone and Apple Watch" style="display: flex; align-items: center; gap: 10px; padding: 10px 10px 10px 12px; border-radius: 10px; background: #171C23; box-shadow: inset 0 0 0 1px #2A2F36">
      {icon(28)}
      <span style="flex: 1; font-size: 14px; line-height: 18px; font-weight: 600; min-width: 0">Also on iPhone and Apple Watch <span style="font-weight: 500; color: #9AA4B1">— the 12-hour strip as a complication.</span></span>
      <a href="https://apps.apple.com" style="font-size: 14px; font-weight: 700; color: #FFFFFF; text-decoration: none; white-space: nowrap; padding: 6px 12px; border-radius: 999px; background: #2A2F36">Get it</a>
      <button type="button" aria-label="Dismiss for 30 days" style="width: 32px; height: 32px; border: 0; background: transparent; color: #9AA4B1; display: flex; align-items: center; justify-content: center; cursor: pointer; margin-right: -4px"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M3 3 L11 11 M11 3 L3 11" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></button>
    </div>'''

def header_link():
    return '<a href="https://apps.apple.com" style="font-size: 12px; font-weight: 600; color: #9BB7D4; text-decoration: none; white-space: nowrap">iPhone &amp; Watch app →</a>'

def build_phone(variant):
    s = open(P+'Web-Phone.dc.html').read()
    s = s.replace('<title>Wind Watch — Port Townsend Bay</title>', f'<title>Wind Watch — web on iPhone ({variant})</title>')
    # header tagline → app link
    s = s.replace('<span style="font-size: 12px; color: #5C6B7A">HRRR wind · Port Townsend Bay, WA</span>', header_link(), 1)
    # footer: card above it
    s = s.replace('<footer style="font-size: 13px;', promo_card(desktop=False)+'\n    <footer style="font-size: 13px;', 1)
    if variant == 'safari':
        s = s.replace('<div style="min-height: 100vh; box-sizing: border-box; background: #0B0E12;', smart_banner()+'\n<div style="min-height: 100vh; box-sizing: border-box; background: #0B0E12;', 1)
    else:
        s = s.replace('<header style="display: flex; flex-direction: column; gap: 6px">', own_strip()+'\n    <header style="display: flex; flex-direction: column; gap: 6px">', 1)
    s = s.replace('"$preview":{"width":390,"height":1100}', '"$preview":{"width":390,"height":1200}')
    return s

def build_desktop():
    s = open(P+'Web-Desktop.dc.html').read()
    s = s.replace('<title>Wind Watch — Port Townsend Bay</title>', '<title>Wind Watch — web desktop with app card</title>')
    s = s.replace('<span style="font-size: 12px; color: #5C6B7A">HRRR wind · Port Townsend Bay, WA</span>', '<span style="display: inline-flex; align-items: center; gap: 16px"><span style="font-size: 12px; color: #5C6B7A">HRRR wind · Port Townsend Bay, WA</span>'+header_link()+'</span>', 1)
    s = s.replace('<footer style="display: flex; flex-wrap: wrap;', promo_card(desktop=True)+'\n    <footer style="display: flex; flex-wrap: wrap;', 1)
    s = s.replace('"$preview":{"width":1280,"height":1040}', '"$preview":{"width":1280,"height":1200}')
    return s

def options_board():
    def tile(n, title, verdict, vcol, mock, body):
        return f'''<div style="display: flex; flex-direction: column; gap: 10px; border: 1px solid #2A2F36; border-radius: 12px; padding: 14px 16px; min-width: 0">
      <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px"><span style="font-size: 15px; font-weight: 700"><span style="color: #9AA4B1; font-weight: 600; margin-right: 6px">{n}</span>{title}</span><span style="font-size: 11px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; padding: 3px 8px; border-radius: 999px; background: {vcol}; color: #000">{verdict}</span></div>
      <div style="background: #0B0E12; border: 1px solid #171C23; border-radius: 10px; padding: 10px; overflow: hidden">{mock}</div>
      <div style="font-size: 12.5px; line-height: 1.5; color: #C7CED8">{body}</div>
    </div>'''
    GO, MAYBE, NO = '#8DD44A', '#F2D13D', '#5C6B7A'
    m1 = f'<div style="height: 72px; overflow: hidden"><div style="transform: scale(0.86); transform-origin: top left; width: 116%">{smart_banner()}</div></div>'
    m2 = f'<div style="height: 104px; overflow: hidden"><div style="transform: scale(0.62); transform-origin: top left; width: 161%; color: #FFFFFF; font-family: {TXT}">{promo_card(desktop=True)}</div></div>'
    m3 = f'<div style="display: flex; align-items: center; justify-content: space-between; padding-bottom: 10px; border-bottom: 1px solid #171C23"><div style="display: flex; align-items: center; gap: 8px">{icon(22)}<span style="font-family: {RND}; font-size: 18px; font-weight: 800; letter-spacing: -0.03em">Wind<span style="font-weight: 500; color: #9AA4B1"> Watch</span></span></div>{header_link()}</div>'
    m4 = f'<div style="color: #FFFFFF; font-family: {TXT}">{own_strip()}</div>'
    m5 = f'''<div style="display: flex; flex-direction: column; gap: 8px; color: #FFFFFF; font-family: {TXT}">
      <div style="display: flex; justify-content: space-between; font-size: 12px; color: #9AA4B1"><span><b style="color: #FFFFFF">Sat 1–4pm</b> · outing with Henry</span><span>windwatch.app/o/7Q2K</span></div>
      <div style="height: 54px; border-radius: 8px; background: #171C23; position: relative"><div style="position: absolute; left: 33%; width: 34%; top: 0; bottom: 0; background: rgba(255,255,255,0.07); border-left: 1.5px solid #fff; border-right: 1.5px solid #fff"></div></div>
      <div style="display: flex; align-items: center; gap: 10px; padding: 10px 12px; border-radius: 10px; background: #171C23">{icon(28)}<span style="flex: 1; font-size: 13px; line-height: 17px"><b>Keep this one on your wrist.</b> <span style="color: #9AA4B1">The Saturday forecast as a complication, updating until you cast off.</span></span>{store_link(12, '6px 10px')}</div>
    </div>'''
    m6 = f'''<div style="display: flex; align-items: center; justify-content: center; height: 72px; color: #5C6B7A; font-size: 13px; text-align: center; line-height: 1.5"><span>Full-screen "Open in the app" interstitial,<br>"Install our app" modal, nag on every visit.<br><b style="color: #9AA4B1">Not drawn on purpose.</b></span></div>'''
    tiles = [
      tile(1, 'Safari Smart App Banner', 'build first', GO, m1, 'One <span style="font-family: ui-monospace, Menlo, monospace">&lt;meta name="apple-itunes-app" content="app-id=…, app-argument=https://windwatch.app/…"&gt;</span> tag. Safari on iOS draws it, in system light/dark, with <b>View</b> for new users and <b>Open</b> when the app is installed; the user dismisses it once and Safari remembers. Zero design, zero code, zero nagging. Only Safari on iOS — nothing on Chrome/Firefox iOS, nothing on desktop.'),
      tile(2, 'Persistent card above the footer', 'build', GO, m2, 'Lives on every page, every browser, never dismissed — it is part of the page like the data credit. Icon + one sentence of what the web can\'t do (a complication, the now readout, saved spots) + the <b>thing itself</b>: a small drawing of the rectangular complication. Desktop adds a QR because the phone is in the other hand; phone shows the store link. Below the fold on purpose: someone who scrolled past the table is interested.'),
      tile(3, 'Header link', 'build', GO, m3, 'Replaces the "HRRR wind · Port Townsend Bay, WA" tagline on phone widths, sits beside it on desktop. 12 pt, link colour, no icon, no badge. Always findable, never in the way. On an iPhone with the app installed it becomes <b>Open in app</b> via the universal link.'),
      tile(4, 'Our own strip (non-Safari iOS)', 'build, gated', MAYBE, m4, 'For iOS browsers that never draw the Smart Banner (Chrome, Firefox, the Slack/Messages in-app browsers that text2sail links open in). Shown once under the header, <b>✕</b> remembered for 30 days in localStorage, never shown on desktop or Android (there is no Android app — say nothing there). Rule: never together with the Smart Banner; detect Safari and skip.'),
      tile(5, 'The outing page is the best moment', 'build with text2sail', GO, m5, 'Someone arriving from a text2sail link is new, on their phone, and about to go sailing. Under the chart, one card: <b>Keep this one on your wrist</b>. The universal link into the app opens that outing\'s location pre-selected so the complication shows Saturday. The highest-intent visit the web will ever get — don\'t waste it on a generic banner.'),
      tile(6, 'Interstitials, modals, nags', 'no', NO, m6, 'The web view is a first-class surface and must stay the fallback that always works — for MMS-stripped carriers, for friends on Android, for a laptop at the yacht club. Nothing that blocks the chart, nothing that repeats, nothing that asks twice. If someone said no once, the footer card is the only reminder they ever get.'),
    ]
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Web → iOS app awareness, six treatments</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0;background:#262D36}}
a{{color:#9BB7D4}}a:hover{{color:#FFFFFF}}
</style>
</helmet>
<div style="width: 1640px; height: 900px; box-sizing: border-box; padding: 36px 40px; background: #0B0E12; color: #FFFFFF; font-family: {TXT}; display: flex; flex-direction: column; gap: 22px; font-size: 13px; line-height: 1.5">
  <div style="display: flex; justify-content: space-between; align-items: flex-end; gap: 24px">
    <div style="display: flex; flex-direction: column; gap: 4px"><div style="font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: #9AA4B1; font-weight: 600">Telling web users the app exists</div><div style="font-size: 20px; font-weight: 700">Say it once, say it where it's true, and show the thing the web can't do</div></div>
    <div style="font-size: 12.5px; color: #9AA4B1; max-width: 640px; text-align: right">Recommended set: <b style="color: #FFFFFF">1 + 2 + 3 + 5</b>, with 4 gated to non-Safari iOS. The pitch is always the same three facts — complication, now readout, saved spots — never "download our app". The web keeps working exactly as before; nothing is added above the chart on desktop.</div>
  </div>
  <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; flex: 1">{''.join(tiles)}</div>
  <div style="display: flex; gap: 28px; font-size: 12px; color: #9AA4B1; padding: 12px 16px; border-radius: 10px; background: #171C23">
    <span><b style="color: #FFFFFF">Measure:</b> taps on the header link, the footer card and the outing card as three events; the Smart Banner is Apple's and reports nothing. Expect most installs from 5.</span>
    <span><b style="color: #FFFFFF">Decide:</b> (a) QR on desktop, or is a URL enough? (b) 30 days for the strip dismissal, or forever? (c) does the outing card go to the organiser too?</span>
  </div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1640,"height":900}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>'''

if __name__ == '__main__':
    open(P+'App-Options.dc.html','w').write(options_board())
    open(P+'Web-Phone-App-Safari.dc.html','w').write(build_phone('safari'))
    open(P+'Web-Phone-App-Other.dc.html','w').write(build_phone('other'))
    open(P+'Web-Desktop-App.dc.html','w').write(build_desktop())
    print('ok')
