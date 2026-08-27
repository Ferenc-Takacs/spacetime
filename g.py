import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import PillowWriter
import matplotlib.animation as animation
import pandas as pd
from PIL import Image
import io

writer = PillowWriter(fps=10)

# 1. LÉPÉS: Adatok beolvasása (A te 10 000-es automatikus mentésedből)
df = pd.read_csv("data_i50000_dx0.5000_m1.6_r10.csv", comment='#')

# Kiszedjük a koordinátákat és az áramlási irányokat (g01, g02, g03)
x = df['x'].values
y = df['y'].values
z = df['z'].values
g00 = df['g00'].values
g01 = df['g01'].values
g02 = df['g02'].values
g03 = df['g03'].values

# Kiválasztunk egy 2D-s szeletet (pl. a középső Z síkot), hogy átlátható legyen a kép
mask_z = (z == 0)
x_szelet = x[mask_z]
y_szelet = y[mask_z]
u = g01[mask_z] # X irányú sebesség
v = g02[mask_z] # Y irányú sebesség
speed = np.sqrt(u**2 + v**2)

# Rács hálózat rekonstruálása az áramvonalakhoz
xi = np.unique(x_szelet)
yi = np.unique(y_szelet)
X, Y = np.meshgrid(xi, yi)
U = u.reshape(len(yi), len(xi))
V = v.reshape(len(yi), len(xi))
SPEED = speed.reshape(len(yi), len(xi))

# 2. LÉPÉS: Az animációs ablak előkészítése
fig, ax = plt.subplots(figsize=(8, 8))
ax.set_facecolor('black') # A világűr sötétje

# Kirajzoljuk a háttérben a g00 feszültségi tórust színes felhőként
torsz = ax.contourf(X, Y, SPEED, cmap='inferno', alpha=0.4)

# 3. LÉPÉS: A te zseniális fázisszabdalt áramvonal-léptetésed leprogramozása
# A matplotlib 'streamplot' függvénye beépítve tud szaggatott vonalakat mozgatni
stream = ax.streamplot(X, Y, U, V, color='cyan', density=1.5, linewidth=1.0)

x_min, x_max = xi.min(), xi.max()
y_min, y_max = yi.min(), yi.max()
kockak_kepei = []

# Generálunk fix kiinduló mag-pontokat az egész dobozban
# Ezekből a pontokból indulnak ki a szaggatott mozgó csíkok
np.random.seed(42) # Fix mag a reprodukálhatóságért
num_particles = 400
px = np.random.uniform(x_min, x_max, num_particles)
py = np.random.uniform(y_min, y_max, num_particles)

# Az animációs hurok (50 kocka, 5 fázisú ciklus)
for frame in range(50):
    ax.clear()
    ax.set_facecolor('black')
    ax.set_title(f"Spacetime Dash Flow - Iteration 40000 - Phase {frame % 5}")
    
    # 1. Háttér feszültség felhő (g00)
    ax.contourf(X, Y, SPEED, cmap='inferno', alpha=0.3)
    
    # 2. Ciklikus fázis-léptetés (0 és 4 között)
    faza = frame % 5
    for i in range(num_particles):
        ix = np.abs(xi - px[i]).argmin()
        iy = np.abs(yi - py[i]).argmin()
        
        local_u = U[iy, ix]
        local_v = V[iy, ix]
        local_R = df['R'].values[mask_z].reshape(len(yi), len(xi))[iy, ix] # Ricci-skalár
        local_g00 = g00[mask_z].reshape(len(yi), len(xi))[iy, ix]          # g00 elem
        
        v_mag = np.sqrt(local_u**2 + local_v**2) + 1e-8
        dir_x = local_u / v_mag
        dir_y = local_v / v_mag
        
        # BONYOLULTABB IDŐFEJLESZTÉS: A csíkok sebessége és hossza most már nem monoton!
        # Összekapcsoljuk a helyi Ricci feszültséggel (local_R) és a g00 horizontközelséggel.
        # Ahol R negatív (-0.2), ott a csíkok befelé szívódnak, ahol pozitív, ott kifelé lökődnek!
        dynamic_factor = (local_R + 0.0) * (1.0 + local_g00) * 6.0
        
        vonal_hossz = 5.0 * (1.0 / (1.0 + np.abs(local_R)))
        dx = dir_x * vonal_hossz * dynamic_factor
        dy = dir_y * vonal_hossz * dynamic_factor
        
        global_progress = (frame / 50.0) % 1.0
        
        # A te zseniális 3 átlapolt harmadoló szálad pörgetése
        for thread in range(3):
            thread_shift = thread / 3.0
            progress = (global_progress + thread_shift) % 1.0
            
            x1 = px[i] + dx * progress
            y1 = py[i] + dy * progress
            x2 = px[i] + dx * (progress + 0.25)
            y2 = py[i] + dy * (progress + 0.25)
            
            # KELETKEZÉS ÉS ELNYELŐDÉS VIZUÁLIS MODULÁCIÓJA (Alpha és színfázis)
            # A fényerőt és az átlátszóságot közvetlenül a helyi feszültségkomplexum vezérli.
            # A fűrészfog-instabilitást (4 pixeles hullámzást) egy koszinuszos idő-tér modulációval 
            # visszük be, így a csíkok gyönyörűen pulzálni, lüktetni fognak haladás közben!
            wave_pulsation = np.cos((px[i]*2.0 + py[i]*2.0) - (frame * 0.4))
            alpha_base = np.sin(progress * np.pi)
            
            # Végső, komplex feszültség-függő fényerő
            alpha_factor = alpha_base * (0.5 + 0.5 * wave_pulsation)
            
            # Csak akkor rajzolunk, ha a téridő-szövet épp nem elnyelt fázisban van
            if alpha_factor > 0.1:
                ax.plot([x1, x2], [y1, y2], color='cyan', linewidth=1.4, alpha=alpha_factor * 0.8)
               
    # Lakattal lezárjuk a határokat
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_min, y_max)
    
    # Pufferelés a szélsebes RAM memóriába (BytesIO)
    buf = io.BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', facecolor='black', dpi=100)
    buf.seek(0)
    
    img = Image.open(buf)
    img.load() 
    rgb_img = img.convert('RGB')
    kockak_kepei.append(rgb_img)
    print(f"Fázis-kocka kész: {frame}/50")
    buf.close()



print("Összefűzés és mentés animált WEBP fájlba...")

kockak_kepei[0].save(
    "spacetime_vortex.webp",
    format="WEBP",                  # Explicit megadjuk a formátumot
    save_all=True,              # Kötelező: az összes kocka mentése!
    append_images=kockak_kepei[1:], # Hozzáfűzzük a maradék 49 fáziskockát
    duration=100,               # Képkockák közötti idő ezredmásodpercben (100ms = 10 FPS)
    loop=0                      # 0 = Végtelenített, megszakítás nélküli ismétlődés (loop)
)

plt.close()
print("Siker! A 'spacetime_vortex.webp' elkészült és tökéletesen animál!")

