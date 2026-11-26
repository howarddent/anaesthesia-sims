#!/usr/bin/env python3
"""Plots asthmarun's CSV files (out/tubelaw.csv, alveolus.csv, starling.csv)
into out/unit.png:  python3 plot_asthma.py [dir]"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
tl = np.genfromtxt(f"{d}/tubelaw.csv", delimiter=",", names=True)
al = np.genfromtxt(f"{d}/alveolus.csv", delimiter=",", names=True)
st = np.genfromtxt(f"{d}/starling.csv", delimiter=",", names=True)
cases = [("normal", "normal", "#1f77b4"), ("tone", "muscle tone", "#ff7f0e"),
         ("thick", "thick wall", "#2ca02c"), ("tone_thick", "tone + thick wall", "#d62728")]

fig, ax = plt.subplots(1, 3, figsize=(15, 4.6))
for key, name, col in cases:
    ax[0].plot(tl["Ptm_cmH2O"], tl[key], color=col, label=name)
ax[0].set_xlabel("transmural pressure (cmH2O)")
ax[0].set_ylabel("lumen area / unloaded normal area")
ax[0].set_title("Bronchiole tube law (FE wall, tethered at Ptp 5)")
ax[0].legend(frameon=False)

ax[1].plot(al["saline"], al["V_over_VFRC"], color="#7f7f7f", label="saline-filled")
ax[1].plot(al["deflation"], al["V_over_VFRC"], color="#1f77b4", label="deflation")
ax[1].plot(al["inflation"], al["V_over_VFRC"], color="#d62728", label="inflation")
ax[1].set_xlabel("recoil pressure (cmH2O)")
ax[1].set_ylabel("volume / volume at FRC")
ax[1].set_title("Alveolus")
ax[1].legend(frameon=False)

for key, name, col in cases:
    ax[2].plot(st["Ppl_cmH2O"], st[key], color=col, label=name)
ax[2].plot(st["Ppl_cmH2O"], st["tone_thick_mucus"], color="#9467bd", label="tone + thick + mucus")
ax[2].set_xlim(-5, 40)
ax[2].set_xlabel("pleural pressure (cmH2O)")
ax[2].set_ylabel("flow through one bronchiole (mm$^3$/s)")
ax[2].set_title("Isovolume pressure-flow (recoil 5, far end at 0)")
ax[2].legend(frameon=False)
for a in ax:
    a.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(f"{d}/unit.png", dpi=110)
print(f"wrote {d}/unit.png")
