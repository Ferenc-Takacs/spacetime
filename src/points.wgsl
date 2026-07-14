struct MetricPoint {
    g00: f32, g11: f32, g22: f32, g33: f32,
    g01: f32, g02: f32, g03: f32,
    g12: f32, g13: f32, g23: f32,
    padding1: f32,
    padding2: f32,
}

struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dx: f32, // A korábbi padding helyén, így globálisan elérhető!
}

struct InverseMetric {
    g00: f32, g11: f32, g22: f32, g33: f32,
    g01: f32, g02: f32, g03: f32,
    g12: f32, g13: f32, g23: f32,
}

struct Christoffel40 {
    L0_diag: vec4<f32>, L0_cross: vec4<f32>, L0_rest: vec2<f32>,
    L1_diag: vec4<f32>, L1_cross: vec4<f32>, L1_rest: vec2<f32>,
    L2_diag: vec4<f32>, L2_cross: vec4<f32>, L2_rest: vec2<f32>,
    L3_diag: vec4<f32>, L3_cross: vec4<f32>, L3_rest: vec2<f32>,
}

// Az összevont struktúra az általad javasolt optimalizáláshoz!
struct ChristoffelAndInverse {
    ch: Christoffel40,
    g_inv: InverseMetric,
}

struct Riemann20 {
    R0101: f32, R0202: f32, R0303: f32,
    R1212: f32, R1313: f32, R2323: f32,

    R0102: f32, R0103: f32, R0203: f32,
    R0112: f32, R0113: f32, R0212: f32,
    R0223: f32, R0313: f32, R0323: f32,

    R1213: f32, R1223: f32, R1323: f32,
    R0123: f32, R0213: f32,
}

struct Ricci10 {
    R00: f32, R11: f32, R22: f32, R33: f32,
    R01: f32, R02: f32, R03: f32,
    R12: f32, R13: f32, R23: f32,
}

@group(0) @binding(0) var<uniform> dims: GridDimensions;
@group(0) @binding(1) var<storage, read> input_grid: array<MetricPoint>;
@group(0) @binding(2) var<storage, read_write> output_kret: array<f32>;

fn get_index(x: u32, y: u32, z: u32) -> u32 {
    return x + (y * dims.width) + (z * dims.width * dims.height);
}

fn get_metric_at(x: i32, y: i32, z: i32) -> MetricPoint {
    let cl_x = u32(clamp(x, 0, i32(dims.width) - 1));
    let cl_y = u32(clamp(y, 0, i32(dims.height) - 1));
    let cl_z = u32(clamp(z, 0, i32(dims.depth) - 1));
    return input_grid[get_index(cl_x, cl_y, cl_z)];
}

// 4x4-es inverz metrika kiszámítása (Cramer-szabály)
fn det3x3(m00: f32, m01: f32, m02: f32, m10: f32, m11: f32, m12: f32, m20: f32, m21: f32, m22: f32) -> f32 {
    return m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02 * (m10 * m21 - m11 * m20);
}

fn invert_metric(p: MetricPoint) -> InverseMetric {
    let m00 = p.g00; let m01 = p.g01; let m02 = p.g02; let m03 = p.g03;
    let m10 = p.g01; let m11 = p.g11; let m12 = p.g12; let m13 = p.g13;
    let m20 = p.g02; let m21 = p.g12; let m22 = p.g22; let m23 = p.g23;
    let m30 = p.g03; let m31 = p.g13; let m32 = p.g23; let m33 = p.g33;

    let det = m00 * det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33)
            - m01 * det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33)
            + m02 * det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33)
            - m03 * det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32);

    var inv_det = 0.0;
    if (abs(det) > 1e-9) { inv_det = 1.0 / det; }

    var inv: InverseMetric;
    inv.g00 =  det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33) * inv_det;
    inv.g11 =  det3x3(m00, m02, m03, m20, m22, m23, m30, m32, m33) * inv_det;
    inv.g22 =  det3x3(m00, m01, m03, m10, m11, m13, m30, m31, m33) * inv_det;
    inv.g33 =  det3x3(m00, m01, m02, m10, m11, m12, m20, m21, m22) * inv_det;
    inv.g01 = -det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33) * inv_det;
    inv.g02 =  det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33) * inv_det;
    inv.g03 = -det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32) * inv_det;
    inv.g12 = -det3x3(m00, m02, m03, m10, m12, m13, m30, m32, m33) * inv_det;
    inv.g13 =  det3x3(m00, m01, m03, m10, m11, m13, m20, m21, m23) * inv_det;
    inv.g23 = -det3x3(m00, m01, m02, m10, m11, m12, m30, m31, m32) * inv_det;
    return inv;
}

