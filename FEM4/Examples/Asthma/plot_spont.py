#!/usr/bin/env python3
"""Plots spontrun's out/spont.csv into out/spont.png:  python3 plot_spont.py [dir]

Per case: work of breathing and peak muscle pressure; the pleural
pressure swing and intrinsic PEEP; end-expiratory volume above FRC,
split into the part CPAP sets (the relaxed volume at that CPAP) and the
dynamic hyperinflation on top; PaO2 and the shunt."""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
t = np.genfromtxt(f"{d}/spont.csv", delimiter=",", names=True, dtype=None, encoding=None)
lab = {"normal": "normal\n(air)", "asthma_air": "asthma\n(air)", "asthma": "asthma", "salbutamol": "salb.",
       "heliox": "heliox", "cpap5": "CPAP 5", "cpap10": "CPAP 10", "salbutamol_heliox": "salb.+\nheliox",
       "salbutamol_cpap5": "salb.+\nCPAP 5"}
x = np.arange(len(t))
names = [lab.get(n, n) for n in t["run"]]
fig, ax = plt.subplots(2, 2, figsize=(14, 8.5))
a = ax[0][0]
a.bar(x - 0.2, t["work_J_per_min"], 0.4, color="#de2d26", label="work (J/min)")
a.bar(x + 0.2, t["Pmus_peak_cmH2O"], 0.4, color="#fd8d3c", label="peak muscle pressure (cmH2O)")
a.set_title("Work of breathing, VT 500 mL at 25 /min")
a = ax[0][1]
a.bar(x - 0.2, t["Ppl_swing_cmH2O"], 0.4, color="#3182bd", label="pleural swing (cmH2O)")
a.bar(x + 0.2, t["PEEPi_cmH2O"], 0.4, color="#9ecae1", label="intrinsic PEEP (cmH2O)")
a.set_title("Pleural swing (pulsus paradoxus) and threshold load")
a = ax[1][0]
applied = t["EELV_above_FRC_mL"] - t["EELV_above_relaxed_at_CPAP_mL"]
a.bar(x, applied, 0.6, color="#bdbdbd", label="set by CPAP (relaxed volume)")
a.bar(x, t["EELV_above_relaxed_at_CPAP_mL"], 0.6, bottom=applied, color="#756bb1", label="dynamic hyperinflation")
a.set_title("End-expiratory volume above FRC (mL)")
a = ax[1][1]
a.bar(x - 0.2, t["PaO2_mmHg"], 0.4, color="#31a354", label="PaO2 (mmHg)")
a.bar(x + 0.2, 5 * t["shunt_pct"], 0.4, color="#a1d99b", label="shunt (% of cardiac output, x 5)")
a.set_title("Oxygenation (FiO2 0.3 except on air)")
for a in ax.flat:
    a.set_xticks(x, names, fontsize=8)
    a.legend(frameon=False, fontsize=8)
    a.grid(alpha=0.3, axis="y")
fig.tight_layout()
fig.savefig(f"{d}/spont.png", dpi=100)
print(f"wrote {d}/spont.png")
