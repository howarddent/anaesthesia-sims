#!/usr/bin/env python3
"""Plots treatrun's out/treat.csv into out/treat.png:  python3 plot_treat.py [dir]

Left: the salbutamol dose response (muscle tone from 0.8 down) - peak and
plateau pressure, and the units shut all breath. Right: each treatment's
peak and plateau pressure, trapped volume, shunt, PaO2 and PaCO2."""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
t = np.genfromtxt(f"{d}/treat.csv", delimiter=",", names=True, dtype=None, encoding=None)
r = {row["run"]: row for row in t}
fig, ax = plt.subplots(1, 3, figsize=(16, 4.8))
dose = [n for n in ["baseline", "tone_0.7", "tone_0.6", "tone_0.5", "salbutamol"] if n in r]
tone = [r[n]["tone"] for n in dose]
ax[0].plot(tone, [r[n]["Ppeak_cmH2O"] for n in dose], "o-", color="#de2d26", label="peak")
ax[0].plot(tone, [r[n]["Pplat_cmH2O"] for n in dose], "s-", color="#3182bd", label="plateau")
a2 = ax[0].twinx()
a2.plot(tone, [r[n]["units_shut_all_breath"] for n in dose], "^--", color="#636363", label="units shut all breath")
a2.set_ylabel("units shut all breath (of 256)")
ax[0].invert_xaxis()
ax[0].set_xlabel("airway muscle tone (salbutamol lowers it)")
ax[0].set_ylabel("pressure (cmH2O)")
ax[0].legend(loc="upper right", frameon=False)
a2.legend(loc="lower left", frameon=False)
ax[0].set_title("Salbutamol dose response, 500 mL x 12 /min")
treats = [n for n in ["normal", "baseline", "salbutamol", "heliox", "salbutamol_heliox", "rate8",
                      "salbutamol_heliox_rate8"] if n in r]
labels = {"normal": "normal", "baseline": "asthma", "salbutamol": "salb.", "heliox": "heliox",
          "salbutamol_heliox": "salb.+\nheliox", "rate8": "rate 8", "salbutamol_heliox_rate8": "salb.+heliox\nrate 8"}
x = np.arange(len(treats))
ax[1].bar(x - 0.2, [r[n]["Ppeak_cmH2O"] for n in treats], 0.4, color="#de2d26", label="peak")
ax[1].bar(x + 0.2, [r[n]["Pplat_cmH2O"] for n in treats], 0.4, color="#3182bd", label="plateau")
ax[1].set_xticks(x, [labels[n] for n in treats], fontsize=8)
ax[1].set_ylabel("pressure (cmH2O)")
ax[1].legend(frameon=False)
ax[1].set_title("Airway pressures (FiO2 0.3)")
ax[2].bar(x - 0.27, [r[n]["PaO2_mmHg"] for n in treats], 0.27, color="#31a354", label="PaO2 (mmHg)")
ax[2].bar(x, [r[n]["PaCO2_mmHg"] for n in treats], 0.27, color="#756bb1", label="PaCO2 (mmHg)")
ax[2].bar(x + 0.27, [r[n]["EEV_above_FRC_mL"] / 10 for n in treats], 0.27, color="#fd8d3c",
          label="trapped gas (10 mL)")
ax[2].set_xticks(x, [labels[n] for n in treats], fontsize=8)
ax[2].legend(frameon=False, fontsize=8)
ax[2].set_title("Gas exchange and trapping")
for a in ax:
    a.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(f"{d}/treat.png", dpi=100)
print(f"wrote {d}/treat.png")