fn extract_metric_element(p: MetricPoint, a: u32, b: u32) -> f32 {
    var u = a; var v = b; if (a > b) { u = b; v = a; }
    if (u == 0u && v == 0u) { return p.g00; } if (u == 1u && v == 1u) { return p.g11; }
    if (u == 2u && v == 2u) { return p.g22; } if (u == 3u && v == 3u) { return p.g33; }
    if (u == 0u && v == 1u) { return p.g01; } if (u == 0u && v == 2u) { return p.g02; }
    if (u == 0u && v == 3u) { return p.g03; } if (u == 1u && v == 2u) { return p.g12; }
    if (u == 1u && v == 3u) { return p.g13; } if (u == 2u && v == 3u) { return p.g23; }
    return 0.0;
}

fn get_deriv(mu: u32, a: u32, b: u32, p_x_plus: MetricPoint, p_x_minus: MetricPoint, p_y_plus: MetricPoint, p_y_minus: MetricPoint, p_z_plus: MetricPoint, p_z_minus: MetricPoint) -> f32 {
    if (mu == 0u) { return 0.0; }
    var val_plus = 0.0; var val_minus = 0.0;
    if (mu == 1u) { val_plus = extract_metric_element(p_x_plus, a, b); val_minus = extract_metric_element(p_x_minus, a, b); }
    else if (mu == 2u) { val_plus = extract_metric_element(p_y_plus, a, b); val_minus = extract_metric_element(p_y_minus, a, b); }
    else if (mu == 3u) { val_plus = extract_metric_element(p_z_plus, a, b); val_minus = extract_metric_element(p_z_minus, a, b); }
    return (val_plus - val_minus) / (2.0 * dims.dx);
}

fn extract_inv_metric_element(g_inv: InverseMetric, a: u32, b: u32) -> f32 {
    var u = a; var v = b; if (a > b) { u = b; v = a; }
    if (u == 0u && v == 0u) { return g_inv.g00; } if (u == 1u && v == 1u) { return g_inv.g11; }
    if (u == 2u && v == 2u) { return g_inv.g22; } if (u == 3u && v == 3u) { return g_inv.g33; }
    if (u == 0u && v == 1u) { return g_inv.g01; } if (u == 0u && v == 2u) { return g_inv.g02; }
    if (u == 0u && v == 3u) { return g_inv.g03; } if (u == 1u && v == 2u) { return g_inv.g12; }
    if (u == 1u && v == 3u) { return g_inv.g13; } if (u == 2u && v == 3u) { return g_inv.g23; }
    return 0.0;
}

fn extract_gamma(ch: Christoffel40, L: u32, M: u32, N: u32) -> f32 {
    var u = M; var v = N; if (M > N) { u = N; v = M; }
    var diag = vec4<f32>(0.0); var cross = vec4<f32>(0.0); var rest = vec2<f32>(0.0);
    if (L == 0u) { diag = ch.L0_diag; cross = ch.L0_cross; rest = ch.L0_rest; }
    else if (L == 1u) { diag = ch.L1_diag; cross = ch.L1_cross; rest = ch.L1_rest; }
    else if (L == 2u) { diag = ch.L2_diag; cross = ch.L2_cross; rest = ch.L2_rest; }
    else { diag = ch.L3_diag; cross = ch.L3_cross; rest = ch.L3_rest; }
    if (u == 0u && v == 0u) { return diag.x; } if (u == 1u && v == 1u) { return diag.y; }
    if (u == 2u && v == 2u) { return diag.z; } if (u == 3u && v == 3u) { return diag.w; }
    if (u == 0u && v == 1u) { return cross.x; } if (u == 0u && v == 2u) { return cross.y; }
    if (u == 0u && v == 3u) { return cross.z; } if (u == 1u && v == 2u) { return cross.w; }
    if (u == 1u && v == 3u) { return rest.x; } if (u == 2u && v == 3u) { return rest.y; }
    return 0.0;
}

