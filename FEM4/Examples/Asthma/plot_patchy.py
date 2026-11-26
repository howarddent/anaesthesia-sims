#!/usr/bin/env python3
"""Plots patchyrun's unit files into out/patchy.png:  python3 plot_patchy.py [dir]

Top row: each case's units in the frontal section, coloured by severity.
Bottom row: the same units coloured by specific ventilation in fast
breathing (tidal volume over end-expiratory volume, as a fraction of the
lung's mean); black are units shut all breath."""
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
cases = [c for c in ("normal", "moderate_p05", "moderate_p10", "severe_p05")
         if os.path.exists(f"{d}/patchy_{c}_units.csv")]
fig, ax = plt.subplots(2, len(cases), figsize=(4 * len(cases), 7), squeeze=False)
for k, c in enumerate(cases):
    u = np.genfromtxt(f"{d}/patchy_{c}_units.csv", delimiter=",", names=True)
    x, y = u["x_cm"], u["y_cm"]
    w = 30 / 16; h = 24 / 16
    sv = u["SV_fast"]
    vee = u["V_EE_fast_mL"]
    rel = sv / (np.sum(sv * vee) / np.sum(vee))
    for row, val, cmap, lo, hi, lab in ((0, u["severity"], "magma_r", 0, 3, "severity"),
                                        (1, rel, "viridis", 0, 2, "specific ventilation / mean")):
        a = ax[row][k]
        im = a.scatter(x, y, c=val, cmap=cmap, vmin=lo, vmax=hi, marker="s", s=230, linewidths=0)
        if row == 1:
            shut = sv < 1e-6
            a.scatter(x[shut], y[shut], c="k", marker="s", s=230, linewidths=0)
        a.set_xlim(0, 30); a.set_ylim(24, 0); a.set_aspect("equal")
        a.set_xticks([]); a.set_yticks([])
        if row == 0:
            a.set_title(c)
        if k == len(cases) - 1:
            fig.colorbar(im, ax=a, fraction=0.04, label=lab)
ax[0][0].set_ylabel("severity (top of chest at top)")
ax[1][0].set_ylabel("ventilation, 30 /min (black: shut)")
fig.tight_layout()
fig.savefig(f"{d}/patchy.png", dpi=100)
print(f"wrote {d}/patchy.png")
