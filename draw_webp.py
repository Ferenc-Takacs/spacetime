import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import PillowWriter
import matplotlib.animation as animation
from mpl_toolkits.mplot3d import Axes3D
import pandas as pd
from PIL import Image
from tkinter import filedialog
import io

filename = filedialog.askopenfilename(
    title="Válassz ki egy adatsort (53x53x53 CSV)",
    filetypes=[("CSV fájlok", "*.csv"), ("Minden fájl", "*.*")]
)
if filename == '' :
    exit()
df = pd.read_csv(filename, comment='#')
printf(filename)

writer = PillowWriter(fps=10)

z = df['z'].values

# Kiválasztunk egy 2D-s szeletet (pl. a középső Z síkot), hogy átlátható legyen a kép
#mask_z = (z == 0)
x_szelet = df['x'  ].values#[mask_z]
y_szelet = df['y'  ].values#[mask_z]
z_szelet = df['z'  ].values#[mask_z]
r        = df['R'  ].values#[mask_z] # T
c        = df['C2' ].values#[mask_z] # C2
t        = df['g00'].values#[mask_z] # T
u        = df['g01'].values#[mask_z] # X irányú sebesség
v        = df['g02'].values#[mask_z] # Y irányú sebesség
w        = df['g03'].values#[mask_z] # Y irányú sebesség

speed = np.sqrt(u**2 + v**2 + w**2)
max_speed = np.max(speed)
r_min = np.min(r)
r_max = np.max(r)
t_min = np.min(t)
t_max = np.max(t)
s_max = max( (r_min + 0.002) * (1.0 + t_min), (r_max + 0.002) * (1.0 + t_max) )
if s_max > 1e-30:
    auto_scale = 1.5 / s_max
else:
    auto_scale = 1.0

# Rács hálózat rekonstruálása az áramvonalakhoz
xi = np.unique(x_szelet)
yi = np.unique(y_szelet)
zi = np.unique(z_szelet)
X, Y, Z = np.meshgrid(xi, yi, zi)
R     =     r.reshape(len(zi), len(yi), len(xi))
C     =     c.reshape(len(zi), len(yi), len(xi))
T     =     t.reshape(len(zi), len(yi), len(xi))
U     =     u.reshape(len(zi), len(yi), len(xi))
V     =     v.reshape(len(zi), len(yi), len(xi))
W     =     w.reshape(len(zi), len(yi), len(xi))
SPEED = speed.reshape(len(zi), len(yi), len(xi))

# 2. LÉPÉS: Az animációs ablak előkészítése
fig = plt.figure(figsize=(10, 10))
ax = fig.add_subplot(111, projection='3d')
fig.patch.set_facecolor('black')
ax.set_proj_type('persp', focal_length=0.2) # Bekapcsolja a valós 3D perspektívát!
ax.set_facecolor('black')


# Kirajzoljuk a háttérben a g00 feszültségi tórust színes felhőként
#torsz = ax.contourf(X, Y, Z, SPEED, cmap='inferno', alpha=0.4)

# 3. LÉPÉS: A te zseniális fázisszabdalt áramvonal-léptetésed leprogramozása
# A matplotlib 'streamplot' függvénye beépítve tud szaggatott vonalakat mozgatni
#stream = ax.streamplot(X, Y, Z, U, V, W, color='cyan', density=1.5, linewidth=1.0)

x_min, x_max = xi.min(), xi.max()
y_min, y_max = yi.min(), yi.max()
z_min, z_max = zi.min(), zi.max()
kockak_kepei = []

np.random.seed(42) # Fix mag a reprodukálhatóságért
num_particles = 2500
px_orig = np.random.uniform(x_min, x_max, num_particles)
py_orig = np.random.uniform(y_min, y_max, num_particles)
pz_orig = np.random.uniform(z_min, z_max, num_particles)

px = np.copy(px_orig)
py = np.copy(py_orig)
pz = np.copy(pz_orig)

