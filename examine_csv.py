# View csv datas in 3D graphics which saved from spacetime rust progam
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.text import Text
from matplotlib.widgets import Slider, TextBox, Button
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from skimage import measure
import os
import tkinter as tk
from tkinter import filedialog

N = 53
KVAL_CUT = 0
MAX_ABS_PHI = 5.0

filename = filedialog.askopenfilename(
    title="Válassz ki egy adatsort (53x53x53 CSV)",
    filetypes=[("CSV fájlok", "*.csv"), ("Minden fájl", "*.*")]
)
if filename == '' :
    exit()

fields = ['k11','k22','k33']
fields_text = "k11,k22,k33,";
current_mode_title = "Skalármező"
current_mode = 1 # 1,2,3,4,5

df = None
X, Y, Z = None, None, None
Phi, U, V, W = None, None, None, None
min_x, max_x, min_y, max_y, min_z, max_z = 0, 0, 0, 0, 0, 0
phi_min, phi_max = 0.0, 1.0

def clean_and_shape_3d(raw_vector, KVAL_CUT, apply_abs_filter=False, coord=False):
    global N
    cleaned = np.where(np.isinf(raw_vector), np.nan, raw_vector)
    if apply_abs_filter and (MAX_ABS_PHI is not None):
        cleaned = np.where(np.abs(cleaned) > MAX_ABS_PHI, np.nan, cleaned)
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
    grid_3d = cleaned.reshape((N, N, N)).transpose(2, 1, 0)
    return grid_3d[KVAL_CUT:N-KVAL_CUT, KVAL_CUT:N-KVAL_CUT, KVAL_CUT:N-KVAL_CUT]

def load_and_process_data(fname="*", field_text="*"):
        global df, X, Y, Z, Phi, U, V, W, min_x, max_x, min_y, max_y, min_z, max_z, phi_min, phi_max, current_mode, current_mode_title, filename, fields, fields_text

