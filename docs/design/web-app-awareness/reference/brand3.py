"""Icon B·3 'Wake' — single source for every size. icon(size, round_, mono, label)"""
INK='#0B0E12'; B2,B3,B4='#4FA3D8','#3FC2A0','#8DD44A'
GREY=['#7A818B','#A0A7B1','#C6CBD2']
_n=[0]
def _id(): _n[0]+=1; return f'wk{_n[0]}'
def tier(size): return 'full' if size>=48 else ('small' if size>=24 else 'tiny')
def glyph(t,mono=False,arrow='#FFFFFF'):
    c=GREY if mono else [B2,B3,B4]
    if t=='full':
        cx,cy,s,sw=115.2,101.8,46,11; st=[(-22,58,80,c[0]),(0,58,92,c[1]),(22,58,84,c[2])]
    elif t=='small':
        cx,cy,s,sw=116.8,102.2,50,18; st=[(-16,62,86,c[0]),(16,62,92,c[2])]
    else:
        cx,cy,s,sw=117,103.1,54,26; st=[(0,66,96,c[1])]
    lines=''.join(f'<line x1="{x}" x2="{x}" y1="{a}" y2="{b}" stroke="{col}" stroke-width="{sw}" stroke-linecap="round"/>' for x,a,b,col in st)
    return f'<g transform="translate({cx},{cy}) rotate(103)">{lines}<path d="M0,{-s} L{s*.75:.1f},{s} L0,{s*.4:.1f} L{-s*.75:.1f},{s} Z" fill="{arrow}"/></g>'
def icon(size,round_=False,mono=False,label=None,t=None,ground=INK):
    i=_id(); t=t or tier(size)
    shape='<circle cx="90" cy="90" r="90"/>' if round_ else '<rect width="180" height="180" rx="40"/>'
    a=f'role="img" aria-label="{label}"' if label else 'aria-hidden="true"'
    return f'<svg width="{size}" height="{size}" viewBox="0 0 180 180" {a}><defs><clipPath id="{i}">{shape}</clipPath></defs><g clip-path="url(#{i})"><rect width="180" height="180" fill="{ground}"/></g>{glyph(t,mono)}</svg>'
