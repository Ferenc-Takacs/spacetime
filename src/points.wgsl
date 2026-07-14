
struct MetricPoint {
    g00: f32, g11: f32, g22: f32, g33: f32,
    g01: f32, g02: f32, g03: f32,
    g12: f32, g13: f32,
    g23: f32,
    padding1: f32,
    padding2: f32,
}

// Uniform buffer a rács méreteinek átadására (hogy ne legyenek beégetett számok)
struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dx: f32,
}

@group(0) @binding(0) var<uniform> dims: GridDimensions;
@group(0) @binding(1) var<storage, read> input_grid: array<MetricPoint>;
@group(0) @binding(2) var<storage, read_write> output_kret: array<f32>;

// Kényelmi függvény: 3D koordinátákból kiszámolja a folytonos 1D memóriaindexet
fn get_index(x: u32, y: u32, z: u32) -> u32 {
    return x + (y * dims.width) + (z * dims.width * dims.height);
}

// Biztonságos lekérdezés peremvédelemmel (Clamping)
// Ha túlcsordulna a szélén, a legszélső érvényes pontot adja vissza (Neumann-féle peremfeltétel)
fn get_metric_at(x: i32, y: i32, z: i32) -> MetricPoint {
    let cl_x = u32(clamp(x, 0, i32(dims.width) - 1));
    let cl_y = u32(clamp(y, 0, i32(dims.height) - 1));
    let cl_z = u32(clamp(z, 0, i32(dims.depth) - 1));
    
    let idx = get_index(cl_x, cl_y, cl_z);
    return input_grid[idx];
}

// A felső indexes metrika tárolására (szintén szimmetrikus, 10 komponens)
struct InverseMetric {
    g00: f32, g11: f32, g22: f32, g33: f32,
    g01: f32, g02: f32, g03: f32,
    g12: f32, g13: f32, g23: f32,
}

// Segédfüggvény: egy 3x3-as mátrix determinánsának kiszámítása (Sarrus-szabály)
fn det3x3(m00: f32, m01: f32, m02: f32,
          m10: f32, m11: f32, m12: f32,
          m20: f32, m21: f32, m22: f32) -> f32 {
    return m00 * (m11 * m22 - m12 * m21) 
         - m01 * (m10 * m22 - m12 * m20) 
         + m02 * (m10 * m21 - m11 * m20);
}

struct ChristoffelAndInverse {
    ch: Christoffel40,
    g_inv: InverseMetric,
}

// FŐ INVERTÁLÓ FÜGGVÉNY: Elvégzi a 4x4-es nem-diagonális invertálást
fn invert_metric(p: MetricPoint) -> InverseMetric {
    // 1. Felépítjük a teljes 4x4-es mátrixot a szimmetria figyelembevételével
    // Sorok és oszlopok: 0: t, 1: x, 2: y, 3: z
    let m00 = p.g00; let m01 = p.g01; let m02 = p.g02; let m03 = p.g03;
    let m10 = p.g01; let m11 = p.g11; let m12 = p.g12; let m13 = p.g13;
    let m20 = p.g02; let m21 = p.g12; let m22 = p.g22; let m23 = p.g23;
    let m30 = p.g03; let m31 = p.g13; let m32 = p.g23; let m33 = p.g33;

    // 2. Kiszámoljuk a 4x4-es determinánst a 0. sor szerinti kifejtéssel
    let det = m00 * det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33)
            - m01 * det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33)
            + m02 * det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33)
            - m03 * det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32);

    // Biztonsági ellenőrzés szingularitás esetére (pl. koordináta-szingularitás)
    var inv_det = 0.0;
    if (abs(det) > 1e-9) {
        inv_det = 1.0 / det;
    }
    var inv: InverseMetric;

    // 3. Kiszámoljuk a 10 független felső indexes komponenst az aldeterminánsokkal (Cramer-szabály)
    // Figyelni kell a sakktábla-szabály szerinti előjelekre (-1)^(i+j)
    inv.g00 =  det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33) * inv_det;
    inv.g11 =  det3x3(m00, m02, m03, m20, m22, m23, m30, m32, m33) * inv_det;
    inv.g22 =  det3x3(m00, m01, m03, m10, m11, m13, m30, m31, m33) * inv_det;
    inv.g33 =  det3x3(m00, m01, m02, m10, m11, m12, m20, m21, m22) * inv_det;

    inv.g01 = -det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33) * inv_det;
    inv.g02 =  det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33) * inv_det;
    inv.g03 = -det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32) * inv_det;
    
    inv.g12 = -det3x3(m00, m01, m03, m20, m21, p.g23, m30, m31, m33) * inv_det; // Hibajavított indexekkel ?????
    inv.g13 =  det3x3(m00, m01, m02, m20, m21, m22, m30, m31, m32) * inv_det;
    inv.g23 = -det3x3(m00, m01, m02, m10, m11, m12, m30, m31, m32) * inv_det;

    return inv;
}

