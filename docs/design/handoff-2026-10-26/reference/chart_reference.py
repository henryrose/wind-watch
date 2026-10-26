import math,sys
kn=[3,4,2,3,4,3,3,4,4,4,5,8,9,11,13,15,14,14,12,12,11,10,9,8,7,7,6,9,8,6,8,7,8,7,9,11,10,11,10,10,9,9,10,11,11]
gust=[4,5,3,3,4,2,4,5,6,9,13,15,18,19,24,25,24,24,22,21,18,15,14,12,12,12,11,16,16,15,15,14,16,13,15,22,19,20,20,20,18,18,20,21,21]
dr=[290,289,313,51,74,66,11,339,325,323,301,295,287,284,282,283,286,288,288,290,292,298,297,307,318,331,346,344,341,329,328,311,307,301,283,292,294,296,294,289,289,289,292,293,296]
RAMP={0:'#5C6B7A',1:'#5C6B7A',2:'#4FA3D8',3:'#3FC2A0',4:'#8DD44A',5:'#F2D13D',6:'#F59A2B',7:'#EC5A2A',8:'#E0245E',9:'#A32CD1',10:'#F5F5F7'}
def bft(k):
    for b,hi in [(0,0.5),(1,3.5),(2,6.5),(3,10.5),(4,16.5),(5,21.5),(6,27.5),(7,33.5),(8,40.5),(9,47.5),(10,55.5)]:
        if k<hi: return b
    return 11