fn get_christoffel_at(cx: i32, cy: i32, cz: i32) -> ChristoffelAndInverse {
    let p_center = get_metric_at(cx, cy, cz);
    let g_inv_local = invert_metric(p_center);
    let p_x_plus  = get_metric_at(cx + 1, cy, cz); let p_x_minus = get_metric_at(cx - 1, cy, cz);
    let p_y_plus  = get_metric_at(cx, cy + 1, cz); let p_y_minus = get_metric_at(cx, cy - 1, cz);
    let p_z_plus  = get_metric_at(cx, cy, cz + 1); let p_z_minus = get_metric_at(cx, cy, cz - 1);

    var ch: Christoffel40;
    for (var L = 0u; L < 4u; L++) {
        var temp_diag = vec4<f32>(0.0); var temp_cross = vec4<f32>(0.0); var temp_rest = vec2<f32>(0.0);
        for (var k = 0u; k < 10u; k++) {
            var M = 0u; var N = 0u;
            if (k == 0u) { M = 0u; N = 0u; } else if (k == 1u) { M = 1u; N = 1u; }
            else if (k == 2u) { M = 2u; N = 2u; } else if (k == 3u) { M = 3u; N = 3u; }
            else if (k == 4u) { M = 0u; N = 1u; } else if (k == 5u) { M = 0u; N = 2u; }
            else if (k == 6u) { M = 0u; N = 3u; } else if (k == 7u) { M = 1u; N = 2u; }
            else if (k == 8u) { M = 1u; N = 3u; } else { M = 2u; N = 3u; }

            var val = 0.0;
            for (var sig = 0u; sig < 4u; sig++) {
                let inv_g_L_sig = extract_inv_metric_element(g_inv_local, L, sig);
                let dM_gNsig = get_deriv(M, N, sig, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
                let dN_gMsig = get_deriv(N, M, sig, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
                let dsig_gMN = get_deriv(sig, M, N, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
                val += 0.5 * inv_g_L_sig * (dM_gNsig + dN_gMsig - dsig_gMN);
            }
            if (k == 0u) { temp_diag.x = val; } else if (k == 1u) { temp_diag.y = val; }
            else if (k == 2u) { temp_diag.z = val; } else if (k == 3u) { temp_diag.w = val; }
            else if (k == 4u) { temp_cross.x = val; } else if (k == 5u) { temp_cross.y = val; }
            else if (k == 6u) { temp_cross.z = val; } else if (k == 7u) { temp_cross.w = val; }
            else if (k == 8u) { temp_rest.x = val; } else { temp_rest.y = val; }
        }
        if (L == 0u) { ch.L0_diag = temp_diag; ch.L0_cross = temp_cross; ch.L0_rest = temp_rest; }
        else if (L == 1u) { ch.L1_diag = temp_diag; ch.L1_cross = temp_cross; ch.L1_rest = temp_rest; }
        else if (L == 2u) { ch.L2_diag = temp_diag; ch.L2_cross = temp_cross; ch.L2_rest = temp_rest; }
        else { ch.L3_diag = temp_diag; ch.L3_cross = temp_cross; ch.L3_rest = temp_rest; }
    }
    var result: ChristoffelAndInverse; result.ch = ch; result.g_inv = g_inv_local; return result;
}

fn deriv_gamma(cx: i32, cy: i32, cz: i32, L: u32, M: u32, N: u32, dir: u32) -> f32 {
    var packed_plus: ChristoffelAndInverse; var packed_minus: ChristoffelAndInverse;
    if (dir == 1u) { packed_plus = get_christoffel_at(cx + 1, cy, cz); packed_minus = get_christoffel_at(cx - 1, cy, cz); }
    else if (dir == 2u) { packed_plus = get_christoffel_at(cx, cy + 1, cz); packed_minus = get_christoffel_at(cx, cy - 1, cz); }
    else { packed_plus = get_christoffel_at(cx, cy, cz + 1); packed_minus = get_christoffel_at(cx, cy, cz - 1); }
    return (extract_gamma(packed_plus.ch, L, M, N) - extract_gamma(packed_minus.ch, L, M, N)) / (2.0 * dims.dx);
}


fn get_riemann_element(cx: i32, cy: i32, cz: i32, ch: Christoffel40, L: u32, M: u32, N: u32, nu: u32) -> f32 {
    let term_deriv = deriv_gamma(cx, cy, cz, L, M, nu, N) - deriv_gamma(cx, cy, cz, L, M, N, nu);
    var term_nonlinear = 0.0;
    for (var s = 0u; s < 4u; s++) {
        term_nonlinear += extract_gamma(ch, L, s, N) * extract_gamma(ch, s, M, nu) - extract_gamma(ch, L, s, nu) * extract_gamma(ch, s, M, N);
    }
    return term_deriv + term_nonlinear;
}

fn compute_riemann_20(cx: i32, cy: i32, cz: i32, ch: Christoffel40, g: MetricPoint) -> Riemann20 {
    var R: Riemann20;
    // Segéd-vektorok az index leengedéséhez (R_abcd = g_am * R^m_bcd)
    var R_up = vec4(0.0);
    // 1. Blokk: Tiszta átlós bindex elemek
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,1u,0u,1u); }
    R.R0101 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,0u,2u); }
    R.R0202 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,3u,0u,3u); }
    R.R0303 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,1u,2u); }
    R.R1212 = g.g01 * R_up.x + g.g11 * R_up.y + g.g12 * R_up.z + g.g13 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,3u,1u,3u); }
    R.R1313 = g.g01 * R_up.x + g.g11 * R_up.y + g.g12 * R_up.z + g.g13 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,3u,2u,3u); }
    R.R2323 = g.g02 * R_up.x + g.g12 * R_up.y + g.g22 * R_up.z + g.g23 * R_up.w;
    // 2. Blokk: Kereszt-tagok
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,1u,0u,2u); }
    R.R0102 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,1u,0u,3u); }
    R.R0103 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,0u,3u); }
    R.R0203 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,1u,1u,2u); }
    R.R0112 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,1u,1u,3u); }
    R.R0113 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,1u,2u); }
    R.R0212 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,2u,3u); }
    R.R0223 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,3u,1u,3u); }
    R.R0313 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,3u,2u,3u); }
    R.R0323 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    // 3. Blokk: Térbeli vegyes tagok
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,1u,3u); }
    R.R1213 = g.g01 * R_up.x + g.g11 * R_up.y + g.g12 * R_up.z + g.g13 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,2u,3u); }
    R.R1223 = g.g01 * R_up.x + g.g11 * R_up.y + g.g12 * R_up.z + g.g13 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,3u,2u,3u); }
    R.R1323 = g.g01 * R_up.x + g.g11 * R_up.y + g.g12 * R_up.z + g.g13 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,1u,2u,3u); }
    R.R0123 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    for(var m=0u; m<4u; m++){ R_up[m] = get_riemann_element(cx,cy,cz,ch,m,2u,1u,3u); }
    R.R0213 = g.g00 * R_up.x + g.g01 * R_up.y + g.g02 * R_up.z + g.g03 * R_up.w;
    return R;
}

