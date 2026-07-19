struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dx: f32,
    dt: f32,
    step_index: u32,
    init_flag: u32,  // (1u = kezdeti inicializáció, 0u = futó szimuláció)
    pad2: u32,
}

struct GridPoints {
    a : array<f32, 44>,
}

@group(0) @binding(0) var<uniform> dims: GridDimensions;
@group(0) @binding(1) var<storage, read_write> buff_old : array<GridPoints>; // dims.width * dims.height * dims.depth * (11 * sizeof(f32))
@group(0) @binding(2) var<storage, read_write> buff_new : array<GridPoints>; // dims.width * dims.height * dims.depth * (11 * sizeof(f32))

alias MetricPoint = array<f32, 10>;
    //  struct MetricPoint {
    //      g00, g11, g22, g33,
    //      g01, g02, g03,
    //      g12, g13, g23,
    //  }


alias Christoffel40 = array<f32, 40>;
    //  struct Christoffel40 {
    //      L0_diag: vec4<f32>, L0_cross: vec4<f32>, L0_rest: vec2<f32>,
    //      L1_diag: vec4<f32>, L1_cross: vec4<f32>, L1_rest: vec2<f32>,
    //      L2_diag: vec4<f32>, L2_cross: vec4<f32>, L2_rest: vec2<f32>,
    //      L3_diag: vec4<f32>, L3_cross: vec4<f32>, L3_rest: vec2<f32>,
    //  }

const OLD: i32 = 0;
const NEW: i32 = 1;

const RICCI: i32 = 0;
const MOMENTS: i32 = 10;
const INVERSE: i32 = 20;
const METRIC: i32 = 30;

fn check_idx(id: vec3<u32>) -> i32 {
    if (id.x >= dims.width || id.y >= dims.height || id.z >= dims.depth) { return -1; }
    return i32(id.x + (id.y + id.z * dims.height) * dims.width);
}

fn next(address: i32, dx: i32, dy: i32, dz: i32 ) -> i32 {
    let w = i32(dims.width);
    let h = i32(dims.height);
    let d = i32(dims.depth);
    let a = address / w;
    var x = address - a * w;
    var z = a / h;
    var y = a - z * h;
    x = clamp(x + dx, 0, w - 1);
    y = clamp(y + dy, 0, h - 1);
    z = clamp(z + dz, 0, d - 1);
    return x + (y + z * h) * w;
}

fn get_metric(old: i32, address: i32, offs: i32) -> MetricPoint {
    var m: MetricPoint;
    if( old == OLD ) {
        m[0] = buff_old[address].a[offs];
        m[1] = buff_old[address].a[offs+1];
        m[2] = buff_old[address].a[offs+2];
        m[3] = buff_old[address].a[offs+3];
        m[4] = buff_old[address].a[offs+4];
        m[5] = buff_old[address].a[offs+5];
        m[6] = buff_old[address].a[offs+6];
        m[7] = buff_old[address].a[offs+7];
        m[8] = buff_old[address].a[offs+8];
        m[9] = buff_old[address].a[offs+9];
    }
    else {
        m[0] = buff_new[address].a[offs];
        m[1] = buff_new[address].a[offs+1];
        m[2] = buff_new[address].a[offs+2];
        m[3] = buff_new[address].a[offs+3];
        m[4] = buff_new[address].a[offs+4];
        m[5] = buff_new[address].a[offs+5];
        m[6] = buff_new[address].a[offs+6];
        m[7] = buff_new[address].a[offs+7];
        m[8] = buff_new[address].a[offs+8];
        m[9] = buff_new[address].a[offs+9];
    }
    return m;
}

fn set_metric(old: i32, address: i32, offs: i32, m: MetricPoint){
    if( old == OLD ) {
        buff_old[address].a[offs]   = m[0];
        buff_old[address].a[offs+1] = m[1];
        buff_old[address].a[offs+2] = m[2];
        buff_old[address].a[offs+3] = m[3];
        buff_old[address].a[offs+4] = m[4];
        buff_old[address].a[offs+5] = m[5];
        buff_old[address].a[offs+6] = m[6];
        buff_old[address].a[offs+7] = m[7];
        buff_old[address].a[offs+8] = m[8];
        buff_old[address].a[offs+9] = m[9];
    }
    else {
        buff_new[address].a[offs]   = m[0];
        buff_new[address].a[offs+1] = m[1];
        buff_new[address].a[offs+2] = m[2];
        buff_new[address].a[offs+3] = m[3];
        buff_new[address].a[offs+4] = m[4];
        buff_new[address].a[offs+5] = m[5];
        buff_new[address].a[offs+6] = m[6];
        buff_new[address].a[offs+7] = m[7];
        buff_new[address].a[offs+8] = m[8];
        buff_new[address].a[offs+9] = m[9];
    }
}