##    try:
        if fname != "*" :
            if not os.path.exists(fname):
                print(f"HIBA: A(z) '{fname}' fájl nem létezik a mappában!")
                return False
            temp_df = pd.read_csv(fname)
            # Alap kötelező koordináták ellenőrzése
            for coord in ['x', 'y', 'z']:
                if coord not in temp_df.columns:
                    print(f"HIBA: Az új fájlból hiányzik a(z) '{coord}' oszlop!")
                    return False
            # Koordináta rácsok építése
            X = clean_and_shape_3d(temp_df['x'].values, KVAL_CUT, coord=True)
            Y = clean_and_shape_3d(temp_df['y'].values, KVAL_CUT)
            Z = clean_and_shape_3d(temp_df['z'].values, KVAL_CUT)
            min_x, max_x = X.min(), X.max()
            min_y, max_y = Y.min(), Y.max()
            min_z, max_z = Z.min(), Z.max()
            if min_y != min_x or min_z != min_x or max_y != max_x or max_z != max_x :
                print(f"HIBA: inkonzisztens koordináta tartomány!")
                return False
            df = temp_df
            filename = fname

        if field_text != "*" :
            parts = [p.strip() for p in field_text.split(',')]
            if len(parts) >= 1 and parts[0] not in df.columns:
                print(f"HIBA: A(z) '{parts[0]}' mező nem található az új '{filename}' fájlban!\n Elérhetők:  {df.columns.tolist()}")
                return False
            if len(parts) >= 3 and parts[1] not in df.columns:
                print(f"HIBA: A(z) '{parts[1]}' mező nem található az új '{filename}' fájlban!\n Elérhetők:  {df.columns.tolist()}")
                return False
            if len(parts) >= 3 and parts[2] not in df.columns:
                print(f"HIBA: A(z) '{parts[2]}' mező nem található az új '{filename}' fájlban!\n Elérhetők:  {df.columns.tolist()}")
                return False
            fields = parts
            fields_text = field_text
        
        # Logika alkalmazása a mezőszámok alapján
        current_mode = len(fields)
        if len(fields) == 1:
            current_mode_title = f"Skalármező felület: '{fields[0]}'"
            Phi = clean_and_shape_3d(df[fields[0]].values, KVAL_CUT, apply_abs_filter=True)

        elif len(fields) == 2: # skalármező gradiense
            current_mode_title = f"Skalármező + Gradiens: '{fields[0]}'"
            Phi = clean_and_shape_3d(df[fields[0]].values, KVAL_CUT, apply_abs_filter=True)
            grad_x, grad_y, grad_z = np.gradient(Phi)
            U = -grad_x
            V = -grad_y
            W = -grad_z
            vlen_raw = np.sqrt(U**2 + V**2 + W**2)
            A = clean_and_shape_3d(vlen_raw, KVAL_CUT, apply_abs_filter=True)
            #print(f"grad len: {float(A.max())}")

        elif len(fields) == 3:
            current_mode_title = f"Vektormező {fields[0]},{fields[1]},{fields[2]})"
            U = clean_and_shape_3d(df[fields[0]].values, KVAL_CUT)
            V = clean_and_shape_3d(df[fields[1]].values, KVAL_CUT)
            W = clean_and_shape_3d(df[fields[2]].values, KVAL_CUT)
            vlen_raw = np.sqrt(df[fields[0]].values**2 + df[fields[1]].values**2 + df[fields[2]].values**2)
            Phi = clean_and_shape_3d(vlen_raw, KVAL_CUT, apply_abs_filter=True)

        elif len(fields) == 4:
            current_mode_title = f"Vektormező + Felület: {fields[0]},{fields[1]},{fields[2]}"
            U = clean_and_shape_3d(df[fields[0]].values, KVAL_CUT)
            V = clean_and_shape_3d(df[fields[1]].values, KVAL_CUT)
            W = clean_and_shape_3d(df[fields[2]].values, KVAL_CUT)
            vlen_raw = np.sqrt(df[fields[0]].values**2 + df[fields[1]].values**2 + df[fields[2]].values**2)
            Phi = clean_and_shape_3d(vlen_raw, KVAL_CUT, apply_abs_filter=True)

        elif len(fields) == 5:
            current_mode_title = f"Felület vektormezőből: {fields[0]},{fields[1]},{fields[2]}"
            U = clean_and_shape_3d(df[fields[0]].values, KVAL_CUT)
            V = clean_and_shape_3d(df[fields[1]].values, KVAL_CUT)
            W = clean_and_shape_3d(df[fields[2]].values, KVAL_CUT)
            vlen_raw = np.sqrt(df[fields[0]].values**2 + df[fields[1]].values**2 + df[fields[2]].values**2)
            Phi = clean_and_shape_3d(vlen_raw, KVAL_CUT, apply_abs_filter=True)

        phi_min, phi_max = float(Phi.min()), float(Phi.max())

        return True
##    except Exception as e:
##        print(f"Váratlan hiba a fájl beolvasásakor: {e}") #nem írja a hiba helyét
##        return False

if not load_and_process_data( fname=filename, field_text=fields_text):
    print("Kritikus hiba: Az indítófájl nem tölthető be. Kérlek ellenőrizd a {filename} meglétét.")
    exit()

init_level1 = phi_min + (phi_max - phi_min) * 0.35
init_level2 = phi_min + (phi_max - phi_min) * 0.65

fig = plt.figure(figsize=(10,10))
plt.subplots_adjust(bottom=0.28)  # Megemelt alsó margó a sok vezérlőnek
ax = fig.add_subplot(111, projection='3d')
ax.set_box_aspect([1, 1, 1])


