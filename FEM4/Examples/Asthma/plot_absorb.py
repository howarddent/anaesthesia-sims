#!/usr/bin/env python3
"""Plots absorbrun's files into out/absorb.png:  python3 plot_absorb.py [dir]

Against time: end-expiratory gas above FRC; perfusion to collapsed units
(true shunt); perfusion to units shut all breath that still hold gas.
The dotted line is the recruitment manoeuvre."""
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
runs = [("asthma_o2", "#de2d26", "asthma, FiO2 1.0"), ("asthma_fio2_04", "#3182bd", "asthma, FiO2 0.4"),
        ("asthma_o2_nohyst", "#fd8d3c", "asthma, FiO2 1.0, no hysteresis"),
        ("normal_o2", "#31a354", "normal, FiO2 1.0")]
fig, ax = plt.subplots(1, 3, figsize=(16, 4.6))
cols = [("EEV_above_FRC_mL", "end-expiratory gas above FRC (mL)"),
        ("perf_collapsed_pct", "perfusion to collapsed units (%)"),
        ("perf_shut_pct", "perfusion to units shut all breath, gas left (%)")]
rm = None
for name, col, lab in runs:
    fn = f"{d}/absorb_{name}.csv"
    if not os.path.exists(fn):
        continue
    t = np.genfromtxt(fn, delimiter=",", names=True)
    for k, (c, _) in enumerate(cols):
        ax[k].plot(t["t_min"], t[c], color=col, label=lab)
    p1 = t["t_min"][t["phase"] == 1]
    if len(p1):
        rm = p1[0]
for k, (_, lab) in enumerate(cols):
    if rm is not None:
        ax[k].axvline(rm - 0.5, color="k", ls=":", lw=1)
    ax[k].set_xlabel("time (min)")
    ax[k].set_ylabel(lab)
    ax[k].grid(alpha=0.3)
ax[0].legend(frameon=False, fontsize=8)
ax[0].set_title("Ventilated 500 mL x 12 /min; recruitment at 35 cmH2O (dotted)")
fig.tight_layout()
fig.savefig(f"{d}/absorb.png", dpi=100)
print(f"wrote {d}/absorb.png")
