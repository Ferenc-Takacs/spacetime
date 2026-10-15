import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import PillowWriter
import matplotlib.animation as animation
from mpl_toolkits.mplot3d import Axes3D
import pandas as pd
from PIL import Image
from tkinter import filedialog
import io

N = 53 # only default
writer = PillowWriter(fps=10)
one_step = 0.5
circle = 2.0
anim_range = 360
warm_range = 270 # must bigger as 8 and smaler as anim_range
last_idx = 5 # number of line sectors

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

def float_range(start, stop, step):
    while start < stop:
        yield start
        start += step
        
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
    K   = clean_and_shape_3d(df['K'  ].values)
    T   = clean_and_shape_3d(df['g00'].values)
    U   = clean_and_shape_3d(df['g01'].values)
    V   = clean_and_shape_3d(df['g02'].values)
    W   = clean_and_shape_3d(df['g03'].values)
    G12 = clean_and_shape_3d(df['g12'].values)
    G13 = clean_and_shape_3d(df['g13'].values)
    G23 = clean_and_shape_3d(df['g23'].values)
    speed = np.sqrt(U**2 + V**2 + W**2)
    #SPEED = speed.reshape(N, N, N)

    S = R - 2.0 * C - K
    xi = np.unique(x_szelet)
    yi = np.unique(y_szelet)
    zi = np.unique(z_szelet)
    X, Y, Z = np.meshgrid(xi, yi, zi)

    max_speed = np.max(speed)
    s_min = np.min(S)
    s_max = np.max(S)
    t_min = np.min(T)
    t_max = np.max(T)
    s_abs_max = max( max(abs(s_min), 0.002), max(abs(s_max), 0.002) )
    ss_max = abs(s_abs_max * max_speed  * (1.0 + t_max))
    print(f"ss_max {ss_max},  max_speed {max_speed},  t_max {t_max}")
    auto_scale = np.power(1000000000000.0 / ss_max, 1/5)
    print(f"speed :{max_speed} ss_max: {ss_max} scale: {auto_scale}")
    scale_factor = 0.75
    last_rate = 0.0

    buborek_maszk_m = np.zeros_like(S, dtype=bool)
    buborek_maszk_p = np.zeros_like(S, dtype=bool)
    if s_min < 0 :
        Sm = S[ S < 0]
        if len(Sm) > 0:
            buborek_maszk_m = ( S <= np.percentile(Sm, 1) ) & ( S < 0 )
    if s_max > 0 :
        Sp = S[ S > 0]
        if len(Sp) > 0:
            buborek_maszk_p = ( S >= np.percentile(Sp, 99) ) & ( S > 0 )

    x_min, x_max = xi.min(), xi.max()
    y_min, y_max = yi.min(), yi.max()
    z_min, z_max = zi.min(), zi.max()
    kockak_kepei = []
    np.random.seed(42) # Fix mag a reprodukálhatóságért
    num_particles = 2500
    px_orig = np.random.uniform(x_min, x_max, num_particles)
    py_orig = np.random.uniform(y_min, y_max, num_particles)
    pz_orig = np.random.uniform(z_min, z_max, num_particles)
    np.set_printoptions(precision=3, suppress=True)
    watch_part = 111

    # Eltároljuk a 360 képkockára az összes részecske 7 fázisú uszály-koordinátáját és színét
    hist_x = np.zeros((num_particles, last_idx+1))
    hist_y = np.zeros((num_particles, last_idx+1))
    hist_z = np.zeros((num_particles, last_idx+1))
    hist_v = np.zeros((num_particles), dtype=int)

    for i in range(num_particles):
        hist_x[i, last_idx] = px_orig[i]
        hist_y[i, last_idx] = py_orig[i]
        hist_z[i, last_idx] = pz_orig[i]

    fig = plt.figure(figsize=(10, 10))
    ax = fig.add_subplot(111, projection='3d')
    fig.patch.set_facecolor('black')
    ax.set_proj_type('persp', focal_length=0.2) # Bekapcsolja a valós 3D perspektívát!
    ax.set_facecolor('black')
    

    #last_watch_end = anim_range * circle + warm_range

    for frame in float_range(0, anim_range * circle + warm_range, one_step ):
        if frame >= warm_range :
            ax.clear()
            ax.set_facecolor('black')
            ax.grid(False)
            ax.xaxis.pane.fill = ax.yaxis.pane.fill = ax.zaxis.pane.fill = False
            ax.set_axis_off()
            camera_angle = frame-warm_range
            elev = 35.0
            if circle == 2.0 :
                if camera_angle < 35.0 : elev = camera_angle
                elif camera_angle > 360.0 - 35.0 :
                    if camera_angle < 360.0 + 35.0 : elev = 360.0 - camera_angle
                    elif camera_angle < 720.0 - 35.0 : elev = -35.0
                    else : elev = camera_angle - 720.0
            ax.view_init(elev=elev, azim=camera_angle)
            # 1. Először kirajzoljuk a fix pontfelhőket, a kockát, és elvégezzük az első renderelést
            if np.any(buborek_maszk_m):
                ax.scatter(x_szelet[buborek_maszk_m], y_szelet[buborek_maszk_m], z_szelet[buborek_maszk_m], color='gold', alpha=0.22)
            if np.any(buborek_maszk_p):
                ax.scatter(x_szelet[buborek_maszk_p], y_szelet[buborek_maszk_p], z_szelet[buborek_maszk_p], color='magenta', alpha=0.22)
            # Kockaváz rajzolása a háttérbe
            ax.plot([x_min, x_max, x_max, x_min, x_min, x_min, x_max, x_max, x_min, x_min, x_min],
                    [y_min, y_min, y_max, y_max, y_min, y_min, y_min, y_max, y_max, y_min, y_min],
                    [z_min, z_min, z_min, z_min, z_min, z_max, z_max, z_max, z_max, z_max, z_max], color='white', linewidth=0.5, alpha=0.5)
            ax.plot([x_min, x_min], [y_max, y_max], [z_min, z_max], color='white', linewidth=0.5, alpha=0.5)
            ax.plot([x_max, x_max], [y_min, y_min], [z_min, z_max], color='white', linewidth=0.5, alpha=0.5)
            ax.plot([x_max, x_max], [y_max, y_max], [z_min, z_max], color='white', linewidth=1.0, alpha=0.8)
            
        long = 0
        num = 0
        ok = 0
        bad = 0
        for i in range(num_particles):
            hist_x_i = hist_x[i]
            hist_y_i = hist_y[i]
            hist_z_i = hist_z[i]
            x_prev = hist_x_i[last_idx]
            y_prev = hist_y_i[last_idx]
            z_prev = hist_z_i[last_idx]
            v_prev = hist_v[i]
            for j in range(last_idx) :
                jj = j+1
                hist_x_i[j] = hist_x_i[jj]
                hist_y_i[j] = hist_y_i[jj]
                hist_z_i[j] = hist_z_i[jj]
            end = False
            ix, iy, iz = np.abs(xi - x_prev).argmin(), np.abs(yi - y_prev).argmin(), np.abs(zi - z_prev).argmin()
            local_u, local_v, local_w = U[iz, iy, ix], V[iz, iy, ix], W[iz, iy, ix]
            src, local_g00 = S[iz, iy, ix], T[iz, iy, ix]
            #local_R, local_C, local_K, local_g00 = R[iz, iy, ix], C[iz, iy, ix], K[iz, iy, ix], T[iz, iy, ix]
            #src = local_R - 2.0 * local_C - local_K
            if np.abs(src) < 0.002 : src = 0.002 if src == 0 else 0.002 * np.sign(src)
            dynamic_factor = src * (1.0 + local_g00) * auto_scale
            dynamic_factor = np.power(np.abs(dynamic_factor), (1/last_idx)) * np.sign(dynamic_factor)
            x_next = x_prev - local_u * dynamic_factor
            y_next = y_prev - local_v * dynamic_factor
            z_next = z_prev - local_w * dynamic_factor
            v_next = v_prev + 1 if v_prev < last_idx else last_idx
            first = last_idx-v_next
            v_mag = np.sqrt((x_next-hist_x_i[first])**2 + (y_next-hist_y_i[first])**2 + (z_next-hist_z_i[first])**2) / v_next
            out = x_next < x_min or x_next > x_max or y_next < y_min or y_next > y_max or z_next < z_min or z_next > z_max
            if out or v_mag < 0.1:
                hist_x_i[last_idx] = px_orig[i]
                hist_y_i[last_idx] = py_orig[i]
                hist_z_i[last_idx] = pz_orig[i]
                hist_v[i] = 0
                if not out :
                    long = long + v_mag
                    num = num + 1
                end = True
                bad = bad + 1
                #if watch_part == i :
                #    last_watch_end = frame
            else:
                hist_v[i] = v_next
                hist_x_i[last_idx] = x_next
                hist_y_i[last_idx] = y_next
                hist_z_i[last_idx] = z_next
                long = long + v_mag
                num = num + 1
                ok = ok + 1
            if frame >= warm_range :
                local_g12, local_g13, local_g23 = G12[iz, iy, ix], G13[iz, iy, ix], G23[iz, iy, ix]
                shear_intensity = np.power(local_g12**2 + local_g13**2 + local_g23**2, 1/3)
                color_phase = min(1.0, max(0.0, shear_intensity))
                line_color = (0.1 + 0.9 * color_phase, 0.8 - 0.7 * color_phase, 1.0)
                if v_next == 5 and not end:
                    ax.plot(hist_x_i, hist_y_i, hist_z_i, color=line_color, linewidth=0.9, alpha=0.6)
                else :
                    last = last_idx if end else last_idx+1
                    xd = hist_x_i[first:last]
                    yd = hist_y_i[first:last]
                    zd = hist_z_i[first:last]
                    ax.plot(xd, yd, zd, color=line_color, linewidth=0.9, alpha=0.6)
                    if v_next < last_idx-1 :
                        last = last_idx - v_next
                        xd = hist_x_i[:last]
                        yd = hist_y_i[:last]
                        zd = hist_z_i[:last]
                        ax.plot(xd, yd, zd, color=line_color, linewidth=0.9, alpha=0.6)
            #else :
                #if watch_part == i :
                #    print(f"nx: {x_next}, ny: {y_next}, nz: {z_next}, long: {v_mag}, out:{out}")
                #    print(f"x:{hist_x_i}, y:{hist_y_i}, z:{hist_z_i}, valid:{hist_v[i]} {end} {last_watch_end}")

        if frame < warm_range :
            if num != 0 :
                long = long / num
                ch = ''
                if long > 1 :
                    auto_scale = auto_scale / long
                    ch = '/'
                if long < 0.25 :
                    auto_scale = auto_scale / ( long * 4 ) if long > 0.000001 else auto_scale * 100
                    ch = '*'
                print(f"warm: {frame} factor: {scale_factor} scale{ch}: {auto_scale} long: {long} num:{num} bad: {bad} ok {ok} ")
            else :
                print("num=0")
        else :
            ax.set_xlim(x_min, x_max)
            ax.set_ylim(y_min, y_max)
            ax.set_zlim(z_min, z_max)
            
            # Pufferelés a RAM-ba
            buf = io.BytesIO()
            plt.savefig(buf, format='png', bbox_inches='tight', facecolor='black', dpi=100)
            buf.seek(0)
            img = Image.open(buf)
            img.load() 
            kockak_kepei.append(img.convert('RGB'))
            print(f"frame: {frame-warm_range}/{anim_range*circle}")
            buf.close()    


    print("Összefűzés és mentés animált WEBP fájlba...")
    halftext = f"_{one_step}"
    save_name = filename+halftext+".webp"

    kockak_kepei[0].save(
        save_name,
        format="WEBP",                  # Explicit megadjuk a formátumot
        save_all=True,              # Kötelező: az összes kocka mentése!
        append_images=kockak_kepei[1:], # Hozzáfűzzük a maradékok fáziskockáit
        duration=100,               # Képkockák közötti idő ezredmásodpercben (100ms = 10 FPS)
        loop=0                      # 0 = Végtelenített, megszakítás nélküli ismétlődés (loop)
    )

    plt.close()
    print(f"Siker! A '{save_name}' elkészült.")

