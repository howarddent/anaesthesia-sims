"""Draw the asthma model's airway geometry: the Weibel tree (uLungModel),
radius, length and total area by generation, the airway wall ring
(uAirwayRing) and the patchy-lung layout (uPatchyLung).
Usage: python plot_tree.py tree_geometry.png
The patchy-lung severity map is an illustrative random draw, not the
model's own seed."""
import sys, math, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.patches import Wedge, Rectangle

RF=[8.18,5.79,3.98,2.85,2.11,1.50,1.10,0.810,0.612,0.462,0.347,0.267,0.213,0.177,0.150,0.131,0.115]
RM=[8.69,6.14,4.72,3.73,2.99,2.30,1.80,1.41,1.13,0.889,0.704,0.567,0.473,0.416,0.367,0.331,0.296]
L=[120,47.6,19.0,7.6,12.7,10.7,9.0,7.6,6.4,5.4,4.6,3.9,3.3,2.7,2.3,2.0,1.65]
WALL=[0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2]
WCOL=["#7a3b8f","#c0392b","#2e86c1"]; WNAME=["cartilaginous (gen 0-1)","cartilaginous (gen 2)","membranous (gen 3-16)"]
G=len(L)

fig=plt.figure(figsize=(16,10)); gs=fig.add_gridspec(2,3,width_ratios=[1.35,1,1])
# A: tree to scale (2-D projection, branches alternate +-angle)
ax=fig.add_subplot(gs[:,0]); segs=[];lw=[];col=[]
def grow(x,y,th,g):
    x2=x+L[g]*math.cos(th); y2=y+L[g]*math.sin(th)
    segs.append([(x,y),(x2,y2)]); lw.append(max(0.15,RM[g]*0.9)); col.append(WCOL[WALL[g]])
    if g+1<G:
        a=math.radians(37 if g<3 else 33)
        grow(x2,y2,th+a,g+1); grow(x2,y2,th-a,g+1)
grow(0,0,-math.pi/2,0)
ax.add_collection(LineCollection(segs,linewidths=lw,colors=col,capstyle="round"))
ax.autoscale(); ax.set_aspect("equal"); ax.axis("off")
ax.set_title("A  Symmetric tree, generations 0-16 (Weibel model A)\n131,071 airways, lengths to scale (mm), line width ~ radius at full dilation",fontsize=10)
for i,n in enumerate(WNAME): ax.plot([],[],color=WCOL[i],lw=4,label=n)
ax.legend(loc="lower left",fontsize=8,title="wall type (modulus scale 13.9 / 3.9 / 1)",title_fontsize=8)
ax.plot([0,50],[ -10,-10],"k-",lw=1); ax.text(25,-4,"50 mm",ha="center",fontsize=8)

# B: radius & length per generation
ax=fig.add_subplot(gs[0,1]); g=np.arange(G)
ax.semilogy(g,RM,"o-",label="lumen radius, full dilation (Ptm 40 cmH2O)")
ax.semilogy(g,RF,"s--",label="Lambert's radius at FRC (not used)")
ax.semilogy(g,L,"^-",color="gray",label="length (Weibel, fixed)")
ax.set_xlabel("generation"); ax.set_ylabel("mm"); ax.grid(alpha=.3,which="both"); ax.legend(fontsize=8)
ax.set_title("B  Airway size by generation",fontsize=10)

# C: total cross-section (trumpet)
ax=fig.add_subplot(gs[0,2]); A=[2**k*math.pi*RM[k]**2/100 for k in g]
ax.semilogy(g,A,"o-",color="#16a085"); ax.set_xlabel("generation"); ax.set_ylabel("total lumen area, cm$^2$")
ax.set_title(r"C  Total cross-section, 2^g πr² (full dilation)",fontsize=10); ax.grid(alpha=.3,which="both")
for k in (0,8,16): ax.annotate(f"{A[k]:.1f}",(k,A[k]),textcoords="offset points",xytext=(4,6),fontsize=8)

# D: wall cross-section
ax=fig.add_subplot(gs[1,1])
layers=[("mucosa",0.03,"#f5b7b1",0),("submucosa",0.08,"#fdebd0",0),("smooth muscle",0.04,"#e74c3c",1),("adventitia",0.08,"#d5dbdb",0)]
def ring(cx,thick):
    r=1.0
    for name,t,c,m in layers:
        t2=t*(thick**2 if m else thick)
        ax.add_patch(Wedge((cx,0),r+t2,0,360,width=t2,fc=c,ec="k",lw=.5)); r+=t2
    for k in range(3):
        th=k*2*math.pi/3; ax.plot([cx,cx+math.cos(th)*1.0],[0,math.sin(th)*1.0],":",color="gray",lw=.6)
    return r
ro=ring(0,1); ro2=ring(3.2,1.5)
ax.text(0,-1.75,f"normal: wall {100*(ro-1):.0f}% of Ri",ha="center",fontsize=8)
ax.text(3.2,-1.75,f"asthma x1.5 (muscle x2.25): {100*(ro2-1):.0f}%",ha="center",fontsize=8)
for name,t,c,m in layers: ax.add_patch(Rectangle((0,0),0,0,fc=c,ec="k",label=name))
ax.legend(fontsize=7,loc="upper center",ncol=4,bbox_to_anchor=(0.5,1.02))
ax.set_xlim(-1.6,4.9); ax.set_ylim(-2,1.9); ax.set_aspect("equal"); ax.axis("off")
ax.set_title("D  Airway wall FE ring (uAirwayRing), radii / unloaded lumen Ri\n4 layers, folds into 3 lobes (dotted: one fold = 120°; half is meshed)",fontsize=10)

# E: patchy lung layout
ax=fig.add_subplot(gs[1,2]); rng=np.random.default_rng(3); K=8; sig=0.4
xi=[rng.standard_normal(2**k) for k in range(1,K+1)]
S=np.zeros((16,16))
for u in range(2**K):
    z=sum(xi[k][u>>(K-1-k)] for k in range(K))/math.sqrt(K)
    s=math.exp(sig*z-sig*sig/2); s=round(s/0.25)*0.25
    x0,x1,y0,y1=0,16,0,16
    for k in range(K):
        b=(u>>(K-1-k))&1
        if k%2==0: m=(x0+x1)//2; x0,x1=(m,x1) if b else (x0,m)
        else: m=(y0+y1)//2; y0,y1=(m,y1) if b else (y0,m)
    S[y0,x0]=s
im=ax.imshow(S,extent=[0,30,0,24],cmap="OrRd",origin="lower",aspect="equal")
plt.colorbar(im,ax=ax,label="severity s (illustrative draw, sigma 0.4)",shrink=.8)
ax.set_xlabel("width, cm"); ax.set_ylabel("height, cm")
ax.set_title("E  Patchy lung (uPatchyLung): trunk gen 0-7 shared,\n256 subtrees (gen 8-16) on a 16x16 frontal grid",fontsize=10)
fig.tight_layout(); fig.savefig(sys.argv[1],dpi=110)
print(A[0],A[-1])
