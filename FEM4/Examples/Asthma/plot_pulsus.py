#!/usr/bin/env python3
"""Plots pulsusrun's output into out/pulsus.png:  python3 plot_pulsus.py [dir]

Top left: the asthmatic's pleural and arterial (cuff-site) pressures over
two breaths, inspiration shaded. Top right: every beat's systolic pressure
against its phase in the breath, for four cases. Bottom left: pulsus
paradoxus against the pleural swing for every case, with the thoracic
aorta's share of arterial compliance as a line. Bottom right: the
asthmatic's pulsus with each mechanism switched off."""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1] if len(sys.argv) > 1 else "out"
s = np.genfromtxt(f"{d}/pulsus.csv", delimiter=",", names=True, dtype=None, encoding=None)
lab = {"normal": "normal", "asthma": "asthma", "salbutamol": "salbutamol", "heliox": "heliox",
       "cpap5": "CPAP 5", "cpap10": "CPAP 10", "salbutamol_heliox": "salb. + heliox",
       "salbutamol_cpap5": "salb. + CPAP 5"}
TiFrac = 0.35
fig, ax = plt.subplots(2, 2, figsize=(14, 9))

a = ax[0][0]
w = np.genfromtxt(f"{d}/pulsus_asthma_wave.csv", delimiter=",", names=True)
tb = w["t_s"][-1] / 2
for k in range(2):
    a.axvspan(k * tb, k * tb + TiFrac * tb, color="#deebf7")
a.plot(w["t_s"], w["Psa_mmHg"], color="#de2d26", lw=1, label="systemic artery (cuff site)")
a.plot(w["t_s"], w["Plv_mmHg"], color="#fc9272", lw=0.6, label="left ventricle")
a2 = a.twinx()
a2.plot(w["t_s"], w["Ppl_mmHg"], color="#3182bd", lw=1.5, label="pleural pressure")
a2.set_ylabel("pleural pressure (mmHg)", color="#3182bd")
a2.set_ylim(-40, 20)
a.set_ylim(0, 150)
a.set_xlabel("time (s)"); a.set_ylabel("pressure (mmHg)")
a.set_title("Asthma: two breaths at 25 /min, HR 107 (inspiration shaded)")
h1, l1 = a.get_legend_handles_labels(); h2, l2 = a2.get_legend_handles_labels()
a.legend(h1 + h2, l1 + l2, loc="lower right", fontsize=8)

a = ax[0][1]
a.axvspan(0, TiFrac, color="#deebf7")
for r, c in [("normal", "#636363"), ("asthma", "#de2d26"), ("salbutamol", "#31a354"), ("cpap10", "#756bb1")]:
    b = np.genfromtxt(f"{d}/pulsus_{r}_beats.csv", delimiter=",", names=True)
    a.plot(b["phase"], b["SBP_mmHg"], ".", ms=3, color=c, alpha=0.5)
    nb = 24
    idx = np.minimum((b["phase"] * nb).astype(int), nb - 1)
    m = [b["SBP_mmHg"][idx == i].mean() for i in range(nb)]
    a.plot((np.arange(nb) + 0.5) / nb, m, "-", color=c, lw=2, label=lab[r])
a.set_xlabel("phase of the breath (0 = start of inspiration)"); a.set_ylabel("systolic pressure (mmHg)")
a.set_title("Systolic pressure beat by beat, and its mean by phase")
a.legend(fontsize=8)

a = ax[1][0]
f = s[s["mechanism"] == "full"]
x = np.linspace(0, 20, 2)
a.plot(x, 0.6 / 1.45 * x, "--", color="#969696", label="thoracic share of arterial compliance (0.41)")
a.plot(x, 10 + 0 * x, ":", color="#de2d26", lw=1)
a.text(19.7, 10.3, "10 mmHg: classical bedside threshold", fontsize=8, color="#de2d26", ha="right")
for row in f:
    a.plot(row["Ppl_swing_mmHg"], row["pulsus_envelope_mmHg"], "o", color="#3182bd")
    a.plot(row["Ppl_swing_mmHg"], row["pulsus_mmHg"], "s", color="#9ecae1", ms=5)
    a.annotate(lab[row["run"]], (row["Ppl_swing_mmHg"], row["pulsus_envelope_mmHg"]), fontsize=7,
               xytext=(4, 3), textcoords="offset points")
a.plot([], [], "o", color="#3182bd", label="envelope (mean by phase)")
a.plot([], [], "s", color="#9ecae1", label="bedside (max - min within a breath)")
a.set_xlim(0, 20); a.set_ylim(0, 12)
a.set_xlabel("pleural pressure swing (mmHg)"); a.set_ylabel("pulsus paradoxus (mmHg)")
a.set_title("Pulsus tracks the pleural swing")
a.legend(fontsize=8, loc="lower right")

a = ax[1][1]
m = s[s["run"] == "asthma"]
mlab = {"full": "full model", "rigid": "rigid septum,\nno pericardium", "veins": "no inspiratory\nvenous return",
        "nozones": "no alveolar\nsqueeze", "dry": "-300 mL", "wet": "+300 mL",
        "aorta": "thoracic aorta\n0.6 of compliance", "steady": "steady\n(floor)"}
xs = np.arange(len(m))
a.bar(xs - 0.2, m["pulsus_envelope_mmHg"], 0.4, color="#3182bd", label="pulsus, envelope (mmHg)")
a.bar(xs + 0.2, m["PPV_pct"], 0.4, color="#fdae6b", label="pulse pressure variation (%)")
a.set_xticks(xs); a.set_xticklabels([mlab[n] for n in m["mechanism"]], fontsize=7, rotation=25, ha="right")
a.set_title("Asthma: what causes it (each mechanism switched off)")
a.legend(fontsize=8)

fig.tight_layout()
fig.savefig(f"{d}/pulsus.png", dpi=110)
print(f"{d}/pulsus.png")