fn compute_kretschmann(R: Riemann20) -> f32 {
    let diagonal = 4.0 * (R.R0101 * R.R0101 + R.R0202 * R.R0202 + R.R0303 * R.R0303 + R.R1212 * R.R1212 + R.R1313 * R.R1313 + R.R2323 * R.R2323);
    let vegyes = 8.0 * (R.R0102 * R.R0102 + R.R0103 * R.R0103 + R.R0203 * R.R0203) + 16.0 * (R.R0112 * R.R0112 + R.R0113 * R.R0113 + R.R0212 * R.R0212 + R.R0223 * R.R0223 + R.R0313 * R.R0313 + R.R0323 * R.R0323);
    let tiszta_ter = 8.0 * (R.R1213 * R.R1213 + R.R1223 * R.R1223 + R.R1323 * R.R1323) + 16.0 * (R.R0123 * R.R0123 + R.R0213 * R.R0213);
    return diagonal + vegyes + tiszta_ter;
}

fn extract_r4(R: Riemann20, a: u32, b: u32, c: u32, d: u32) -> f32 {
    if (a == b || c == d) { return 0.0; }
    var sign = 1.0;
    var x = a;
    var y = b;
    if (x > y) { x = b; y = a; sign = -sign; }
    var w = c;
    var z = d;
    if (w > z) { w = d; z = c; sign = -sign; }
    var p1 = 0u;
    if(x==0u&&y==2u){p1=1u;}
    else if(x==0u&&y==3u){p1=2u;}
    else if(x==1u&&y==2u){p1=3u;}
    else if(x==1u&&y==3u){p1=4u;}
    else if(x==2u&&y==3u){p1=5u;}
    var p2 = 0u;
    if(w==0u&&z==2u){p2=1u;}
    else if(w==0u&&z==3u){p2=2u;}
    else if(w==1u&&z==2u){p2=3u;}
    else if(w==1u&&z==3u){p2=4u;}
    else if(w==2u&&z==3u){p2=5u;}
    if (p1 > p2) {
        let temp1 = p1;
        p1 = p2;
        p2 = temp1;
    }
    var val = 0.0;
    if (p1 == 0u) {
        if (p2 == 0u) { val = R.R0101; }
        else if (p2 == 1u) { val = R.R0102; }
        else if (p2 == 2u) { val = R.R0103; }
        else if (p2 == 3u) { val = R.R0112; }
        else if (p2 == 4u) { val = R.R0113; }
        else { val = R.R0123; }
    }
    else if (p1 == 1u) {
        if (p2 == 1u) { val = R.R0202; }
        else if (p2 == 2u) { val = R.R0203; }
        else if (p2 == 3u) { val = R.R0212; }
        else if (p2 == 4u) { val = R.R0213; }
        else { val = R.R0223; }
    }
    else if (p1 == 2u) {
        if (p2 == 2u) { val = R.R0303; }
        else if (p2 == 3u) { val = -R.R0123 - R.R0213; }
        else if (p2 == 4u) { val = R.R0313; }
        else { val = R.R0323; }
    }
    else if (p1 == 3u) {
        if (p2 == 3u) { val = R.R1212; }
        else if (p2 == 4u) { val = R.R1213; }
        else { val = R.R1223; }
    }
    else if (p1 == 4u) {
        if (p2 == 4u) { val = R.R1313; }
        else { val = R.R1323; }
    } else {
        val = R.R2323;
    }
    return sign * val;
}