def col(k): return RAMP[min(bft(k),10)]
# sun events in hour-index space (idx0 = Oct21 09:00)
SUN=[('set',9.2),('dusk',9.733),('dawn',22.133),('rise',22.667),('set',33.167),('dusk',33.7)]
def svg(start,n,W,H,ymax=30,top=14,bot=14,left=0,arrows='all',ticks=3,now=None,labels=None,end_label=None,gw=1.5,font=11,arrow_size=9,show_grid=True,night_alpha=0.0,day_alpha=0.07,sun_r=3,uid='c',sel=None,days=None,sunstyle='rise-set'):
    hours=list(range(start,min(start+n,len(kn))))
    plotW=W-left; plotH=H-top-bot
    slot=plotW/n; bw=round(slot*0.72,2)
    def X(i): return left+(i-start)*slot
    def Y(v): return top+plotH-(v/ymax)*plotH
    o=[]
    o.append(f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="Hourly wind chart" style="display:block;overflow:visible">')
    # day/night gradient along x
    stops=[]
    def frac(h): return max(0,min(1,(h-start)/n))
    # build stops: start state
    def state_at(h):
        # day if between rise and set
        d=True
        for name,t in SUN:
            if t<=h:
                d = name in ('rise',)  if name in('rise','set') else d
        # simpler: compute via sequence
        return d
    # explicit sequence
    seq=[(start,1.0)]
    cur=1.0
    pts=[]
    for name,t in SUN:
        if name=='set': pts.append((t,1.0));
        if name=='dusk': pts.append((t,0.0))
        if name=='dawn': pts.append((t,0.0))
        if name=='rise': pts.append((t,1.0))
    # determine initial
    init=1.0
    for name,t in SUN:
        if t<start: init = 1.0 if name in('rise','set') and name=='rise' else (0.0 if name=='dusk' else init)
    # correct init: find last event before start
    last=None
    for name,t in SUN:
        if t<=start: last=name
    init={'set':1.0,'dusk':0.0,'dawn':0.0,'rise':1.0,None:1.0}[last]
    stops=[(0.0,init)]
    for t,v in pts:
        if start<t<start+n: stops.append((frac(t),v))
    stops.append((1.0,stops[-1][1]))
    o.append(f'<defs><linearGradient id="dn{uid}" x1="0" x2="1" y1="0" y2="0">')
    for f,v in stops:
        a=night_alpha+(day_alpha-night_alpha)*v
        o.append(f'<stop offset="{f:.4f}" stop-color="#FFFFFF" stop-opacity="{a:.3f}"/>')
    o.append('</linearGradient></defs>')
    o.append(f'<rect x="{left}" y="{top}" width="{plotW:.1f}" height="{plotH:.1f}" fill="url(#dn{uid})"/>')
    if show_grid:
        for g in range(10,ymax,10):
            o.append(f'<line x1="{left}" x2="{W}" y1="{Y(g):.1f}" y2="{Y(g):.1f}" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="1"/>')
            o.append(f'<text x="{W-2}" y="{Y(g)-3:.1f}" text-anchor="end" font-size="{font-1}" fill="#FFFFFF" fill-opacity="0.45" font-family="-apple-system,system-ui,sans-serif">{g}</text>')
    # sun markers
    for name,t in SUN:
        if name in('rise','set') and start<=t<=start+n:
            if sunstyle=='rise-set' and name=='set':
                o.append(f'<circle cx="{X(t):.1f}" cy="{top-1}" r="{sun_r-0.75}" fill="none" stroke="#FFB340" stroke-width="1.5"/>')
            elif sunstyle=='half':
                # half-disc on the horizon line: rise = upper half, set = lower half
                r=sun_r+1; x=X(t); y=top-1
                d=f'M{x-r:.1f},{y} a{r},{r} 0 0 1 {2*r},0 z' if name=='rise' else f'M{x-r:.1f},{y} a{r},{r} 0 0 0 {2*r},0 z'
                o.append(f'<path d="{d}" fill="#FFB340"/><line x1="{x-r-1:.1f}" x2="{x+r+1:.1f}" y1="{y}" y2="{y}" stroke="#FFB340" stroke-width="1"/>')
            elif sunstyle=='tick':
                x=X(t); y=top-1; o.append(f'<circle cx="{x:.1f}" cy="{y}" r="{sun_r}" fill="#FFB340"/>')
                o.append(f'<path d="M{x-2.5:.1f},{y-6} l2.5,-3 l2.5,3" fill="none" stroke="#FFB340" stroke-width="1.2" stroke-linecap="round"/>' if name=='rise' else f'<path d="M{x-2.5:.1f},{y-9} l2.5,3 l2.5,-3" fill="none" stroke="#FFB340" stroke-width="1.2" stroke-linecap="round"/>')
            else:
                o.append(f'<circle cx="{X(t):.1f}" cy="{top-1}" r="{sun_r}" fill="#FFB340"/>')
    # bars
    for i in hours:
        k=kn[i]
        op='' if sel is None or i==sel else ' fill-opacity="0.45"'
        o.append(f'<rect x="{X(i)+(slot-bw)/2:.1f}" y="{Y(k):.1f}" width="{bw}" height="{(top+plotH-Y(k)):.1f}" rx="1.5" fill="{col(k)}"{op}/>')
    if sel is not None:
        cx=X(sel)+slot/2
        o.append(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{top-6}" y2="{top+plotH+bot:.1f}" stroke="#FFFFFF" stroke-width="1.5"/>')
        o.append(f'<rect x="{X(sel)+(slot-bw)/2-1.5:.1f}" y="{Y(kn[sel])-1.5:.1f}" width="{bw+3:.1f}" height="{(top+plotH-Y(kn[sel]))+1.5:.1f}" rx="2.5" fill="none" stroke="#FFFFFF" stroke-width="1.5"/>')
    # gust line
    pts2=' '.join(f'{X(i)+slot/2:.1f},{Y(gust[i]):.1f}' for i in hours)
    o.append(f'<polyline points="{pts2}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="{gw}" stroke-linejoin="round"/>')
    cap=bw+2
    for i in hours:
        cx=X(i)+slot/2
        o.append(f'<line x1="{cx-cap/2:.1f}" x2="{cx+cap/2:.1f}" y1="{Y(gust[i]):.1f}" y2="{Y(gust[i]):.1f}" stroke="#FFFFFF" stroke-width="{gw}" stroke-linecap="round"/>')
    # arrows (TO direction = from+180)
    step=1 if arrows=='all' else arrows
    for i in hours:
        if step==0 or (i-start)%step: continue
        cx=X(i)+slot/2; cy=top+plotH+bot/2
        rot=(dr[i]+180)%360
        s=arrow_size
        o.append(f'<g transform="translate({cx:.1f},{cy:.1f}) rotate({rot})"><path d="M0,{-s/2:.2f} L{s*0.38:.2f},{s/2:.2f} L0,{s*0.2:.2f} L{-s*0.38:.2f},{s/2:.2f} Z" fill="#FFFFFF" fill-opacity="0.9"/></g>')
    # ticks
    for i in hours:
        if ticks and (i%ticks)==0:
            x=X(i)+slot/2
            o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top+plotH:.1f}" y2="{top+plotH+3:.1f}" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="1"/>')
    if labels:
        for i,txt in labels:
            if start<=i<=start+n:
                o.append(f'<text x="{X(i)+slot/2:.1f}" y="{H+10}" text-anchor="middle" font-size="{font}" fill="#FFFFFF" fill-opacity="0.6" font-family="-apple-system,system-ui,sans-serif">{txt}</text>')
    if days:
        for i,name in days:
            if i==start and now is not None: continue
            if start<=i<=start+n:
                x=X(i)
                if i>start:
                    o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top-18}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="1" stroke-dasharray="2 3"/>')
                dx = 5 if i>start else 4
                o.append(f'<text x="{x+dx:.1f}" y="{top-22}" font-size="{font}" font-weight="700" fill="#FFFFFF" fill-opacity="0.75" font-family="-apple-system,system-ui,sans-serif">{name}</text>')
    if now is not None:
        x=X(now)
        o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top-6}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-width="1.5"/>')
        o.append(f'<text x="{x+4:.1f}" y="{top-8}" font-size="{font}" font-weight="600" fill="#FFFFFF" font-family="-apple-system,system-ui,sans-serif">now</text>')
    if end_label:
        x=X(start+len(hours))
        o.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top-6}" y2="{top+plotH:.1f}" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="1" stroke-dasharray="3 3"/>')
        o.append(f'<text x="{x-4:.1f}" y="{top-8}" text-anchor="end" font-size="{font}" font-weight="600" fill="#FFFFFF" fill-opacity="0.7" font-family="-apple-system,system-ui,sans-serif">{end_label}</text>')
    o.append('</svg>')
    return '\n'.join(o)
