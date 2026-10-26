"""Illustrative sky conditions for the 45-h HRRR window, in 3-h blocks: (cloud %, rain mm/h)."""
SKY=[(10,0),(20,0),(45,0),(70,0),(90,0.4),(100,1.2),(100,2.0),(95,0.6),(80,0),(55,0),(30,0),(25,0),(60,0),(85,0.3),(70,0)]  # Wed 09 .. Fri 03 (+2h tail)
def band_svg(W,slot_h,h=14,uid='sky',start=0,n=45,label=True):
    """A sky band aligned to the chart x-scale: cloud tone per 3-h block, rain as blue ticks. rect+line marks only."""
    pxh=W/n; o=[f'<svg width="{W}" height="{h}" viewBox="0 0 {W} {h}" aria-hidden="true" style="display:block;overflow:visible">']
    for i,(cc,mm) in enumerate(SKY):
        t=i*3; 
        if t>=n: break
        w=min(3,n-t)*pxh; x=t*pxh
        if cc<25: fill='#FFB340'; op=0.22          # clear: a warm hint (sun colour already in the system)
        elif cc<70: fill='#9AA4B1'; op=0.28       # partly cloudy
        else: fill='#9AA4B1'; op=0.60             # overcast
        o.append(f'<rect x="{x+0.5:.1f}" y="2" width="{w-1:.1f}" height="{h-4}" rx="2" fill="{fill}" fill-opacity="{op}"/>')
        if mm>0:
            # rain: 1-3 ticks by intensity, blue, hanging from the band's bottom edge
            k=1 if mm<0.5 else (2 if mm<1.5 else 3)
            for j in range(k):
                cx=x+w*(j+1)/(k+1)
                o.append(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{h-6}" y2="{h-1}" stroke="#4FA3D8" stroke-width="2" stroke-linecap="round"/>')
    o.append('</svg>'); return '\n'.join(o)
def describe(i):
    cc,mm=SKY[i]
    sky='Clear' if cc<25 else ('Partly cloudy' if cc<70 else 'Overcast')
    rain='' if mm==0 else (' · light rain' if mm<0.5 else (' · rain' if mm<1.5 else ' · heavy rain'))
    return sky+rain