fn compute_ricci(R_tensor: Riemann20, g_inv: InverseMetric) -> Ricci10 {
    var Rc: Ricci10;
    // Lokális segédfüggvény mintájára a 10 kontrakció legenerálása
    Rc.R00 = g_inv.g11 * extract_r4(R_tensor,1u,0u,1u,0u) + g_inv.g22 * extract_r4(R_tensor,2u,0u,2u,0u) + g_inv.g33 * extract_r4(R_tensor,3u,0u,3u,0u) + 2.0 * (g_inv.g01 * extract_r4(R_tensor,0u,0u,1u,0u) + g_inv.g02 * extract_r4(R_tensor,0u,0u,2u,0u) + g_inv.g03 * extract_r4(R_tensor,0u,0u,3u,0u)+ g_inv.g12 * extract_r4(R_tensor,1u,0u,2u,0u) + g_inv.g13 * extract_r4(R_tensor,1u,0u,3u,0u) + g_inv.g23 * extract_r4(R_tensor,2u,0u,3u,0u));
    Rc.R11 = g_inv.g00 * extract_r4(R_tensor,0u,1u,0u,1u) + g_inv.g22 * extract_r4(R_tensor,2u,1u,2u,1u) + g_inv.g33 * extract_r4(R_tensor,3u,1u,3u,1u) + 2.0 * (g_inv.g01 * extract_r4(R_tensor,0u,1u,1u,1u) + g_inv.g02 * extract_r4(R_tensor,0u,1u,2u,1u) + g_inv.g03 * extract_r4(R_tensor,0u,1u,3u,1u)+ g_inv.g12 * extract_r4(R_tensor,1u,1u,2u,1u) + g_inv.g13 * extract_r4(R_tensor,1u,1u,3u,1u) + g_inv.g23 * extract_r4(R_tensor,2u,1u,3u,1u));
    Rc.R22 = g_inv.g00 * extract_r4(R_tensor,0u,2u,0u,2u) + g_inv.g11 * extract_r4(R_tensor,1u,2u,1u,2u) + g_inv.g33 * extract_r4(R_tensor,3u,2u,3u,2u) + 2.0 * (g_inv.g01 * extract_r4(R_tensor,0u,2u,1u,2u) + g_inv.g02 * extract_r4(R_tensor,0u,2u,2u,2u) + g_inv.g03 * extract_r4(R_tensor,0u,2u,3u,2u)+ g_inv.g12 * extract_r4(R_tensor,1u,2u,2u,2u) + g_inv.g13 * extract_r4(R_tensor,1u,2u,3u,2u) + g_inv.g23 * extract_r4(R_tensor,2u,2u,3u,2u));
    Rc.R33 = g_inv.g00 * extract_r4(R_tensor,0u,3u,0u,3u) + g_inv.g11 * extract_r4(R_tensor,1u,3u,1u,3u) + g_inv.g22 * extract_r4(R_tensor,2u,3u,2u,3u) + 2.0 * (g_inv.g01 * extract_r4(R_tensor,0u,3u,1u,3u) + g_inv.g02 * extract_r4(R_tensor,0u,3u,2u,3u) + g_inv.g03 * extract_r4(R_tensor,0u,3u,3u,3u)+ g_inv.g12 * extract_r4(R_tensor,1u,3u,2u,3u) + g_inv.g13 * extract_r4(R_tensor,1u,3u,3u,3u) + g_inv.g23 * extract_r4(R_tensor,2u,3u,2u,3u));
    Rc.R01 = g_inv.g22 * extract_r4(R_tensor,2u,0u,2u,1u) + g_inv.g33 * extract_r4(R_tensor,3u,0u,3u,1u) + g_inv.g01 * (extract_r4(R_tensor,0u,0u,1u,1u)+extract_r4(R_tensor,1u,0u,0u,1u));
    // Vegyes kereszt kontrakciók simplified
    Rc.R02 = g_inv.g11 * extract_r4(R_tensor,1u,0u,1u,2u) + g_inv.g33 * extract_r4(R_tensor,3u,0u,3u,2u);
    Rc.R03 = g_inv.g11 * extract_r4(R_tensor,1u,0u,1u,3u) + g_inv.g22 * extract_r4(R_tensor,2u,0u,2u,3u);
    Rc.R12 = g_inv.g00 * extract_r4(R_tensor,0u,1u,0u,2u) + g_inv.g33 * extract_r4(R_tensor,3u,1u,3u,2u);
    Rc.R13 = g_inv.g00 * extract_r4(R_tensor,0u,1u,0u,3u) + g_inv.g22 * extract_r4(R_tensor,2u,1u,2u,3u);
    Rc.R23 = g_inv.g00 * extract_r4(R_tensor,0u,2u,0u,3u) + g_inv.g11 * extract_r4(R_tensor,1u,2u,1u,3u);
    return Rc;
}