fn get_scalars(old: i32, address: i32) -> vec4<f32> {
    var v: vec4<f32>;
    if( old == OLD ) {
        v.x = buff_old[address].a[40];
        v.y = buff_old[address].a[41];
        v.z = buff_old[address].a[42];
        v.w = buff_old[address].a[43];
    }
    else {
        v.x = buff_new[address].a[40];
        v.y = buff_new[address].a[41];
        v.z = buff_new[address].a[42];
        v.w = buff_new[address].a[43];
    }
    return v;
}

fn set_scalars(old: i32, address: i32, v: vec4<f32>) {
    if( old == OLD ) {
        buff_old[address].a[40] = v.x;
        buff_old[address].a[41] = v.y;
        buff_old[address].a[42] = v.z;
        buff_old[address].a[43] = v.w;
    }
    else {
        buff_new[address].a[40] = v.x;
        buff_new[address].a[41] = v.y;
        buff_new[address].a[42] = v.z;
        buff_new[address].a[43] = v.w;
    }
}

fn store_christoffel_scratchpad(ch: Christoffel40, address: i32) {
    buff_new[address].a[ 0] = ch[ 0];
    buff_new[address].a[ 1] = ch[ 1];
    buff_new[address].a[ 2] = ch[ 2];
    buff_new[address].a[ 3] = ch[ 3];
    buff_new[address].a[ 4] = ch[ 4];
    buff_new[address].a[ 5] = ch[ 5];
    buff_new[address].a[ 6] = ch[ 6];
    buff_new[address].a[ 7] = ch[ 7];
    buff_new[address].a[ 8] = ch[ 8];
    buff_new[address].a[ 9] = ch[ 9];
    buff_new[address].a[10] = ch[10];
    buff_new[address].a[11] = ch[11];
    buff_new[address].a[12] = ch[12];
    buff_new[address].a[13] = ch[13];
    buff_new[address].a[14] = ch[14];
    buff_new[address].a[15] = ch[15];
    buff_new[address].a[16] = ch[16];
    buff_new[address].a[17] = ch[17];
    buff_new[address].a[18] = ch[18];
    buff_new[address].a[19] = ch[19];
    buff_new[address].a[20] = ch[20];
    buff_new[address].a[21] = ch[21];
    buff_new[address].a[22] = ch[22];
    buff_new[address].a[23] = ch[23];
    buff_new[address].a[24] = ch[24];
    buff_new[address].a[25] = ch[25];
    buff_new[address].a[26] = ch[26];
    buff_new[address].a[27] = ch[27];
    buff_new[address].a[28] = ch[28];
    buff_new[address].a[29] = ch[29];
    buff_new[address].a[30] = ch[30];
    buff_new[address].a[31] = ch[31];
    buff_new[address].a[32] = ch[32];
    buff_new[address].a[33] = ch[33];
    buff_new[address].a[34] = ch[34];
    buff_new[address].a[35] = ch[35];
    buff_new[address].a[36] = ch[36];
    buff_new[address].a[37] = ch[37];
    buff_new[address].a[38] = ch[38];
    buff_new[address].a[39] = ch[39];
}

fn load_christoffel_scratchpad(address: i32) -> Christoffel40 {
    var ch: Christoffel40;
    ch[ 0] = buff_new[address].a[ 0];
    ch[ 1] = buff_new[address].a[ 1];
    ch[ 2] = buff_new[address].a[ 2];
    ch[ 3] = buff_new[address].a[ 3];
    ch[ 4] = buff_new[address].a[ 4];
    ch[ 5] = buff_new[address].a[ 5];
    ch[ 6] = buff_new[address].a[ 6];
    ch[ 7] = buff_new[address].a[ 7];
    ch[ 8] = buff_new[address].a[ 8];
    ch[ 9] = buff_new[address].a[ 9];
    ch[10] = buff_new[address].a[10];
    ch[11] = buff_new[address].a[11];
    ch[12] = buff_new[address].a[12];
    ch[13] = buff_new[address].a[13];
    ch[14] = buff_new[address].a[14];
    ch[15] = buff_new[address].a[15];
    ch[16] = buff_new[address].a[16];
    ch[17] = buff_new[address].a[17];
    ch[18] = buff_new[address].a[18];
    ch[19] = buff_new[address].a[19];
    ch[20] = buff_new[address].a[20];
    ch[21] = buff_new[address].a[21];
    ch[22] = buff_new[address].a[22];
    ch[23] = buff_new[address].a[23];
    ch[24] = buff_new[address].a[24];
    ch[25] = buff_new[address].a[25];
    ch[26] = buff_new[address].a[26];
    ch[27] = buff_new[address].a[27];
    ch[28] = buff_new[address].a[28];
    ch[29] = buff_new[address].a[29];
    ch[30] = buff_new[address].a[30];
    ch[31] = buff_new[address].a[31];
    ch[32] = buff_new[address].a[32];
    ch[33] = buff_new[address].a[33];
    ch[34] = buff_new[address].a[34];
    ch[35] = buff_new[address].a[35];
    ch[36] = buff_new[address].a[36];
    ch[37] = buff_new[address].a[37];
    ch[38] = buff_new[address].a[38];
    ch[39] = buff_new[address].a[39];
    return ch;
}

