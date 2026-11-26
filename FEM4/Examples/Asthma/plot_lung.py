#!/usr/bin/env python3
"""Plots lungrun's CSV files into out/lung.png:  python3 plot_lung.py [dir] [TLC]

Left: maximal expiratory flow-volume curves with the tidal loops (rest
and fast) drawn at their place in the vital capacity. Middle and right:
the fast-breathing cycle's alveolar and pleural pressures."""
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
TLC = float(sys.argv[2]) if len(sys.argv) > 2 else 6.5
cases = [("normal", "#1f77b4"), ("mild", "#2ca02c"), ("moderate", "#ff7f0e"),
         ("severe", "#d62728"), ("custom", "#9467bd")]

fig, ax = plt.subplots(1, 3, figsize=(16, 4.8))
for name, col in cases:
    fv = f"{d}/lung_{name}_fv.csv"
    if not os.path.exists(fv):
        continue
    f = np.genfromtxt(fv, delimiter=",", names=True)
    ax[0].plot(f["volume_exhaled_L"], f["flow_Lps"], color=col, label=name)
    for pat, ls in (("rest", "-"), ("fast", "--")):
        fn = f"{d}/lung_{name}_{pat}.csv"
        if not os.path.exists(fn):
            continue
        t = np.genfromtxt(fn, delimiter=",", names=True)
        ax[0].plot(TLC - t["V_L"], t["flow_Lps"], color=col, ls=ls, lw=1)
        if pat == "fast":
            ax[1].plot(t["t_s"], t["Palv_cmH2O"], color=col, label=name)
            ax[2].plot(t["t_s"], t["Ppl_cmH2O"], color=col, label=name)
ax[0].axhline(0, color="k", lw=0.5)
ax[0].set_xlabel("volume exhaled from TLC (L)")
ax[0].set_ylabel("expiratory flow (L/s)")
ax[0].set_title("Forced expiration, with tidal loops (rest solid, fast dashed)")
ax[0].legend(frameon=False)
ax[1].set_xlabel("time in the breath (s)")
ax[1].set_ylabel("alveolar pressure (cmH2O)")
ax[1].set_title("Fast breathing, 30 /min, 600 mL")
ax[2].set_xlabel("time in the breath (s)")
ax[2].set_ylabel("pleural pressure (cmH2O)")
ax[2].set_title("Fast breathing: pleural pressure")
for a in ax:
    a.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(f"{d}/lung.png", dpi=110)
print(f"wrote {d}/lung.png")