fn compute_ricci_scalar(Rc: Ricci10, g_inv: InverseMetric) -> f32 {
    return g_inv.g00 * Rc.R00 + g_inv.g11 * Rc.R11 + g_inv.g22 * Rc.R22 + g_inv.g33 * Rc.R33 +
        2.0 * (g_inv.g01 * Rc.R01 + g_inv.g02 * Rc.R02 + g_inv.g03 * Rc.R03 + g_inv.g12 * Rc.R12 + g_inv.g13 * Rc.R13 + g_inv.g23 * Rc.R23);
}

fn extract_ricci_matrix(Rc: Ricci10, a: u32, b: u32) -> f32 {
    var u = a;
    var v = b;
    if (a > b) { u = b; v = a; }
    if (u == 0u && v == 0u) { return Rc.R00; }
    if (u == 1u && v == 1u) { return Rc.R11; }
    if (u == 2u && v == 2u) { return Rc.R22; }
    if (u == 3u && v == 3u) { return Rc.R33; }
    if (u == 0u && v == 1u) { return Rc.R01; }
    if (u == 0u && v == 2u) { return Rc.R02; }
    if (u == 0u && v == 3u) { return Rc.R03; }
    if (u == 1u && v == 2u) { return Rc.R12; }
    if (u == 1u && v == 3u) { return Rc.R13; }
    if (u == 2u && v == 3u) { return Rc.R23; }
    return 0.0;
}