if __name__=='__main__':
    which=sys.argv[1]
    L12=[(6,'3pm'),(12,'9pm'),(18,'3am'),(24,'9am'),(30,'3pm'),(36,'9pm'),(42,'3am')]
    L12b=[(0,'9am'),(3,'noon'),(6,'3pm'),(9,'6pm'),(12,'9pm'),(15,'12am'),(18,'3am'),(21,'6am'),(24,'9am'),(27,'noon'),(30,'3pm'),(33,'6pm'),(36,'9pm'),(39,'12am'),(42,'3am')]
    DAYS=[(0,'Wed'),(15,'Thu'),(39,'Fri')]
    L6=[(0,'09'),(6,'15'),(12,'21'),(15,'Thu'),(18,'03'),(24,'09'),(30,'15'),(36,'21'),(39,'Fri'),(42,'03')]
    if which=='phonebig': print(svg(0,45,402,262,top=38,bot=18,arrows=3,ticks=6,now=0.4,labels=L12,end_label='ends Fri 5am',uid='pb',days=DAYS))
    if which=='phonesel': print(svg(0,45,402,262,top=38,bot=18,arrows=3,ticks=6,now=0.4,labels=L12,end_label='ends Fri 5am',uid='ps',sel=15,days=DAYS))
    if which=='land': print(svg(0,45,834,296,top=38,bot=22,arrows=1,ticks=3,now=0.4,labels=L12b,end_label='ends Fri 5am',uid='ld',sel=15,days=DAYS,font=12,arrow_size=9))
    if which=='webhover': print(svg(0,45,1120,300,top=40,bot=22,arrows=1,ticks=3,now=0.4,labels=L12b,end_label='ends Fri 5am',font=12,arrow_size=10,uid='dh',sel=15,days=DAYS))
    if which=='phone': print(svg(0,45,370,190,top=22,bot=16,arrows=3,ticks=6,now=0.4,labels=[(i,t) for i,t in L6 if t not in('Thu','Fri')],end_label='HRRR ends 05:00',uid='p'))
    if which=='watchstrip': print(svg(0,12,396,230,top=24,bot=22,arrows='all',ticks=3,now=0.4,labels=[(3,'12'),(6,'15'),(9,'18')],font=22,arrow_size=14,gw=2.5,sun_r=5,uid='w'))
    if which=='watchshort': print(svg(39,12,396,230,top=24,bot=22,arrows='all',ticks=3,now=39.1,labels=[(39,'00'),(42,'03')],font=22,arrow_size=14,gw=2.5,sun_r=5,end_label='ends 05:00',uid='s'))
    if which=='mini': print(svg(15,6,150,62,ymax=30,top=10,bot=2,arrows=0,ticks=0,show_grid=False,gw=2,sun_r=3,uid='m'))
    if which=='minishort': print(svg(41,4,150,62,ymax=25,top=10,bot=2,arrows=0,ticks=0,show_grid=False,gw=2,sun_r=3,end_label='',uid='q'))
    if which=='web': print(svg(0,45,1120,280,top=28,bot=22,arrows=1,ticks=3,now=0.4,labels=L6,end_label='HRRR ends 05:00 Fri',font=12,arrow_size=10,uid='d'))
    if which=='webphone': print(svg(0,45,358,200,top=22,bot=16,arrows=3,ticks=6,now=0.4,labels=[(i,t) for i,t in L6 if t not in('Thu','Fri')],end_label='HRRR ends 05:00',uid='e'))
    if which=='table':
        for i in range(45):
            h=(9+i)%24; d=['Wed','Thu','Fri'][(9+i)//24]
            print(i,f'{h:02d}:00',d,kn[i],gust[i],dr[i],(dr[i]+180)%360,bft(kn[i]),col(kn[i]))
