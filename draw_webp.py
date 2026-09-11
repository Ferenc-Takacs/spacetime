import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import PillowWriter
import matplotlib.animation as animation
from mpl_toolkits.mplot3d import Axes3D
import pandas as pd
from PIL import Image
from tkinter import filedialog
import io

N = 53
writer = PillowWriter(fps=10)

def clean_and_shape_3d(raw_vector, coord=False):
    global N
    cleaned = np.where(np.isinf(raw_vector), np.nan, raw_vector)
    if np.isnan(cleaned).any():
        indices = np.arange(len(cleaned))
        good_mask = ~np.isnan(cleaned)
        if good_mask.any():
            cleaned = np.interp(indices, indices[good_mask], cleaned[good_mask])
        else:
            cleaned = np.zeros_like(cleaned)
    if coord :
        min_, max_ = cleaned.min(), cleaned.max()
        N = int(max_ - min_) + 1
    return cleaned.reshape((N, N, N)) #.transpose(2, 1, 0)

while True :
    filename = filedialog.askopenfilename(
        title="Válassz ki egy adatsort (53x53x53 CSV)",
        filetypes=[("CSV fájlok", "*.csv"), ("Minden fájl", "*.*")]
    )
    if filename == '' :
        exit()
    df = pd.read_csv(filename, comment='#')
    for coord in ['x', 'y', 'z']:
        if coord not in df.columns:
            print(f"HIBA: Az új fájlból hiányzik a(z) '{coord}' oszlop!")
            exit()
    print(filename)

    x_szelet = clean_and_shape_3d(df['x'].values, coord=True)
    y_szelet = clean_and_shape_3d(df['y'].values)
    z_szelet = clean_and_shape_3d(df['z'].values)
    min_x, max_x = x_szelet.min(), x_szelet.max()
    min_y, max_y = y_szelet.min(), y_szelet.max()
    min_z, max_z = z_szelet.min(), z_szelet.max()
    if min_y != min_x or min_z != min_x or max_y != max_x or max_z != max_x :
        print(f"HIBA: inkonzisztens koordináta tartomány!")
        continue
    R   = clean_and_shape_3d(df['R'  ].values)
    C   = clean_and_shape_3d(df['C2' ].values)
    T   = clean_and_shape_3d(df['g00'].values)
    U   = clean_and_shape_3d(df['g01'].values)
    V   = clean_and_shape_3d(df['g02'].values)
    W   = clean_and_shape_3d(df['g03'].values)
    #G12 = clean_and_shape_3d(df['g12'].values)
    #G13 = clean_and_shape_3d(df['g13'].values)
    #G23 = clean_and_shape_3d(df['g23'].values)
    speed = np.sqrt(U**2 + V**2 + W**2)
    #SPEED = speed.reshape(N, N, N)

    xi = np.unique(x_szelet)
    yi = np.unique(y_szelet)
    zi = np.unique(z_szelet)
    X, Y, Z = np.meshgrid(xi, yi, zi)


    max_speed = np.max(speed)
    r_min = np.min(R)
    r_max = np.max(R)
    t_min = np.min(T)
    t_max = np.max(T)
    r_abs_max = max( max(abs(r_min), 0.002), max(abs(r_max), 0.002) )
    s_max = r_abs_max * max_speed  * (1.0 + t_max)
    auto_scale = np.power(1000000000000.0 / s_max, 1/5)
    print(f"speed :{max_speed} s_max: {s_max} scale: {auto_scale}")