struct Riemann20 {
    // 1. Tiszta bindex átlós elemek (6 darab)
    R0101: f32, R0202: f32, R0303: f32,
    R1212: f32, R1313: f32, R2323: f32,

    // 2. Kereszt-tagok az idő-tér blokkok között (9 darab)
    R0102: f32, R0103: f32, R0203: f32,
    R0112: f32, R0113: f32, R0212: f32,
    R0223: f32, R0313: f32, R0323: f32,

    // 3. Tiszta térbeli kereszt-tagok és vegyes elemek (5 darab)
    R1213: f32, R1223: f32, R1323: f32,
    R0123: f32, R0213: f32 
    // Megjegyzés: R0312 az első Bianchi-azonosság miatt kiszámolható: -R0123 - R0213
}


fn deriv_gamma(cx: i32, cy: i32, cz: i32, L: u32, M: u32, N: u32, dir: u32) -> f32 {
    var packed_plus: Christoffel40;
    var packed_minus: Christoffel40;

    if (dir == 1u) {
        packed_plus  = get_christoffel_at(cx + 1, cy, cz).ch;
        packed_minus = get_christoffel_at(cx - 1, cy, cz).ch;
    }
    else if (dir == 2u) {
        packed_plus  = get_christoffel_at(cx, cy + 1, cz).ch;
        packed_minus = get_christoffel_at(cx, cy - 1, cz).ch;
    }
    else { // if (dir == 3u) {
        packed_plus  = get_christoffel_at(cx, cy, cz + 1).ch;
        packed_minus = get_christoffel_at(cx, cy, cz - 1).ch;
    }

    let val_plus  = extract_gamma(packed_plus, L, M, N);
    let val_minus = extract_gamma(packed_minus, L, M, N);
    
    return (val_plus - val_minus) / (2.0 * dims.dx);
}