anim_range = 360
for frame in range(anim_range):
    ax.clear()
    ax.set_facecolor('black')
    # KIKAPCSOLJUK A TENGELYEKET A TISZTA, KOZMIKUS LÁTVÁNYÉRT
    ax.grid(False)
    ax.xaxis.pane.fill = False
    ax.yaxis.pane.fill = False
    ax.zaxis.pane.fill = False
    ax.set_axis_off()
    camera_angle = (frame / anim_range) * 360.0
    ax.view_init(elev=35.0, azim=camera_angle)
    rad = np.radians(camera_angle)
    # A kamera elméleti iránya a térben (X és Y vetület a forgás szerint)
    cam_x = np.cos(rad) * 30.0
    cam_y = np.sin(rad) * 30.0
    cam_z = np.sin(np.radians(25.0)) * 30.0

    for i in range(num_particles):
        x1 = px[i]
        y1 = py[i]
        z1 = pz[i]
        
        ix = np.abs(xi - x1).argmin()
        iy = np.abs(yi - y1).argmin()
        iz = np.abs(zi - z1).argmin()
        local_u   = U[iz, iy, ix]
        local_v   = V[iz, iy, ix]
        local_w   = W[iz, iy, ix]
        local_R   = R[iz, iy, ix]
        local_C   = C[iz, iy, ix]
        local_g00 = T[iz, iy, ix]
        dynamic_factor = (local_R + 0.002) * (1.0 + local_g00) * auto_scale
        dynamic_factor = np.power(np.abs(dynamic_factor), (1/5)) * np.sign(dynamic_factor)
        local_dx = local_u * dynamic_factor
        local_dy = local_v * dynamic_factor
        local_dz = local_w * dynamic_factor
        x2 = x1 + local_dx
        y2 = y1 + local_dy
        z2 = z1 + local_dz
        v_mag = np.sqrt(local_dx**2 + local_dy**2 + local_dz**2)
        if x2 < x_min or x2 > x_max or y2 < y_min or y2 > y_max or z2 < z_min or z2 > z_max or v_mag < 0.7:
            px[i] = px_orig[i]
            py[i] = py_orig[i]
            pz[i] = pz_orig[i]
            continue
        old_i = i
        px[i] = x2
        py[i] = y2
        pz[i] = z2
        
        wave_pulsation = 1.0 #np.cos((px[i]*2.0 + py[i]*2.0 + pz[i]*2.0) - (frame * 0.4))
        alpha_factor = 0.4 + 0.4 * wave_pulsation
        distance_to_cam = np.sqrt((x1 - cam_x)**2 + (y1 - cam_y)**2 + (z1 - cam_z)**2)        
        depth_alpha = 1.0 - (distance_to_cam - 15.0) / 45.0
        depth_alpha = min(1.0, max(0.1, depth_alpha))
        alpha_factor = alpha_factor * depth_alpha
        color_intensity = min(1.0, max(0.1, local_C / 0.33))
        line_color = (color_intensity, 1.0 - color_intensity, 1.0) 


        ix = np.abs(xi - x2).argmin()
        iy = np.abs(yi - y2).argmin()
        iz = np.abs(zi - z2).argmin()
        local_u   = U[iz, iy, ix]
        local_v   = V[iz, iy, ix]
        local_w   = W[iz, iy, ix]
        local_R   = R[iz, iy, ix]
        local_C   = C[iz, iy, ix]
        local_g00 = T[iz, iy, ix]
        dynamic_factor = (local_R + 0.002) * (1.0 + local_g00) * auto_scale
        dynamic_factor = np.power(np.abs(dynamic_factor), (1/5)) * np.sign(dynamic_factor)
        local_dx = local_u * dynamic_factor
        local_dy = local_v * dynamic_factor
        local_dz = local_w * dynamic_factor
        x3 = x2 + local_dx
        y3 = y2 + local_dy
        z3 = z2 + local_dz
        if x3 < x_min or x3 > x_max or y3 < y_min or y3 > y_max or z3 < z_min or z3 > z_max:
            ax.plot([x1, x2], [y1, y2], [z1, z2], color=line_color, linewidth=0.9, alpha=alpha_factor)
            continue
            
        ix = np.abs(xi - x3).argmin()
        iy = np.abs(yi - y3).argmin()
        iz = np.abs(zi - z3).argmin()
        local_u   = U[iz, iy, ix]
        local_v   = V[iz, iy, ix]
        local_w   = W[iz, iy, ix]
        local_R   = R[iz, iy, ix]
        local_C   = C[iz, iy, ix]
        local_g00 = T[iz, iy, ix]
        dynamic_factor = (local_R + 0.002) * (1.0 + local_g00) * auto_scale
        dynamic_factor = np.power(np.abs(dynamic_factor), (1/5)) * np.sign(dynamic_factor)
        local_dx = local_u * dynamic_factor
        local_dy = local_v * dynamic_factor
        local_dz = local_w * dynamic_factor
        x4 = x3 + local_dx
        y4 = y3 + local_dy
        z4 = z3 + local_dz
        wave_pulsation = 1.0 #np.cos((px[i]*2.0 + py[i]*2.0 + pz[i]*2.0) - (frame * 0.4))
        alpha_factor = 0.4 + 0.4 * wave_pulsation
        color_intensity = min(1.0, max(0.1, local_C / 0.33))
        line_color = (color_intensity, 1.0 - color_intensity, 1.0) 
        # Fázisszűrés helyett a folyamatos mozgás adja meg a hullámzást a Zitterbewegung alapján!
        if x4 < x_min or x4 > x_max or y4 < y_min or y4 > y_max or z4 < z_min or z4 > z_max:
            ax.plot([x1, x2, x3], [y1, y2, y3], [z1, z2, z3], color=line_color, linewidth=0.9, alpha=alpha_factor)
            continue
            
        ax.plot([x1, x2, x3, x4], [y1, y2, y3, y4], [z1, z2, z3, z4], color=line_color, linewidth=0.9, alpha=alpha_factor)
        
    ax.plot(
        [x_min, x_max, x_max, x_min, x_min, x_min, x_max, x_max, x_min, x_min, x_min],
        [y_min, y_min, y_max, y_max, y_min, y_min, y_min, y_max, y_max, y_min, y_min],
        [z_min, z_min, z_min, z_min, z_min, z_max, z_max, z_max, z_max, z_max, z_max],
        color='white', linewidth=0.5, alpha=0.5)
    ax.plot( [x_min, x_min], [y_max, y_max], [z_min, z_max], color='white', linewidth=0.5, alpha=0.5)
    ax.plot( [x_max, x_max], [y_min, y_min], [z_min, z_max], color='white', linewidth=0.5, alpha=0.5)
    ax.plot( [x_max, x_max], [y_max, y_max], [z_min, z_max], color='white', linewidth=1.0, alpha=0.8)
    # Lakattal lezárjuk a határokat
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(y_min, y_max)
    ax.set_zlim(z_min, z_max)
    # Pufferelés a szélsebes RAM memóriába (BytesIO)
    buf = io.BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', facecolor='black', dpi=100)
    buf.seek(0)
    
    img = Image.open(buf)
    img.load() 
    rgb_img = img.convert('RGB')
    kockak_kepei.append(rgb_img)
    print(f"kész: {frame}/{anim_range}")
    buf.close()


print("Összefűzés és mentés animált WEBP fájlba...")

kockak_kepei[0].save(
    filename+".webp",
    format="WEBP",                  # Explicit megadjuk a formátumot
    save_all=True,              # Kötelező: az összes kocka mentése!
    append_images=kockak_kepei[1:], # Hozzáfűzzük a maradékok fáziskockáit
    duration=100,               # Képkockák közötti idő ezredmásodpercben (100ms = 10 FPS)
    loop=0                      # 0 = Végtelenített, megszakítás nélküli ismétlődés (loop)
)

plt.close()
print("Siker! A 'spacetime_vortex.webp' elkészült és tökéletesen animál!")