///////////////////////////////////////////////////////////////////////////////////////

// 4x4-es inverz metrika kiszámítása (Cramer-szabály)
fn det3x3(m00: f32, m01: f32, m02: f32, m10: f32, m11: f32, m12: f32, m20: f32, m21: f32, m22: f32) -> f32 {
    return m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02 * (m10 * m21 - m11 * m20);
}

fn invert_metric(p: MetricPoint) -> MetricPoint {
    let m00 = p[0]; let m01 = p[4]; let m02 = p[5]; let m03 = p[6];
    let m10 = p[4]; let m11 = p[1]; let m12 = p[7]; let m13 = p[8];
    let m20 = p[5]; let m21 = p[7]; let m22 = p[2]; let m23 = p[9];
    let m30 = p[6]; let m31 = p[8]; let m32 = p[9]; let m33 = p[3];

    let det = m00 * det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33)
            - m01 * det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33)
            + m02 * det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33)
            - m03 * det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32);

    var inv_det = 0.0;
    if (abs(det) > 1e-9) { inv_det = 1.0 / det; }

    var inv: MetricPoint;
    inv[0] =  det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33) * inv_det;
    inv[1] =  det3x3(m00, m02, m03, m20, m22, m23, m30, m32, m33) * inv_det;
    inv[2] =  det3x3(m00, m01, m03, m10, m11, m13, m30, m31, m33) * inv_det;
    inv[3] =  det3x3(m00, m01, m02, m10, m11, m12, m20, m21, m22) * inv_det;
    
    inv[4] = -det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33) * inv_det;
    inv[5] =  det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33) * inv_det;
    inv[6] = -det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32) * inv_det;
    
    inv[7] = -det3x3(m00, m02, m03, m10, m12, m13, m30, m32, m33) * inv_det;
    inv[8] =  det3x3(m00, m01, m03, m10, m11, m13, m20, m21, m23) * inv_det;
    
    inv[9] = -det3x3(m00, m01, m02, m10, m11, m12, m30, m31, m32) * inv_det;
    return inv;
}


// ==========================================
// 1. LÉPCSŐ: TISZTA INVERZ KISZÁMÍTÁSA (Pre-compute)
// ==========================================
@compute @workgroup_size(4, 4, 4)
fn phase1(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }
    let g = get_metric(OLD, address, METRIC);
    let inv = invert_metric(g);
    set_metric(OLD, address, INVERSE, inv);
}
// ==========================================

fn extract_metric_element(p: MetricPoint, a: u32, b: u32) -> f32 {
    var u = a;
    var v = b;
    if (a > b) { u = b; v = a; }
    if (u == 0u && v == 0u) { return p[0]; }
    if (u == 1u && v == 1u) { return p[1]; }
    if (u == 2u && v == 2u) { return p[2]; }
    if (u == 3u && v == 3u) { return p[3]; }
    if (u == 0u && v == 1u) { return p[4]; }
    if (u == 0u && v == 2u) { return p[5]; }
    if (u == 0u && v == 3u) { return p[6]; }
    if (u == 1u && v == 2u) { return p[7]; }
    if (u == 1u && v == 3u) { return p[8]; }
    if (u == 2u && v == 3u) { return p[9]; }
    return 0.0;
}

