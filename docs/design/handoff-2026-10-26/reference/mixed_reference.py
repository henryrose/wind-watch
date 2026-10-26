"""7-day mixed-model chart: HRRR hourly (real payload) + GFS 3-hourly (illustrative) beyond the HRRR horizon."""
import math, json, sys
sys.argv=['x','none']
exec(open('chart.py').read().split("if __name__=='__main__':")[0])   # kn, gust, dr, RAMP, bft, col
# --- illustrative GFS blocks, 3-hourly, from hour 45 (Fri 06:00) to hour 168 (Tue 09:00) ---
# (kn, gust, dirFrom) per 3h block; a SW front Saturday, NW clearing Sunday, light Monday, S Tuesday.
G=[(10,17,295),(11,18,290),(10,16,285),(9,15,280),(8,13,270),(7,12,250),(8,14,230),(10,17,220),   # Fri 06 -> Sat 06
   (12,20,215),(15,26,210),(18,32,205),(17,30,210),(14,25,220),(11,19,235),(9,16,260),(10,18,290),   # Sat 06 -> Sun 06
   (13,21,305),(14,22,310),(12,19,315),(9,15,320),(7,12,325),(5,9,330),(4,7,20),(3,6,60),           # Sun 06 -> Mon 06
   (4,7,90),(5,8,120),(6,10,160),(6,10,180),(5,9,190),(5,8,185),(6,10,180),(8,13,175),              # Mon 06 -> Tue 06
   (10,16,170)]                                                                                        # Tue 06 -> 09
HRRR_END=45  # hours; last hourly index 44
def blocks3(h0,h1):
    """aggregate hourly payload into 3h blocks: max kn, max gust, vector-mean dir"""
    out=[]
    for s in range(h0,h1,3):
        idx=[i for i in range(s,min(s+3,h1))]
        k=max(kn[i] for i in idx); g=max(gust[i] for i in idx)
        x=sum(math.cos(math.radians(dr[i])) for i in idx); y=sum(math.sin(math.radians(dr[i])) for i in idx)
        d=(math.degrees(math.atan2(y,x))+360)%360
        out.append(dict(t=s,w=len(idx),kn=k,gust=g,dir=d,model='HRRR'))
    return out
def slots(mode):
    """mode 'phone': everything 3-hourly. mode 'web': HRRR hourly + GFS 3-hourly."""
    if mode=='phone': s=blocks3(0,HRRR_END)
    else: s=[dict(t=i,w=1,kn=kn[i],gust=gust[i],dir=dr[i],model='HRRR') for i in range(HRRR_END)]
    t=HRRR_END
    for k,g,d in G:
        s.append(dict(t=t,w=3,kn=k,gust=g,dir=d,model='NBM')); t+=3
    return s
# sun events for 7 days (approx, PDT): day0 = Wed Oct 21
def sun_events():
    ev=[]
    for day in range(8):
        rise=7+(40+day)/60; sett=18+(12-2*day)/60
        base=day*24-9  # hour index of local midnight for that day (Wed 00:00 = -9)
        ev+= [('dawn',base+rise-32/60),('rise',base+rise),('set',base+sett),('dusk',base+sett+32/60)]
    return [(n,t) for n,t in ev if -1<t<170]
