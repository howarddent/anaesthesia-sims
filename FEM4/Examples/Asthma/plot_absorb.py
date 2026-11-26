#!/usr/bin/env python3
"""Plots absorbrun's files into out/absorb.png:  python3 plot_absorb.py [dir]

Top row against time: end-expiratory gas above FRC; perfusion to
collapsed units (true shunt); perfusion to units shut all breath that
still hold gas. Bottom row (stage 7): PaO2 / FiO2, PaCO2, and the share
of the cardiac output through unventilated units after hypoxic
vasoconstriction. The dotted line is the recruitment manoeuvre."""
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
runs = [("asthma_o2", "#de2d26", "asthma, FiO2 1.0"), ("asthma_fio2_04", "#3182bd", "asthma, FiO2 0.4"),
        ("asthma_o2_nohyst", "#fd8d3c", "asthma, FiO2 1.0, no hysteresis"),
        ("asthma_o2_nohpv", "#a50f15", "asthma, FiO2 1.0, no HPV"),
        ("asthma_air", "#756bb1", "asthma, air"),
        ("normal_o2", "#31a354", "normal, FiO2 1.0"), ("normal_air", "#74c476", "normal, air")]
fio2 = {"asthma_fio2_04": 0.4, "asthma_air": 0.21, "normal_air": 0.21}
fig, axs = plt.subplots(2, 3, figsize=(16, 9))
ax = axs[0]
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
    if "PaO2_mmHg" in t.dtype.names:
        ok = ~((t["phase"] == 1) & (np.arange(len(t)) == np.argmax(t["phase"] == 1)))
        axs[1][0].plot(t["t_min"][ok], t["PaO2_mmHg"][ok] / fio2.get(name, 1.0), color=col, label=lab)
        axs[1][1].plot(t["t_min"][ok], t["PaCO2_mmHg"][ok], color=col)
        axs[1][2].plot(t["t_min"][ok], t["shunt_after_HPV_pct"][ok], color=col)
    p1 = t["t_min"][t["phase"] == 1]
    if len(p1):
        rm = p1[0]
labs = [l for _, l in cols] + ["PaO2 / FiO2 (mmHg)", "PaCO2 (mmHg)", "shunt after HPV (% of cardiac output)"]
for k, a in enumerate(list(axs[0]) + list(axs[1])):
    if rm is not None:
        a.axvline(rm - 0.5, color="k", ls=":", lw=1)
    a.set_xlabel("time (min)")
    a.set_ylabel(labs[k])
    a.grid(alpha=0.3)
ax[0].legend(frameon=False, fontsize=8)
ax[0].set_title("Ventilated 500 mL x 12 /min; recruitment at 35 cmH2O (dotted)")
fig.tight_layout()
fig.savefig(f"{d}/absorb.png", dpi=100)
print(f"wrote {d}/absorb.png")