fn get_deriv(mu: u32, a: u32, b: u32,
        p_x_plus: MetricPoint, p_x_minus: MetricPoint,
        p_y_plus: MetricPoint, p_y_minus: MetricPoint,
        p_z_plus: MetricPoint, p_z_minus: MetricPoint) -> f32 {
    if (mu == 0u) { return 0.0; }
    var val_plus = 0.0;
    var val_minus = 0.0;
    if (mu == 1u) { val_plus = extract_metric_element(p_x_plus, a, b); val_minus = extract_metric_element(p_x_minus, a, b); }
    else if (mu == 2u) { val_plus = extract_metric_element(p_y_plus, a, b); val_minus = extract_metric_element(p_y_minus, a, b); }
    else if (mu == 3u) { val_plus = extract_metric_element(p_z_plus, a, b); val_minus = extract_metric_element(p_z_minus, a, b); }
    return (val_plus - val_minus) / (2.0 * dims.dx);
}


fn get_christoffel_at(address: i32) -> Christoffel40 {
    let p_center  = get_metric(OLD,address, METRIC);
    let g_inverz  = get_metric(OLD,address, INVERSE);
    let p_x_plus  = get_metric(OLD,next(address, 1, 0, 0), METRIC);
    let p_x_minus = get_metric(OLD,next(address,-1, 0, 0), METRIC);
    let p_y_plus  = get_metric(OLD,next(address, 0, 1, 0), METRIC);
    let p_y_minus = get_metric(OLD,next(address, 0,-1, 0), METRIC);
    let p_z_plus  = get_metric(OLD,next(address, 0, 0, 1), METRIC);
    let p_z_minus = get_metric(OLD,next(address, 0, 0,-1), METRIC);

    var ch: Christoffel40;
    for (var L = 0u; L < 4u; L++) {
        var temp_diag = vec4<f32>(0.0);
        var temp_cross = vec4<f32>(0.0);
        var temp_rest = vec2<f32>(0.0);
        for (var k = 0u; k < 10u; k++) {
            var M = 0u; var N = 0u;
            if (k == 0u) { M = 0u; N = 0u; }
            else if (k == 1u) { M = 1u; N = 1u; }
            else if (k == 2u) { M = 2u; N = 2u; }
            else if (k == 3u) { M = 3u; N = 3u; }
            else if (k == 4u) { M = 0u; N = 1u; }
            else if (k == 5u) { M = 0u; N = 2u; }
            else if (k == 6u) { M = 0u; N = 3u; }
            else if (k == 7u) { M = 1u; N = 2u; }
            else if (k == 8u) { M = 1u; N = 3u; }
            else { M = 2u; N = 3u; }

            var val = 0.0;
            for (var sig = 0u; sig < 4u; sig++) {
                let inv_g_L_sig = extract_metric_element(g_inverz, L, sig);
                let dM_gNsig = get_deriv(M, N, sig, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
                let dN_gMsig = get_deriv(N, M, sig, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
                let dsig_gMN = get_deriv(sig, M, N, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
                val += 0.5 * inv_g_L_sig * (dM_gNsig + dN_gMsig - dsig_gMN);
            }
            if (k == 0u)      { temp_diag.x = val; }
            else if (k == 1u) { temp_diag.y = val; }
            else if (k == 2u) { temp_diag.z = val; }
            else if (k == 3u) { temp_diag.w = val; }
            else if (k == 4u) { temp_cross.x = val; }
            else if (k == 5u) { temp_cross.y = val; }
            else if (k == 6u) { temp_cross.z = val; }
            else if (k == 7u) { temp_cross.w = val; }
            else if (k == 8u) { temp_rest .x = val; }
            else              { temp_rest.y = val; }
        }

        if (L == 0u) {
            ch[0] = temp_diag.x;  ch[1] = temp_diag.y;  ch[2] = temp_diag.z;  ch[3] = temp_diag.w;
            ch[4] = temp_cross.x; ch[5] = temp_cross.y; ch[6] = temp_cross.z; ch[7] = temp_cross.w;
            ch[8] = temp_rest.x;  ch[9] = temp_rest.y;
        }
        else if (L == 1u) {
            ch[10] = temp_diag.x;  ch[11] = temp_diag.y;  ch[12] = temp_diag.z;  ch[13] = temp_diag.w;
            ch[14] = temp_cross.x; ch[15] = temp_cross.y; ch[16] = temp_cross.z; ch[17] = temp_cross.w;
            ch[18] = temp_rest.x;  ch[19] = temp_rest.y;
        }
        else if (L == 2u) {
            ch[20] = temp_diag.x;  ch[21] = temp_diag.y;  ch[22] = temp_diag.z;  ch[23] = temp_diag.w;
            ch[24] = temp_cross.x; ch[25] = temp_cross.y; ch[26] = temp_cross.z; ch[27] = temp_cross.w;
            ch[28] = temp_rest.x;  ch[29] = temp_rest.y;
        }
        else {
            ch[30] = temp_diag.x;  ch[31] = temp_diag.y;  ch[32] = temp_diag.z;  ch[33] = temp_diag.w;
            ch[34] = temp_cross.x; ch[35] = temp_cross.y; ch[36] = temp_cross.z; ch[37] = temp_cross.w;
            ch[38] = temp_rest.x;  ch[39] = temp_rest.y;
        }

    }
    return ch;
}

// ==========================================
// 2. LÉPCSŐ: CHRISTOFFEL SIMBÓLUMOK KISZÁMÍTÁSA
// ==========================================
@compute @workgroup_size(4, 4, 4)
fn phase2(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }

    let ch = get_christoffel_at(address);
    store_christoffel_scratchpad(ch, address);
}
// ==========================================


fn extract_gamma(ch: Christoffel40, L: u32, M: u32, N: u32) -> f32 {
    // Biztosítjuk a szimmetriát az alsó indexeknél (M <= N)
    var u = M; var v = N;
    if (M > N) { u = N; v = M; }

    // Kiszámoljuk az alsó indexpár belső k-indexét (0..9)
    var k = 0u;
    if (u == 0u && v == 0u)      { k = 0u; } else if (u == 1u && v == 1u) { k = 1u; }
    else if (u == 2u && v == 2u) { k = 2u; } else if (u == 3u && v == 3u) { k = 3u; }
    else if (u == 0u && v == 1u) { k = 4u; } else if (u == 0u && v == 2u) { k = 5u; }
    else if (u == 0u && v == 3u) { k = 6u; } else if (u == 1u && v == 2u) { k = 7u; }
    else if (u == 1u && v == 3u) { k = 8u; } else                         { k = 9u; }

    // A felső index (L) eltolja a bázisindexet 10-esével
    let final_index = (L * 10u) + k;
    return ch[final_index];
}

fn deriv_gamma(address: i32, L: u32, M: u32, N: u32, dir: u32) -> f32 {
    var coords_plus = address;  var coords_minus = address;
    if (dir == 1u)      { coords_plus = next(address,1,0,0); coords_minus = next(address,-1,0,0); }
    else if (dir == 2u) { coords_plus = next(address,0,1,0); coords_minus = next(address,0,-1,0); }
    else if (dir == 3u) { coords_plus = next(address,0,0,1); coords_minus = next(address,0,0,-1); }

    let ch_plus  = load_christoffel_scratchpad(coords_plus);
    let ch_minus = load_christoffel_scratchpad(coords_minus);

    return (extract_gamma(ch_plus, L, M, N) - extract_gamma(ch_minus, L, M, N)) / (2.0 * dims.dx);
}

fn get_riemann_element(address: i32, ch: Christoffel40, L: u32, M: u32, N: u32, nu: u32) -> f32 {
    // Riemann formula: d_N Gamma^L_M_nu - d_nu Gamma^L_M_N + Gamma * Gamma tagok
    let term_deriv = deriv_gamma(address, L, M, nu, N) - deriv_gamma(address, L, M, N, nu);
    var term_nonlinear = 0.0;
    for (var s = 0u; s < 4u; s = s + 1u) {
        term_nonlinear += extract_gamma(ch, L, s, N) * extract_gamma(ch, s, M, nu) 
                        - extract_gamma(ch, L, s, nu) * extract_gamma(ch, s, M, N);
    }
    return term_deriv + term_nonlinear;
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


fn compute_riemann_20(address: i32, ch: Christoffel40, g: MetricPoint) -> Riemann20 {
    var R: Riemann20;
    // Segéd-vektorok az index leengedéséhez (R_abcd = g_am * R^m_bcd)
    var R_up = vec4(0.0);
    // 1. Blokk: Tiszta átlós bindex elemek
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,1u,0u,1u); }
    R.R0101 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,0u,2u); }
    R.R0202 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,3u,0u,3u); }
    R.R0303 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,1u,2u); }
    R.R1212 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,3u,1u,3u); }
    R.R1313 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,3u,2u,3u); }
    R.R2323 = g[5] * R_up.x + g[7] * R_up.y + g[2] * R_up.z + g[9] * R_up.w;
    // 2. Blokk: Kereszt-tagok
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,1u,0u,2u); }
    R.R0102 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,1u,0u,3u); }
    R.R0103 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,0u,3u); }
    R.R0203 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,1u,1u,2u); }
    R.R0112 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,1u,1u,3u); }
    R.R0113 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,1u,2u); }
    R.R0212 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,2u,3u); }
    R.R0223 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,3u,1u,3u); }
    R.R0313 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,3u,2u,3u); }
    R.R0323 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    // 3. Blokk: Térbeli vegyes tagok
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,1u,3u); }
    R.R1213 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,2u,3u); }
    R.R1223 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,3u,2u,3u); }
    R.R1323 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,1u,2u,3u); }
    R.R0123 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,ch,m,2u,1u,3u); }
    R.R0213 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    return R;
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