#            if np.abs(local_R) < 0.003 : local_R = 0.002 * np.sign(local_R)
#            dynamic_factor = local_R * (1.0 + local_g00) * auto_scale
#            dynamic_factor = np.power(np.abs(dynamic_factor), (1/5)) * np.sign(dynamic_factor)

    buborek_maszk = (np.abs(R) > r_abs_max * 0.8 )

    # 2. LÉPÉS: Az animációs ablak előkészítése
    fig = plt.figure(figsize=(10, 10))
    ax = fig.add_subplot(111, projection='3d')
    fig.patch.set_facecolor('black')
    ax.set_proj_type('persp', focal_length=0.2) # Bekapcsolja a valós 3D perspektívát!
    ax.set_facecolor('black')

    x_min, x_max = xi.min(), xi.max()
    y_min, y_max = yi.min(), yi.max()
    z_min, z_max = zi.min(), zi.max()
    kockak_kepei = []
    np.random.seed(42) # Fix mag a reprodukálhatóságért
    num_particles = 3000
    px_orig = np.random.uniform(x_min, x_max, num_particles)
    py_orig = np.random.uniform(y_min, y_max, num_particles)
    pz_orig = np.random.uniform(z_min, z_max, num_particles)
    px = np.copy(px_orig)
    py = np.copy(py_orig)
    pz = np.copy(pz_orig)

    #print(x_min, x_max, y_min, y_max, z_min, z_max)
    for frame in range(90):
        ok = 0
        bad = 0
        for i in range(num_particles):
            x_n, y_n, z_n = px[i], py[i], pz[i]
            ix = np.abs(xi - x_n).argmin()
            iy = np.abs(yi - y_n).argmin()
            iz = np.abs(zi - z_n).argmin()
            local_u   = U[iz, iy, ix]
            local_v   = V[iz, iy, ix]
            local_w   = W[iz, iy, ix]
            local_R   = R[iz, iy, ix]
            local_C   = C[iz, iy, ix]
            local_g00 = T[iz, iy, ix]
            u_eff = local_u #+ (local_g12 * local_v) + (local_g13 * local_w)
            v_eff = local_v #- (local_g12 * local_u) + (local_g23 * local_w)
            w_eff = local_w #- (local_g13 * local_u) - (local_g23 * local_v)
            if np.abs(local_R) < 0.003 : local_R = 0.002 * np.sign(local_R)
            dynamic_factor = local_R * (1.0 + local_g00) * auto_scale
            dynamic_factor = np.power(np.abs(dynamic_factor), (1/5)) * np.sign(dynamic_factor)
            local_dx = u_eff * dynamic_factor
            local_dy = v_eff * dynamic_factor
            local_dz = w_eff * dynamic_factor
            x_n = x_n - local_dx
            y_n = y_n - local_dy
            z_n = z_n - local_dz
            v_mag = np.sqrt(local_dx**2 + local_dy**2 + local_dz**2)
            #print(v_mag)
            if  x_n < x_min or x_n > x_max or y_n < y_min or y_n > y_max or z_n < z_min or z_n > z_max or v_mag < 0.2:
                px[i] = px_orig[i]
                py[i] = py_orig[i]
                pz[i] = pz_orig[i]
                bad = bad + 1
            else :
                px[i] = x_n
                py[i] = y_n
                pz[i] = z_n
                ok = ok +1
        if 2 * ok < 3 * bad :
            auto_scale = auto_scale * 1.5
        if bad < 3 * ok :
            auto_scale = auto_scale * 0.6666
        print(f"warm: {frame}")

    print(f"scale: {auto_scale}")
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
        if np.any(buborek_maszk):
            ax.scatter(x_szelet[buborek_maszk], y_szelet[buborek_maszk], z_szelet[buborek_maszk], color='purple', alpha=0.8, s=3, depthshade=True)

        for i in range(num_particles):
            x_n, y_n, z_n = px[i], py[i], pz[i]
            x_s, y_s, z_s = x_n, y_n, z_n
            x_draw, y_draw, z_draw = [x_n], [y_n], [z_n]
            for ph in range(7) :
                ix, iy, iz = np.abs(xi - x_n).argmin(), np.abs(yi - y_n).argmin(), np.abs(zi - z_n).argmin()
                local_u   = U[iz, iy, ix]
                local_v   = V[iz, iy, ix]
                local_w   = W[iz, iy, ix]
                local_R   = R[iz, iy, ix]
                local_C   = C[iz, iy, ix]
                local_g00 = T[iz, iy, ix]
                u_eff = local_u #+ (local_g12 * local_v) + (local_g13 * local_w)
                v_eff = local_v #- (local_g12 * local_u) + (local_g23 * local_w)
                w_eff = local_w #- (local_g13 * local_u) - (local_g23 * local_v)
                if np.abs(local_R) < 0.003 : local_R = 0.002 * np.sign(local_R)
                dynamic_factor = local_R * (1.0 + local_g00) * auto_scale
                dynamic_factor = np.power(np.abs(dynamic_factor), (1/5)) * np.sign(dynamic_factor)
                local_dx = u_eff * dynamic_factor
                local_dy = v_eff * dynamic_factor
                local_dz = w_eff * dynamic_factor
                x_n = x_n - local_dx
                y_n = y_n - local_dy
                z_n = z_n - local_dz
                if  x_n < x_min or x_n > x_max or y_n < y_min or y_n > y_max or z_n < z_min or z_n > z_max:
                    break            
                x_draw.append( x_n )
                y_draw.append( y_n )
                z_draw.append( z_n )
            v_mag = np.sqrt((x_n-x_s)**2 + (y_n-y_s)**2 + (z_n-z_s)**2)
            if len(x_draw) == 1 or v_mag < 0.7 : 
                px[i] = px_orig[i]
                py[i] = py_orig[i]
                pz[i] = pz_orig[i]
            else :
                px[i] = x_draw[1]
                py[i] = y_draw[1]
                pz[i] = z_draw[1]
                #distance_to_cam = np.sqrt((x_[0] - cam_x)**2 + (y_[0] - cam_y)**2 + (z_[0] - cam_z)**2)        
                #depth_alpha = 1.0 - (distance_to_cam - 15.0) / 45.0
                #alpha_factor = min(1.0, max(0.1, depth_alpha))
                #color_intensity = min(1.0, max(0.1, local_C / 0.33))
                #line_color = (color_intensity, 1.0 - color_intensity, 1.0) 
                #print( x_draw, y_draw, z_draw )
                ax.plot(x_draw, y_draw, z_draw, color="cyan", linewidth=0.9, alpha=0.6)

           
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
        print(f"frame: {frame}/{anim_range}")
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
    print(f"Siker! A '{filename}.webp' elkészült.")