fn compute_riemann_20(cx: i32, cy: i32, cz: i32, g: MetricPoint) -> Riemann20 {
    var R: Riemann20;
    
    // A lokális Christoffel-szimbólumok a nem-lineáris szorzatokhoz (Gamma * Gamma)
    let ch = get_christoffel_at(cx, cy, cz).ch;

    // BELSŐ SEGÉDFÜGGVÉNY: Kiszámolja R^lambda_{mu nu rho} egy konkrét kombinációját
    // Riemann formula: d_nu(Gamma^L_mu_rho) - d_rho(Gamma^L_mu_nu) + Gamma * Gamma tagok
    // Itt a parciális deriváltakat (d_nu, d_rho) a fenti szomszéd-lekérdezések adják
    
    // Példaként nézzünk meg egy teljesen kifejtett független komponenst: R_0101
    // Ehhez először ki kell számítani R^L_101 elemeket L = 0, 1, 2, 3-ra
    var R_up_0101 = vec4<f32>(0.0);
    for (var L = 0u; L < 4u; L++) {
        // d_0 Gamma^L_11 - d_1 Gamma^L_10 + kontrahált szorzatok
        // Mivel d_0 (időderivált) kezdetben 0, csak a térbeli d_1 derivált él:
        let term_deriv = -deriv_gamma(cx, cy, cz, L, 1u, 0u, 1u); 
        
        // Gamma^L_s0 * Gamma^s_11 - Gamma^s_11 * Gamma^L_s1 szorzatösszegzés s-re
        var term_nonlinear = 0.0;
        for (var s = 0u; s < 4u; s++) {
            term_nonlinear += extract_gamma(ch, L, s, 0u) * extract_gamma(ch, s, 1u, 1u)
                            - extract_gamma(ch, L, s, 1u) * extract_gamma(ch, s, 1u, 0u);
        }
        
        R_up_0101[L] = term_deriv + term_nonlinear;
    }
    
    // Index leengedése a metrikával: R_0101 = g_0L * R^L_101
    // Felhasználjuk a metrika komponenseit (figyelve a kereszt-tagokra is, ha nem-diagonális!)
    R.R0101 = g.g00 * R_up_0101[0] + g.g01 * R_up_0101[1] + g.g02 * R_up_0101[2] + g.g03 * R_up_0101[3];

    // ... Ezt a sémát ismételjük meg a maradék 19 független komponensre ... ????
    // Például R_0202-höz R^L_202 kell, leengedve g_0L-lel.
    // R_1212-höz R^L_212 kell, leengedve g_1L-lel.

    return R;
}

struct Christoffel40 {
    // Minden felső indexhez (L = 0..3) tartozik egy vec4 az átlós és a fő kereszt-tagoknak,
    // és egy vec2 a maradék kereszt-tagoknak.
    L0_diag: vec4<f32>, L0_cross: vec4<f32>, L0_rest: vec2<f32>,
    L1_diag: vec4<f32>, L1_cross: vec4<f32>, L1_rest: vec2<f32>,
    L2_diag: vec4<f32>, L2_cross: vec4<f32>, L2_rest: vec2<f32>,
    L3_diag: vec4<f32>, L3_cross: vec4<f32>, L3_rest: vec2<f32>,
}

// Kényelmi függvény: Kicsomagolja a 40 komponensből a kívánt Gamma^L_MN értéket
fn extract_gamma(ch: Christoffel40, L: u32, M: u32, N: u32) -> f32 {
    // Biztosítjuk a szimmetriát: a kisebb index legyen elöl (M <= N)
    var u = M;
    var v = N;
    if (M > N) {
        u = N;
        v = M;
    }

    // Kiválasztjuk a megfelelő felső index (L) blokkját
    var diag = vec4<f32>(0.0);
    var cross = vec4<f32>(0.0);
    var rest = vec2<f32>(0.0);

    if (L == 0u) { diag = ch.L0_diag; cross = ch.L0_cross; rest = ch.L0_rest; }
    else if (L == 1u) { diag = ch.L1_diag; cross = ch.L1_cross; rest = ch.L1_rest; }
    else if (L == 2u) { diag = ch.L2_diag; cross = ch.L2_cross; rest = ch.L2_rest; }
    else { diag = ch.L3_diag; cross = ch.L3_cross; rest = ch.L3_rest; }

    // Kikeresés a bevezetett 0..9-es belső indexelési térkép alapján
    if (u == 0u && v == 0u) { return diag.x; } // (0,0)
    if (u == 1u && v == 1u) { return diag.y; } // (1,1)
    if (u == 2u && v == 2u) { return diag.z; } // (2,2)
    if (u == 3u && v == 3u) { return diag.w; } // (3,3)
    
    if (u == 0u && v == 1u) { return cross.x; } // (0,1)
    if (u == 0u && v == 2u) { return cross.y; } // (0,2)
    if (u == 0u && v == 3u) { return cross.z; } // (0,3)
    if (u == 1u && v == 2u) { return cross.w; } // (1,2)

    if (u == 1u && v == 3u) { return rest.x; } // (1,3)
    if (u == 2u && v == 3u) { return rest.y; } // (2,3)

    return 0.0;
}