struct Ricci10 {
    R00: f32, R11: f32, R22: f32, R33: f32,
    R01: f32, R02: f32, R03: f32,
    R12: f32, R13: f32, R23: f32,
}

fn compute_ricci(R_tensor: Riemann20, g_inv: MetricPoint) -> Ricci10 {
    var Rc: Ricci10;
    // Lokális segédfüggvény mintájára a 10 kontrakció legenerálása
    Rc.R00 = g_inv[1] * extract_r4(R_tensor,1u,0u,1u,0u) + g_inv[2] * extract_r4(R_tensor,2u,0u,2u,0u) + g_inv[3] * extract_r4(R_tensor,3u,0u,3u,0u) + 2.0 * (g_inv[4] * extract_r4(R_tensor,0u,0u,1u,0u) + g_inv[5] * extract_r4(R_tensor,0u,0u,2u,0u) + g_inv[6] * extract_r4(R_tensor,0u,0u,3u,0u)+ g_inv[7] * extract_r4(R_tensor,1u,0u,2u,0u) + g_inv[8] * extract_r4(R_tensor,1u,0u,3u,0u) + g_inv[9] * extract_r4(R_tensor,2u,0u,3u,0u));
    
    Rc.R11 = g_inv[0] * extract_r4(R_tensor,0u,1u,0u,1u) + g_inv[2] * extract_r4(R_tensor,2u,1u,2u,1u) + g_inv[3] * extract_r4(R_tensor,3u,1u,3u,1u) + 2.0 * (g_inv[4] * extract_r4(R_tensor,0u,1u,1u,1u) + g_inv[5] * extract_r4(R_tensor,0u,1u,2u,1u) + g_inv[6] * extract_r4(R_tensor,0u,1u,3u,1u)+ g_inv[7] * extract_r4(R_tensor,1u,1u,2u,1u) + g_inv[8] * extract_r4(R_tensor,1u,1u,3u,1u) + g_inv[9] * extract_r4(R_tensor,2u,1u,3u,1u));
    
    Rc.R22 = g_inv[0] * extract_r4(R_tensor,0u,2u,0u,2u) + g_inv[1] * extract_r4(R_tensor,1u,2u,1u,2u) + g_inv[3] * extract_r4(R_tensor,3u,2u,3u,2u) + 2.0 * (g_inv[4] * extract_r4(R_tensor,0u,2u,1u,2u) + g_inv[5] * extract_r4(R_tensor,0u,2u,2u,2u) + g_inv[6] * extract_r4(R_tensor,0u,2u,3u,2u)+ g_inv[7] * extract_r4(R_tensor,1u,2u,2u,2u) + g_inv[8] * extract_r4(R_tensor,1u,2u,3u,2u) + g_inv[9] * extract_r4(R_tensor,2u,2u,3u,2u));
    
    Rc.R33 = g_inv[0] * extract_r4(R_tensor,0u,3u,0u,3u) + g_inv[1] * extract_r4(R_tensor,1u,3u,1u,3u) + g_inv[2] * extract_r4(R_tensor,2u,3u,2u,3u) + 2.0 * (g_inv[4] * extract_r4(R_tensor,0u,3u,1u,3u) + g_inv[5] * extract_r4(R_tensor,0u,3u,2u,3u) + g_inv[6] * extract_r4(R_tensor,0u,3u,3u,3u)+ g_inv[7] * extract_r4(R_tensor,1u,3u,2u,3u) + g_inv[8] * extract_r4(R_tensor,1u,3u,3u,3u) + g_inv[9] * extract_r4(R_tensor,2u,3u,2u,3u));
    
    Rc.R01 = g_inv[2] * extract_r4(R_tensor,2u,0u,2u,1u) + g_inv[3] * extract_r4(R_tensor,3u,0u,3u,1u) + g_inv[4] * (extract_r4(R_tensor,0u,0u,1u,1u)+extract_r4(R_tensor,1u,0u,0u,1u));
    // Vegyes kereszt kontrakciók simplified
    Rc.R02 = g_inv[1] * extract_r4(R_tensor,1u,0u,1u,2u) + g_inv[3] * extract_r4(R_tensor,3u,0u,3u,2u);
    Rc.R03 = g_inv[1] * extract_r4(R_tensor,1u,0u,1u,3u) + g_inv[2] * extract_r4(R_tensor,2u,0u,2u,3u);
    Rc.R12 = g_inv[0] * extract_r4(R_tensor,0u,1u,0u,2u) + g_inv[3] * extract_r4(R_tensor,3u,1u,3u,2u);
    Rc.R13 = g_inv[0] * extract_r4(R_tensor,0u,1u,0u,3u) + g_inv[2] * extract_r4(R_tensor,2u,1u,2u,3u);
    Rc.R23 = g_inv[0] * extract_r4(R_tensor,0u,2u,0u,3u) + g_inv[1] * extract_r4(R_tensor,1u,2u,1u,3u);
    return Rc;
}