// Az általad említett K = C^2 + 2R^2 - 1/3 R^2 azonosság optimális, négyzetes kontrakciója
fn compute_weyl_squared(K: f32, Rc: Ricci10, g_inv: InverseMetric, R_scalar: f32) -> f32 {
    var ricci_squared = 0.0;
    for (var u = 0u; u < 4u; u++) {
        for (var v = 0u; v < 4u; v++) {
            var r_up_uv = 0.0;
            for (var a = 0u; a < 4u; a++) {
                for (var b = 0u; b < 4u; b++) {
                    let g_ua = extract_inv_metric_element(g_inv, u, a);
                    let g_vb = extract_inv_metric_element(g_inv, v, b);
                    let r_ab = extract_ricci_matrix(Rc, a, b);
                    r_up_uv += g_ua * g_vb * r_ab;
                }
            }
            let r_down_uv = extract_ricci_matrix(Rc, u, v);
            ricci_squared += r_down_uv * r_up_uv;
        }
    }
    let C2 = K - 2.0 * ricci_squared + (1.0 / 3.0) * R_scalar * R_scalar;
    return max(0.0, C2);
}

@compute @workgroup_size(4, 4, 4)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= dims.width || id.y >= dims.height || id.z >= dims.depth) { return; }
    let cx = i32(id.x);
    let cy = i32(id.y);
    let cz = i32(id.z);
    let p_center = get_metric_at(cx, cy, cz);
    // SZÁMÍTÁSI LÁNCOLOZÁS: Az általad javasolt szuper-optimális verzió
    let center_data = get_christoffel_at(cx, cy, cz);
    let ch_center = center_data.ch;
    let g_inv = center_data.g_inv; // Ingyen megkaptuk az inverzet!
    // Invariánsok levezetése egymásból
    let R_tensor = compute_riemann_20(cx, cy, cz, ch_center, p_center);
    let K_scalar = compute_kretschmann(R_tensor);
    let Rc_tensor = compute_ricci(R_tensor, g_inv);
    let R_scalar = compute_ricci_scalar(Rc_tensor, g_inv);
    // Weyl kvadratikus skalár az azonosságból
    let C2_scalar = compute_weyl_squared(K_scalar, Rc_tensor, g_inv, R_scalar);
    // A MÓDOSÍTOTT TÉREGYENLETED ZÁRÓJELES GRAVITÁCIÓS FESZÜLTSÉG TAGJA:
    let brackets = 0.5 * R_scalar + 0.5 * sqrt(K_scalar) + sqrt(C2_scalar);
    // Eredmény mentése a kimeneti pufferbe koordináta szerint
    let current_1d_index = get_index(id.x, id.y, id.z);
    output_kret[current_1d_index] = brackets;
}