SUN7=sun_events()
DAYS7=[(15,'Thu'),(39,'Fri'),(63,'Sat'),(87,'Sun'),(111,'Mon'),(135,'Tue')]
def mixed_svg(mode,W,H,top,bot,uid,sel=None,font=11,arrow_every=6,arrow_size=9,now=0.4,total=168,day_alpha=0.07):
    S=slots(mode); plotW=W; plotH=H-top-bot; pxh=plotW/total
    ymax=max(20,math.ceil((max(s['gust'] for s in S)+3)/10)*10)
    X=lambda h: h*pxh; Y=lambda v: top+plotH-(v/ymax)*plotH
    o=[f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" aria-hidden="true" style="display:block;overflow:visible">']
    # day/night gradient
    stops=[(0.0,1.0)]
    for n,t in SUN7:
        if 0<t<total:
            stops.append((t/total,{'set':1.0,'dusk':0.0,'dawn':0.0,'rise':1.0}[n]))
    stops.append((1.0,stops[-1][1]))
    o.append(f'<defs><linearGradient id="g{uid}" x1="0" x2="1">'+''.join(f'<stop offset="{f:.4f}" stop-color="#FFFFFF" stop-opacity="{day_alpha*v:.3f}"/>' for f,v in stops)+'</linearGradient></defs>')
    o.append(f'<rect x="0" y="{top}" width="{plotW:.1f}" height="{plotH:.1f}" fill="url(#g{uid})"/>')
    # GFS region tint + label band
    gx=X(HRRR_END)
    o.append(f'<rect x="{gx:.1f}" y="{top}" width="{plotW-gx:.1f}" height="{plotH:.1f}" fill="#4FA3D8" fill-opacity="0.045"/>')
    for g in range(10,ymax,10):
        o.append(f'<line x1="0" x2="{W}" y1="{Y(g):.1f}" y2="{Y(g):.1f}" stroke="#FFFFFF" stroke-opacity="0.12"/>')
        o.append(f'<text x="{W-2}" y="{Y(g)-3:.1f}" text-anchor="end" font-size="{font-1}" fill="#FFFFFF" fill-opacity="0.45" font-family="-apple-system,system-ui,sans-serif">{g}</text>')
    for n,t in SUN7:
        if n in('rise','set') and 0<=t<=total:
            o.append(f'<circle cx="{X(t):.1f}" cy="{top-1}" r="3" fill="#FFB340"/>' if n=='rise' else f'<circle cx="{X(t):.1f}" cy="{top-1}" r="2.25" fill="none" stroke="#FFB340" stroke-width="1.5"/>')
    # bars
    for s in S:
        slot=s['w']*pxh; bw=max(3,slot*0.72); x=X(s['t'])+(slot-bw)/2
        op='' if sel is None or s['t']==sel else ' fill-opacity="0.45"'
        if sel is None and s['model']=='NBM': op=' fill-opacity="0.7"'
        elif sel is not None and s['t']!=sel and s['model']=='NBM': op=' fill-opacity="0.35"'
        o.append(f'<rect x="{x:.1f}" y="{Y(s["kn"]):.1f}" width="{bw:.1f}" height="{top+plotH-Y(s["kn"]):.1f}" rx="1.5" fill="{col(s["kn"])}"{op}/>')
    HH=[q for q in S if q['model']=='HRRR']; NN=[q for q in S if q['model']=='NBM']
    ptsH=' '.join(f'{X(q["t"])+q["w"]*pxh/2:.1f},{Y(q["gust"]):.1f}' for q in HH)
    ptsN=' '.join(f'{X(q["t"])+q["w"]*pxh/2:.1f},{Y(q["gust"]):.1f}' for q in NN)
    o.append(f'<polyline points="{ptsH}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="1.5" stroke-linejoin="round"/>')
    o.append(f'<polyline points="{ptsN}" fill="none" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="1.5" stroke-linejoin="round" stroke-dasharray="4 3"/>')
    for s in S:
        slot=s['w']*pxh; bw=max(3,slot*0.72); cx=X(s['t'])+slot/2; cap=bw+2
        o.append(f'<line x1="{cx-cap/2:.1f}" x2="{cx+cap/2:.1f}" y1="{Y(s["gust"]):.1f}" y2="{Y(s["gust"]):.1f}" stroke="#FFFFFF" stroke-width="1.5" stroke-linecap="round"/>')
    # arrows
    for s in S:
        if s['t']%arrow_every: continue
        cx=X(s['t'])+s['w']*pxh/2; cy=top+plotH+bot/2-5; rot=(s['dir']+180)%360; a=arrow_size
        o.append(f'<g transform="translate({cx:.1f},{cy:.1f}) rotate({rot:.0f})"><path d="M0,{-a/2:.1f} L{a*.38:.1f},{a/2:.1f} L0,{a*.2:.1f} L{-a*.38:.1f},{a/2:.1f} Z" fill="#FFFFFF" fill-opacity="0.9"/></g>')
    # day dividers + names at bottom centre of each day
    for h,name in DAYS7:
        x=X(h)
        o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top-18}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="1" stroke-dasharray="2 3"/>')
    for i,(h,name) in enumerate([(-9,'Wed')]+DAYS7):
        cx=X(max(h,0)+ (24 if h>=0 else 15)/2 )
        if h>=0: cx=X(h+12)
        else: cx=X(7.5)
        if cx<W-10: o.append(f'<text x="{cx:.1f}" y="{H+10}" text-anchor="middle" font-size="{font}" font-weight="600" fill="#FFFFFF" fill-opacity="0.6" font-family="-apple-system,system-ui,sans-serif">{name}</text>')
    # seam
    o.append(f'<line x1="{gx:.1f}" x2="{gx:.1f}" y1="{top-6}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="1" stroke-dasharray="3 3"/>')
    o.append(f'<text x="{gx-4:.1f}" y="{top-8}" text-anchor="end" font-size="{font}" font-weight="600" fill="#FFFFFF" fill-opacity="0.7" font-family="-apple-system,system-ui,sans-serif">HRRR</text>')
    o.append(f'<text x="{gx+4:.1f}" y="{top-8}" font-size="{font}" font-weight="600" fill="#9BB7D4" font-family="-apple-system,system-ui,sans-serif">NBM · 3-hourly</text>')
    # now
    x=X(now); o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top-6}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-width="1.5"/>')
    o.append(f'<text x="{x+4:.1f}" y="{top-8}" font-size="{font}" font-weight="600" fill="#FFFFFF" font-family="-apple-system,system-ui,sans-serif">now</text>')
    # end
    x=X(total); o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top-6}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="1" stroke-dasharray="3 3"/>')
    o.append(f'<text x="{x-4:.1f}" y="{top-8}" text-anchor="end" font-size="{font}" font-weight="600" fill="#FFFFFF" fill-opacity="0.7" font-family="-apple-system,system-ui,sans-serif">ends Tue 9am</text>')
    if sel is not None:
        s=[q for q in S if q['t']==sel][0]; slot=s['w']*pxh; bw=max(3,slot*0.72); cx=X(sel)+slot/2
        o.append(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{top-6}" y2="{top+plotH+bot:.1f}" stroke="#FFFFFF" stroke-width="1.5"/>')
        o.append(f'<rect x="{X(sel)+(slot-bw)/2-1.5:.1f}" y="{Y(s["kn"])-1.5:.1f}" width="{bw+3:.1f}" height="{top+plotH-Y(s["kn"])+1.5:.1f}" rx="2.5" fill="none" stroke="#FFFFFF" stroke-width="1.5"/>')
    o.append('</svg>'); return '\n'.join(o)
if __name__=='__main__':
    open('p7.svg','w').write(mixed_svg('phone',402,262,38,18,'p7'))
    open('p7sel.svg','w').write(mixed_svg('phone',402,262,38,18,'p7s',sel=75))   # Sat 12:00-15:00 block (hour 75)
    open('w7.svg','w').write(mixed_svg('web',1120,300,40,22,'w7',arrow_every=3,arrow_size=10,font=12))
    S=slots('phone'); print([ (s['t'],s['kn'],s['gust'],round(s['dir'])) for s in S if 69<=s['t']<=81])
    print('ymax', max(s['gust'] for s in S))