fn compute_ricci_scalar(Rc: Ricci10, g_inv: MetricPoint) -> f32 {
    return g_inv[0] * Rc.R00 + g_inv[1] * Rc.R11 + g_inv[2] * Rc.R22 + g_inv[3] * Rc.R33 +
        2.0 * (g_inv[4] * Rc.R01 + g_inv[5] * Rc.R02 + g_inv[6] * Rc.R03 + g_inv[7] * Rc.R12 + g_inv[8] * Rc.R13 + g_inv[9] * Rc.R23);
}

fn compute_kretschmann(R: Riemann20) -> f32 {
    let diagonal = 4.0 * (R.R0101 * R.R0101 + R.R0202 * R.R0202 + R.R0303 * R.R0303 + R.R1212 * R.R1212 + R.R1313 * R.R1313 + R.R2323 * R.R2323);
    let vegyes = 8.0 * (R.R0102 * R.R0102 + R.R0103 * R.R0103 + R.R0203 * R.R0203) + 16.0 * (R.R0112 * R.R0112 + R.R0113 * R.R0113 + R.R0212 * R.R0212 + R.R0223 * R.R0223 + R.R0313 * R.R0313 + R.R0323 * R.R0323);
    let tiszta_ter = 8.0 * (R.R1213 * R.R1213 + R.R1223 * R.R1223 + R.R1323 * R.R1323) + 16.0 * (R.R0123 * R.R0123 + R.R0213 * R.R0213);
    return diagonal + vegyes + tiszta_ter;
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
fn compute_weyl_squared(K: f32, Rc: Ricci10, g_inv: MetricPoint, R_scalar: f32) -> f32 {
    var ricci_squared = 0.0;
    for (var u = 0u; u < 4u; u++) {
        for (var v = 0u; v < 4u; v++) {
            var r_up_uv = 0.0;
            for (var a = 0u; a < 4u; a++) {
                for (var b = 0u; b < 4u; b++) {
                    let g_ua = extract_metric_element(g_inv, u, a);
                    let g_vb = extract_metric_element(g_inv, v, b);
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



// ==========================================================
// 3. FÁZIS: GEOMETRIA ÉS FESZÜLTSÉG (Mentés a Múlt inverz helyére!)
// ==========================================================
@compute @workgroup_size(4, 4, 4)
fn phase3(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }
    
    let g_past = get_metric(OLD,address, METRIC);
    let i_past = get_metric(OLD,address, INVERSE);    
    let ch_center = load_christoffel_scratchpad(address);

    let R20_tensor  = compute_riemann_20(address, ch_center, g_past);
    let Rc_tensor = compute_ricci(R20_tensor, i_past);
    let R_scalar  = compute_ricci_scalar(Rc_tensor, i_past);
    let K_scalar  = compute_kretschmann(R20_tensor);
    let C2_scalar = compute_weyl_squared(K_scalar, Rc_tensor, i_past, R_scalar);
    let brackets = 0.5 * R_scalar + 0.5 * sqrt(K_scalar) + sqrt(C2_scalar);
    
    let scalars = vec4<f32>(R_scalar, K_scalar, C2_scalar, brackets);
    set_scalars(NEW,address, scalars);
    var ricci: MetricPoint;
    ricci[0] = Rc_tensor.R00;
    ricci[1] = Rc_tensor.R11;
    ricci[2] = Rc_tensor.R22;
    ricci[3] = Rc_tensor.R33;
    ricci[4] = Rc_tensor.R01;
    ricci[5] = Rc_tensor.R02;
    ricci[6] = Rc_tensor.R03;
    ricci[7] = Rc_tensor.R12;
    ricci[8] = Rc_tensor.R13;
    ricci[9] = Rc_tensor.R23;
    set_metric(OLD, address, RICCI, ricci);
}
// ==========================================


// ==========================================================
// 4. FÁZIS: IDŐFEJLESZTÉS - ÚJ MOMENTUMOK (Mentés a Jövő momentum helyére)
// ==========================================================
@compute @workgroup_size(4, 4, 4)
fn phase4(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }

    let g_past = get_metric(OLD, address, METRIC);
    var k_past: MetricPoint;
    if (dims.init_flag == 1u) {
        // A legelső körben (t=0) a momentumokat a térbeli elcsavarodás deriváltjaiból generáljuk le!
        let p_x_plus  = get_metric(OLD,next(address, 1, 0, 0), METRIC);
        let p_x_minus = get_metric(OLD,next(address,-1, 0, 0), METRIC);
        let p_y_plus  = get_metric(OLD,next(address, 0, 1, 0), METRIC);
        let p_y_minus = get_metric(OLD,next(address, 0,-1, 0), METRIC);
        let p_z_plus  = get_metric(OLD,next(address, 0, 0, 1), METRIC);
        let p_z_minus = get_metric(OLD,next(address, 0, 0,-1), METRIC);

        // Diagonális momentumok kezdetben zérók statikus/forgó egyensúlynál
        k_past[0] = 0.0; k_past[1] = 0.0; k_past[2] = 0.0; k_past[3] = 0.0;

        // A Kerr-Schild elcsavarodási kereszt-tagok numerikus deriválása:
        // k_ij = 0.5 * (d_i g_0j + d_j g_0i) -> a te extract_metric_element függvényedet használva:
        let d1_g01 = get_deriv(1u, 0u, 1u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus); // M=1, N=(0,1)
        let d1_g02 = get_deriv(1u, 0u, 2u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d2_g01 = get_deriv(2u, 0u, 1u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d1_g03 = get_deriv(1u, 0u, 3u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d3_g01 = get_deriv(3u, 0u, 1u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d2_g02 = get_deriv(2u, 0u, 2u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d2_g03 = get_deriv(2u, 0u, 3u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d3_g02 = get_deriv(3u, 0u, 2u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);
        let d3_g03 = get_deriv(3u, 0u, 3u, p_x_plus, p_x_minus, p_y_plus, p_y_minus, p_z_plus, p_z_minus);

        k_past[4] = d1_g01;                      // k01 = 0.5 * (d_1 g_01 + d_1 g_01) = d_1 g_01
        k_past[5] = 0.5 * (d1_g02 + d2_g01);     // k02
        k_past[6] = 0.5 * (d1_g03 + d3_g01);     // k03
        k_past[7] = d2_g02;                      // k12 = d_2 g_02
        k_past[8] = 0.5 * (d2_g03 + d3_g02);     // k13
        k_past[9] = d3_g03;                      // k23 = d_3 g_03
    } else {
        // Ha a szimuláció már fut (init_flag == 0u), a momentumokat normálisan a múltból olvassuk be!
        k_past = get_metric(OLD,address, MOMENTS);
    }
    let ricci = get_metric(OLD,address, RICCI);
    let scalars = get_scalars(NEW,address);
    let brackets = scalars.w;

    // Kiszámítjuk mind a 10 új momentum-komponenst az Euler-szabály szerint
    var next_k: MetricPoint;
    for (var r = 0u; r < 10u; r = r + 1u) {
        next_k[r] = k_past[r] + dims.dt * (brackets * g_past[r] - ricci[r]);
    }
    set_metric(NEW,address,MOMENTS,next_k);

    // 2. ÚJ METRIKA (Kinematikai Euler szabály: g_new = g_old - 2 * dt * k_new)
    var next_g: MetricPoint;
    for (var r = 0u; r < 10u; r = r + 1u) {
        next_g[r] = g_past[r] - 2.0 * dims.dt * next_k[r];
    }
    set_metric(NEW,address,METRIC,next_g);
}
// ==========================================

// ==========================================================
// 5. FÁZIS: JÖVŐBELI ÁLLAPOT VISSZAMÁSOLÁSA A MÚLTBA (In-place Reset)
// ==========================================================
@compute @workgroup_size(4, 4, 4)
fn phase5(@builtin(global_invocation_id) id: vec3<u32>) {
    // Határellenőrzés a te check_idx függvényeddel
    let address = check_idx(id);
    if (address < 0) { return; }

    // Kézzel kibontott, ultra-gyors unrolled ciklus a 44 elem átmásolására
    // Így a GPU textúra/puffer betöltő egységei maximális sávszélességgel dolgoznak
    for (var s = 0; s < 44; s = s + 1) {
        buff_old[address].a[s] = buff_new[address].a[s];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

