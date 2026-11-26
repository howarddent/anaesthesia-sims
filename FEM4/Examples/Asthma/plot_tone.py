#!/usr/bin/env python3
"""Plots tonerun's files into out/tone.png:  python3 plot_tone.py [dir]

Top: breath by breath, end-expiratory volume above FRC, ventilation
defects (% of lung volume) and mean activation, for each run.
Bottom: each unit's activation at the end, for the severe wall: no
feedback (gradual challenge to 0.9), feedback after a gradual challenge,
a sudden dose of 0.9, and the sudden dose with deep breaths."""
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
runs = [("moderate_off", "#9ecae1", "-"), ("moderate_on", "#3182bd", "-"),
        ("severe_off", "#fc9272", "-"), ("severe_on", "#de2d26", "-"),
        ("severe_off_sudden", "#fdae6b", "--"), ("severe_on_sudden", "#e6550d", "--"),
        ("severe_on_sudden_sigh", "#31a354", "--")]
maps = [("severe_off", "no feedback, gradual"), ("severe_on", "feedback, gradual"),
        ("severe_on_sudden", "feedback, sudden"), ("severe_on_sudden_sigh", "feedback, sudden, deep breaths")]
fig = plt.figure(figsize=(16, 8))
cols = [("EELV_above_FRC_mL", "EELV above FRC (mL)"), ("defect_vol_pct", "ventilation defects (% of lung)"),
        ("act_mean", "mean activation")]
for k, (c, lab) in enumerate(cols):
    a = fig.add_subplot(2, 3, k + 1)
    for name, col, ls in runs:
        fn = f"{d}/tone_{name}.csv"
        if not os.path.exists(fn):
            continue
        t = np.genfromtxt(fn, delimiter=",", names=True)
        a.plot(t["breath"], t[c], color=col, ls=ls, label=name.replace("_", " "))
    a.set_xlabel("breath (30 /min)")
    a.set_ylabel(lab)
    a.grid(alpha=0.3)
    if k == 0:
        a.legend(frameon=False, fontsize=8)
for k, (name, title) in enumerate(maps):
    fn = f"{d}/tone_{name}_units.csv"
    if not os.path.exists(fn):
        continue
    u = np.genfromtxt(fn, delimiter=",", names=True)
    last = u["dose"] == u["dose"][-1]
    last &= np.arange(len(u)) >= len(u) - 256
    u = u[last]
    a = fig.add_subplot(2, 4, 5 + k)
    im = a.scatter(u["x_cm"], u["y_cm"], c=u["act"], cmap="magma_r", vmin=0, vmax=0.9, marker="s", s=150,
                   linewidths=0)
    shut = u["strain"] < 1e-6
    a.scatter(u["x_cm"][shut], u["y_cm"][shut], marker="x", c="w", s=20, linewidths=1)
    a.set_xlim(0, 30); a.set_ylim(24, 0); a.set_aspect("equal")
    a.set_xticks([]); a.set_yticks([])
    a.set_title(title, fontsize=10)
fig.colorbar(im, ax=fig.axes[-4:], fraction=0.02, label="activation (x: shut all breath)")
fig.savefig(f"{d}/tone.png", dpi=100, bbox_inches="tight")
print(f"wrote {d}/tone.png")
