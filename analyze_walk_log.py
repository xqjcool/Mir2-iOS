"""Usage: python3 analyze_walk_log.py walk-test-....csv; standard library only."""
import csv,json,statistics,sys
from pathlib import Path

def analyze(path):
    text=Path(path).read_text(encoding='utf-8')
    rows=list(csv.DictReader(line for line in text.splitlines() if not line.startswith('#')))
    if not rows:raise ValueError('No samples in log')
    memories=[float(r['footprint_mb']) for r in rows if r['footprint_mb']!='NA']
    late=[float(r['footprint_mb']) for r in rows if float(r['time_s'])>=1200 and r['footprint_mb']!='NA']
    warm=[float(r['footprint_mb']) for r in rows if 300<=float(r['time_s'])<=600 and r['footprint_mb']!='NA']
    last=rows[-1]
    return {'file':str(path),'samples':len(rows),'activeSeconds':float(last['time_s']),
        'completed30Minutes':'# stopped=completed' in text,
        'peakPhysicalMB':max(float(r['peak_mb']) for r in rows),
        'warmMedianPhysicalMB':statistics.median(warm) if warm else None,
        'lateMedianPhysicalMB':statistics.median(late) if late else None,
        'minSampledFPS':min(float(r['fps']) for r in rows if float(r['time_s'])>5) if len(rows)>2 else None,
        'maxTextureMB':max(float(r['texture_mb']) for r in rows),'memoryWarnings':int(last['memory_warnings']),
        'loads':int(last['loads']),'unloads':int(last['unloads']),'failures':int(last['failures']),
        'budgetHits':int(last['budget_hits']),'steps':int(last['steps']),
        'seriousOrCriticalThermalSamples':sum(int(r['thermal'])>=2 for r in rows),
        'note':'Different positions have different working sets. Compare repeated locations/cycles before diagnosing a leak; no automatic pass verdict.'}

if __name__=='__main__':print(json.dumps(analyze(sys.argv[1]),ensure_ascii=False,indent=2))