fn get_christoffel_at(cx: i32, cy: i32, cz: i32) -> ChristoffelAndInverse {
    let dx = dims.dx;
    // 1. Beolvassuk a lokális metrikát és kiszámoljuk az inverzét
    let p_center = get_metric_at(cx, cy, cz);
    let g_inv_local = invert_metric(p_center); // <-- Ez az egyetlen inverz számítás!

    // 2. Beolvassuk a 6 szomszédos metrikát a parciális deriváláshoz
    let p_x_plus  = get_metric_at(cx + 1, cy, cz);
    let p_x_minus = get_metric_at(cx - 1, cy, cz);
    let p_y_plus  = get_metric_at(cx, cy + 1, cz);
    let p_y_minus = get_metric_at(cx, cy - 1, cz);
    let p_z_plus  = get_metric_at(cx, cy, cz + 1);
    let p_z_minus = get_metric_at(cx, cy, cz - 1);

    var ch: Christoffel40;
    
    // 3. Végrehajtjuk a 40 Christoffel komponens kiszámítását
    for (var L = 0u; L < 4u; L++) {
        var temp_diag = vec4<f32>(0.0); var temp_cross = vec4<f32>(0.0); var temp_rest = vec2<f32>(0.0);

        for (var k = 0u; k < 10u; k++) {
            // ... M és N indexek beállítása k alapján ...
            var val = 0.0;
            for (var sig = 0u; sig < 4u; sig++) {
                // Felhasználjuk a helyben kiszámított g_inv_local-t
                let inv_g_L_sig = extract_inv_metric_element(g_inv_local, L, sig); // ?????

                let dM_gNsig = get_deriv(M, N, sig, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus, dx); // ?????
                let dN_gMsig = get_deriv(N, M, sig, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus, dx);
                let dsig_gMN = get_deriv(sig, M, N, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus, dx);

                val += 0.5 * inv_g_L_sig * (dM_gNsig + dN_gMsig - dsig_gMN);
            }
            // ... mentés a temp vektorokba ...
        }
        // ... vektorok hozzárendelése ch-hoz ...
    }

    // 4. VISSZAADÁS: Becsomagoljuk a Christoffel-szimbólumokat ÉS az inverz metrikát is!
    var result: ChristoffelAndInverse;
    result.ch = ch;
    result.g_inv = g_inv_local;
    return result;
}


fn compute_ricci(R_tensor: Riemann20, g_inv: InverseMetric) -> Ricci10 {
    var Rc: Ricci10;
    
    // BELSŐ HELP FÜGGVÉNY: Egy konkrét (mu, nu) Ricci komponens kontrakciója alpha és beta szerint
    // Rc_{mu, nu} = sum_{a, b} g^ab * R_{a, mu, b, nu}
    // A szimmetria miatt ezt egy fix mintával kódoljuk le a shadernek:
    
    // Példa: R00 kiszámítása
    Rc.R00 = g_inv.g00 * extract_r4(R_tensor, 0u, 0u, 0u, 0u) // Ez fixen 0 az antiszimmetria miatt, de az általánosságért felírjuk
           + g_inv.g11 * extract_r4(R_tensor, 1u, 0u, 1u, 0u)
           + g_inv.g22 * extract_r4(R_tensor, 2u, 0u, 2u, 0u)
           + g_inv.g33 * extract_r4(R_tensor, 3u, 0u, 3u, 0u)
           + 2.0 * g_inv.g01 * extract_r4(R_tensor, 0u, 0u, 1u, 0u)
           + 2.0 * g_inv.g02 * extract_r4(R_tensor, 0u, 0u, 2u, 0u)
           + 2.0 * g_inv.g03 * extract_r4(R_tensor, 0u, 0u, 3u, 0u)
           + 2.0 * g_inv.g12 * extract_r4(R_tensor, 1u, 0u, 2u, 0u)
           + 2.0 * g_inv.g13 * extract_r4(R_tensor, 1u, 0u, 3u, 0u)
           + 2.0 * g_inv.g23 * extract_r4(R_tensor, 2u, 0u, 2u, 0u);

    // Ezt a sémát ismételjük meg a többi 9 komponensre a shaderben: ?????
    // Rc.R11-hez a Riemann belső indexei (a, 1, b, 1) lesznek, és így tovább...
    // (A GPU ezt a 10 blokkot teljesen lineárisan, elágazásmentesen hajtja végre)
    
    // ... Rc.R22, Rc.R33, Rc.R01, Rc.R02, Rc.R03, Rc.R12, Rc.R13, Rc.R23 feltöltése ...

    return Rc;
}


