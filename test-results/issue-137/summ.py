import re,sys,statistics
def load(f):
    d={}
    for l in open(f):
        kv=dict(re.findall(r'(\w+)=([-\d.\w]+)',l))
        s=d.setdefault(kv['stage'],{'falls':0,'haz':0,'min':0.0,'rounds':0,'med':[]})
        s['falls']+=int(kv['prelava_falls']); s['haz']+=int(kv['prelava_hazard']); s['min']+=float(kv['bot_min']); s['rounds']+=int(kv['rounds']); s['med'].append(float(kv['median_first_elim_s']))
    return d
b=load(sys.argv[1]); a=load(sys.argv[2])
order="Flatlands Pillars Ferry Highrise Erosion Islands Furnace Gauntlet Cascade Slant Bowl Springboard Gale Carousel Rockfall Sinkhole Bulwark".split()
print("| Stage | falls/bot-min before | after | change | hazard deaths/bot-min before | after | median s to first elim before | after | rounds before | after |")
print("|---|---|---|---|---|---|---|---|---|---|")
tb=[0,0];ta=[0,0]
for st in order:
    x=b[st];y=a[st]
    rb=x['falls']/x['min']; ra=y['falls']/y['min']
    tb[0]+=x['falls'];tb[1]+=x['min'];ta[0]+=y['falls'];ta[1]+=y['min']
    print(f"| {st} | {rb:.2f} | {ra:.2f} | {(f'{100*(ra-rb)/rb:+.0f}%' if rb else 'n/a')} | {x['haz']/x['min']:.2f} | {y['haz']/y['min']:.2f} | {statistics.median(x['med']):.1f} | {statistics.median(y['med']):.1f} | {x['rounds']} | {y['rounds']} |")
print(f"| **All** | {tb[0]/tb[1]:.2f} | {ta[0]/ta[1]:.2f} | {100*((ta[0]/ta[1])-(tb[0]/tb[1]))/(tb[0]/tb[1]):+.0f}% | | | | | | |")