def draw_surfaces_with_normals(level1, level2):
    global  phi_min, phi_max, current_mode
    ax.cla()

    def process_layer(level, face_color, edge_color, alpha):
        global  phi_min, phi_max, current_mode
        try:
            verts, faces, _, _ = measure.marching_cubes(Phi, level=level)
            x_r = np.interp(verts[:, 0], np.arange(X.shape[0]), X[:, 0, 0])
            y_r = np.interp(verts[:, 1], np.arange(X.shape[1]), Y[0, :, 0])
            z_r = np.interp(verts[:, 2], np.arange(X.shape[2]), Z[0, 0, :])
            scaled_verts = np.column_stack((x_r, y_r, z_r))

            if current_mode != 3 : # surface
                mesh = Poly3DCollection(scaled_verts[faces])
                mesh.set_facecolor(face_color);
                mesh.set_edgecolor(edge_color)
                mesh.set_alpha(alpha);
                mesh.set_linewidth(0.05)
                ax.add_collection3d(mesh)
            
            if current_mode != 1 and current_mode != 5 : # vectors
                step = 20
                face_centers = scaled_verts[faces[::step]].mean(axis=1)
                ix = np.clip(np.interp(face_centers[:, 0], X[:, 0, 0], np.arange(X.shape[0])).astype(int), 0, X.shape[0]-1)
                iy = np.clip(np.interp(face_centers[:, 1], Y[0, :, 0], np.arange(X.shape[1])).astype(int), 0, Y.shape[1]-1)
                iz = np.clip(np.interp(face_centers[:, 2], Z[0, 0, :], np.arange(X.shape[2])).astype(int), 0, Z.shape[2]-1)
                ax.quiver(face_centers[:, 0], face_centers[:, 1], face_centers[:, 2],
                      U[ix, iy, iz], V[ix, iy, iz], W[ix, iy, iz],
                      length= 1.8 * level / (phi_max-phi_min) + 1.2, normalize=True, color=edge_color, alpha=0.7, linewidth=1) # 
        except (ValueError, RuntimeError):
            pass

    process_layer(level1, 'royalblue', 'navy', 0.4)
    process_layer(level2, 'darkorange', 'chocolate', 0.4)

    ax.set_title(f'Fájl: "{filename}" | Mód: {current_mode_title}\n'
                 f'Min = {phi_min} | Max = {phi_max}')
    ax.set_xlabel('X'); ax.set_ylabel('Y'); ax.set_zlabel('Z')
    ax.set_xlim(min_x, max_x); ax.set_ylim(min_y, max_y); ax.set_zlim(min_z, max_z)
    
draw_surfaces_with_normals(init_level1, init_level2)

ax_phi1 = plt.axes([0.25, 0.16, 0.6, 0.02])
ax_phi2 = plt.axes([0.25, 0.12, 0.6, 0.02])
ax_fields_box = plt.axes([0.25, 0.08, 0.6, 0.03])
ax_file_btn = plt.axes([0.25, 0.04, 0.6, 0.03]) # Új gomb pozíciója a régi mező helyén

s_phi1 = Slider(ax_phi1, 'Kék szint ($\Phi_1$)', phi_min, phi_max, valinit=init_level1, dragging=False, color='royalblue')
s_phi2 = Slider(ax_phi2, 'Narancs szint ($\Phi_2$)', phi_min, phi_max, valinit=init_level2, dragging=False, color='darkorange')

fields_textbox = TextBox(ax_fields_box, 'Mező(k) nevei: ', initial=fields_text)
file_button = Button(ax_file_btn, 'Új CSV fájl megnyitása...', color='lightgray', hovercolor='gainsboro')

def refresh_interface_and_draw():
    lvl1 = phi_min + (phi_max - phi_min) * 0.35
    lvl2 = phi_min + (phi_max - phi_min) * 0.65
    
    s_phi1.valmin = phi_min; s_phi1.valmax = phi_max
    s_phi1.ax.set_xlim(phi_min, phi_max); s_phi1.set_val(lvl1)
    
    s_phi2.valmin = phi_min; s_phi2.valmax = phi_max
    s_phi2.ax.set_xlim(phi_min, phi_max); s_phi2.set_val(lvl2)
    fig.canvas.draw_idle()

def update_sliders(val):
    draw_surfaces_with_normals(s_phi1.val, s_phi2.val)
    fig.canvas.draw_idle()

s_phi1.on_changed(update_sliders)
s_phi2.on_changed(update_sliders)

def on_fields_submit(text):
    if load_and_process_data( field_text = text.strip() ):
        refresh_interface_and_draw()

fields_textbox.on_submit(on_fields_submit)

def on_file_button_clicked(event):
    selected_file = filedialog.askopenfilename(
        title="Válassz ki egy adatsort (54x54x54 CSV)",
        filetypes=[("CSV fájlok", "*.csv"), ("Minden fájl", "*.*")]
    )
    if selected_file:
        if load_and_process_data(fname = selected_file):
            refresh_interface_and_draw()

file_button.on_clicked(on_file_button_clicked)

plt.show()