// A RICCI-SKALÁR (R) KISZÁMÍTÁSA
fn compute_ricci_scalar(Rc: Ricci10, g_inv: InverseMetric) -> f32 {
    return g_inv.g00 * Rc.R00 + g_inv.g11 * Rc.R11 + g_inv.g22 * Rc.R22 + g_inv.g33 * Rc.R33
         + 2.0 * (g_inv.g01 * Rc.R01 + g_inv.g02 * Rc.R02 + g_inv.g03 * Rc.R03
                + g_inv.g12 * Rc.R12 + g_inv.g13 * Rc.R13 + g_inv.g23 * Rc.R23);
}


fn compute_kretschmann(R: Riemann20) -> f32 {
    // Az átlós elemek 4-szeres súlyt kapnak (az indexek felcserélhetősége miatt)
    let diagonal = 4.0 * (R.R0101*R.R0101 + R.R0202*R.R0202 + R.R0303*R.R0303 +
                          R.R1212*R.R1212 + R.R1313*R.R1313 + R.R2323*R.R2323);
                          
    // A kereszt-tagok 8-szoros vagy 16-szoros súlyozást kapnak a permutációktól függően
    let vegyes = 8.0 * (R.R0102*R.R0102 + R.R0103*R.R0103 + R.R0203*R.R0203)
               + 16.0 * (R.R0112*R.R0112 + R.R0113*R.R0113 + R.R0212*R.R0212 +
                         R.R0223*R.R0223 + R.R0313*R.R0313 + R.R0323*R.R0323);
                         
    let tiszta_ter = 8.0 * (R.R1213*R.R1213 + R.R1223*R.R1223 + R.R1323*R.R1323)
                   + 16.0 * (R.R0123*R.R0123 + R.R0213*R.R0213);

    return diagonal + vegyes + tiszta_ter;
}


@compute @workgroup_size(4, 4, 4)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Biztonsági ellenőrzés: ha a munkafolyamat túlnyúlik a rács méretén, lépjen ki
    if (id.x >= dims.width || id.y >= dims.height || id.z >= dims.depth) {
        return;
    }
    // A jelenlegi pont 3D koordinátái előjeles egészként a léptetéshez
    let cx = i32(id.x);
    let cy = i32(id.y);
    let cz = i32(id.z);
    let ch_inv = get_christoffel_at(cx, cy, cz);
    let R_tensor = compute_riemann_20(cx, cy, cz, ch_inv.ch, dx);
    let Rc_tensor = compute_ricci(R_tensor, ch_inv.g_inv);
    let R_scalar = compute_ricci_scalar(Rc_tensor, ch_inv.g_inv);
    let K_scalar = compute_kretschmann(R_tensor);
    let C2_scalar = compute_weyl_squared(K_scalar, Rc_tensor, ch_inv.g_inv, R_scalar);

    // MÓDOSÍTOTT EGYENLET KIÉRTÉKELÉSE:
    let brackets = 0.5 * ( R_scalar + sqrt(K_scalar) ) + sqrt(C2_scalar);
    
    // ... Energia impulzus tenzor hozzáadása (ha van) ?????
    // ... új g, és R tenzor kiszámítása ... ?????
    // ... mentés az output_bufferbe ... ?????
    // Egyelőre tesztként mentsük el az x-irányú deriváltat a kimeneti bufferbe
    let current_1d_index = get_index(id.x, id.y, id.z);
    output_kret[current_1d_index] = brackets;
}

