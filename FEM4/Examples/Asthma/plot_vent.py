#!/usr/bin/env python3
"""Plots ventrun's files into out/vent.png:  python3 plot_vent.py [dir]

Left: airway opening pressure through the measured breath (with its
end-inspiratory and end-expiratory holds) at 12 and 24 /min, 500 mL.
Middle: trapped volume above FRC at end expiration and intrinsic PEEP
from the hold, against minute ventilation (PEEP 0). Right: plateau and
peak pressure against minute ventilation."""
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
lungs = [("normal", "#3182bd"), ("asthma", "#de2d26"), ("asthma_mucus", "#756bb1")]
fig, ax = plt.subplots(1, 3, figsize=(16, 4.8))
for name, col in lungs:
    fn = f"{d}/vent_{name}.csv"
    if not os.path.exists(fn):
        continue
    for si, ls in ((1, "-"), (4, "--")):
        w = f"{d}/vent_{name}_{si}.csv"
        if os.path.exists(w):
            t = np.genfromtxt(w, delimiter=",", names=True)
            m = t["t_s"] < 60 / (12 if si == 1 else 24) + 2.5
            ax[0].plot(t["t_s"][m], t["Paw_cmH2O"][m], color=col, ls=ls,
                       label=f"{name}, {12 if si == 1 else 24} /min")
    s = np.genfromtxt(fn, delimiter=",", names=True)
    z = (s["PEEP_cmH2O"] == 0) & (s["VT_L"] == 0.5)
    ax[1].plot(s["VE_Lpmin"][z], s["EEV_above_FRC_mL"][z], "o-", color=col, label=f"{name}: trapped volume")
    ax[1].plot(s["VE_Lpmin"][z], 100 * s["PEEPi_cmH2O"][z], "s--", color=col, label=f"{name}: PEEPi x 100")
    ax[2].plot(s["VE_Lpmin"][z], s["Pplat_cmH2O"][z], "o-", color=col, label=f"{name}: plateau")
    ax[2].plot(s["VE_Lpmin"][z], s["Ppeak_cmH2O"][z], "^:", color=col, label=f"{name}: peak")
ax[0].set_xlabel("time (s)"); ax[0].set_ylabel("airway opening pressure (cmH2O)")
ax[0].set_title("Measured breath: 0.5 s inspiratory and 2 s expiratory holds")
ax[1].set_xlabel("minute ventilation (L/min), 500 mL breaths"); ax[1].set_ylabel("mL  /  cmH2O x 100")
ax[1].set_title("End-expiratory gas above FRC, and intrinsic PEEP")
ax[2].set_xlabel("minute ventilation (L/min), 500 mL breaths"); ax[2].set_ylabel("cmH2O")
ax[2].set_title("Peak and plateau pressure")
for a in ax:
    a.grid(alpha=0.3); a.legend(frameon=False, fontsize=7)
fig.tight_layout()
fig.savefig(f"{d}/vent.png", dpi=100)
print(f"wrote {d}/vent.png")
