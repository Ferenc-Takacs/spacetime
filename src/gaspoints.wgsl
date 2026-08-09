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
    a : array<f32, 52>,
}

@group(0) @binding(0) var<uniform> dims: GridDimensions;
@group(0) @binding(1) var<storage, read_write> buff_old : array<GridPoints>; // dims.width * dims.height * dims.depth * (13 * sizeof(f32))
@group(0) @binding(2) var<storage, read_write> buff_new : array<GridPoints>; // dims.width * dims.height * dims.depth * (13 * sizeof(f32))

alias MetricPoint = array<f32, 10>;
    //  struct MetricPoint { // symmetric 2D matrix
    //      g00, g11, g22, g33,
    //      g01, g02, g03,
    //      g12, g13, g23,
    //  }


alias Christoffel40 = array<f32, 40>;
    //  struct Christoffel40 { // symmetric 3D matrix
    //      L0_diag: vec4<f32>, L0_cross: vec4<f32>, L0_rest: vec2<f32>,
    //      L1_diag: vec4<f32>, L1_cross: vec4<f32>, L1_rest: vec2<f32>,
    //      L2_diag: vec4<f32>, L2_cross: vec4<f32>, L2_rest: vec2<f32>,
    //      L3_diag: vec4<f32>, L3_cross: vec4<f32>, L3_rest: vec2<f32>,
    //  }

const OLD: i32 = 0;
const NEW: i32 = 1;

//concurent with Christoffels
const METRIC: i32 = 0;
const MOMENT: i32 = 10; // konjugált momentum
const INVERZ: i32 = 20;
const RICCI:  i32 = 30;
// concurent with SCALARs
const ENERGY: i32 = 40;

// Christoffels NEW 0 - 39

const R_SCALAR  = 40;
const K_SCALAR  = 41;
const C2_SCALAR = 42;
const BRACKETS  = 43;
const E_11      = 44;
const E_22      = 45;
const E_12      = 46; //(Elektromos nyírás)
const E_SQ      = 47;
const B_11      = 48;
const B_22      = 49;
const B_12      = 50; //(Mágneses örvény)
const B_SQ      = 51;

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

fn get_scalar(old: i32, address: i32, offs: i32) -> f32 {
    var s: f32;
    if( old == OLD ) {
        s = buff_old[address].a[offs];
    }
    else {
        s = buff_new[address].a[offs];
    }
    return s;
}

fn set_scalar(old: i32, address: i32, offs: i32, s: f32) {
    if( old == OLD ) {
        buff_old[address].a[offs] = s;
    }
    else {
        buff_new[address].a[offs] = s;
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

fn isInfNan(x: f32) -> bool {
    let bits = bitcast<u32>(x);
    let exponent = (bits & 0x7f800000u) == 0x7f800000u;
    return exponent;
}


///////////////////////////////////////////////////////////////////////////////////////

// 4x4-es inverz metrika kiszámítása (Cramer-szabály)
fn det3x3(m00: f32, m01: f32, m02: f32, m10: f32, m11: f32, m12: f32, m20: f32, m21: f32, m22: f32) -> f32 {
    return m00 * (m11 * m22 - m12 * m21) + m01 * (m12 * m20 - m10 * m22) + m02 * (m10 * m21 - m11 * m20);
}

fn invert_metric(p: MetricPoint) -> MetricPoint {
    let m00 = p[0]; let m01 = p[4]; let m02 = p[5]; let m03 = p[6];
    let m10 = p[4]; let m11 = p[1]; let m12 = p[7]; let m13 = p[8];
    let m20 = p[5]; let m21 = p[7]; let m22 = p[2]; let m23 = p[9];
    let m30 = p[6]; let m31 = p[8]; let m32 = p[9]; let m33 = p[3];
    
    let det00 =  det3x3(m11, m12, m13, m21, m22, m23, m31, m32, m33);
    let det01 = -det3x3(m10, m12, m13, m20, m22, m23, m30, m32, m33);
    let det02 =  det3x3(m10, m11, m13, m20, m21, m23, m30, m31, m33);
    let det03 = -det3x3(m10, m11, m12, m20, m21, m22, m30, m31, m32);

    let det = m00 * det00 + m01 * det01 + m02 * det02 + m03 * det03;
    
    var inv_det = 0.0;
    let epsilon_soft = 1e-4;
    if (abs(det) > 1e-9) { inv_det = det / (det * det + epsilon_soft); }

    var inv: MetricPoint;
    inv[0] =  det00 * inv_det; // 00
    inv[1] =  det3x3(m00, m02, m03, m20, m22, m23, m30, m32, m33) * inv_det; // 11
    inv[2] =  det3x3(m00, m01, m03, m10, m11, m13, m30, m31, m33) * inv_det; // 22
    inv[3] =  det3x3(m00, m01, m02, m10, m11, m12, m20, m21, m22) * inv_det; // 33
    
    inv[4] =  det01 * inv_det; // 01
    inv[5] =  det02 * inv_det; // 02
    inv[6] =  det03 * inv_det; // 03
    
    inv[7] = -det3x3(m00, m01, m03, m20, m21, m23, m30, m31, m33) * inv_det; // 12
    inv[8] =  det3x3(m00, m01, m02, m20, m21, m22, m30, m31, m32) * inv_det; // 13
    
    inv[9] = -det3x3(m00, m01, m02, m10, m11, m12, m30, m31, m32) * inv_det; // 23
    return inv;
}


// ==========================================
// 1. LÉPCSŐ: TISZTA INVERZ KISZÁMÍTÁSA (Pre-compute)
// ==========================================
//Input: OLD-METRIC (10 X f32)
//Output: OLD-INVERZ (10 X f32)
@compute @workgroup_size(4, 4, 4)
fn phase1(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }
    let g = get_metric(OLD, address, METRIC);
    let inv = invert_metric(g);
    set_metric(OLD, address, INVERZ, inv);
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
    if (mu == 1u)      { val_plus = extract_metric_element(p_x_plus, a, b); val_minus = extract_metric_element(p_x_minus, a, b); }
    else if (mu == 2u) { val_plus = extract_metric_element(p_y_plus, a, b); val_minus = extract_metric_element(p_y_minus, a, b); }
    else if (mu == 3u) { val_plus = extract_metric_element(p_z_plus, a, b); val_minus = extract_metric_element(p_z_minus, a, b); }
    return (val_plus - val_minus) * 0.5 * dims.dx;
}


fn get_christoffel_at(address: i32) -> Christoffel40 {
    let p_center  = get_metric(OLD,address, METRIC);
    let g_inverz  = get_metric(OLD,address, INVERZ);
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
            if      (k == 0u) { M = 0u; N = 0u; }
            else if (k == 1u) { M = 1u; N = 1u; }
            else if (k == 2u) { M = 2u; N = 2u; }
            else if (k == 3u) { M = 3u; N = 3u; }
            else if (k == 4u) { M = 0u; N = 1u; }
            else if (k == 5u) { M = 0u; N = 2u; }
            else if (k == 6u) { M = 0u; N = 3u; }
            else if (k == 7u) { M = 1u; N = 2u; }
            else if (k == 8u) { M = 1u; N = 3u; }
            else              { M = 2u; N = 3u; }

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
            else if (k == 8u) { temp_rest.x = val; }
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
//Input: OLD-METRIC (10 X f32),  OLD-INVERZ (10 X f32)
//Output: NEW-CHRISTOFFEL (40 X f32)
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
    if (u == 0u && v == 0u)      { k = 0u; }
    else if (u == 1u && v == 1u) { k = 1u; }
    else if (u == 2u && v == 2u) { k = 2u; }
    else if (u == 3u && v == 3u) { k = 3u; }
    else if (u == 0u && v == 1u) { k = 4u; }
    else if (u == 0u && v == 2u) { k = 5u; }
    else if (u == 0u && v == 3u) { k = 6u; }
    else if (u == 1u && v == 2u) { k = 7u; }
    else if (u == 1u && v == 3u) { k = 8u; }
    else                         { k = 9u; }

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

    return (extract_gamma(ch_plus, L, M, N) - extract_gamma(ch_minus, L, M, N)) * 0.5 * dims.dx;
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

fn compute_ricci(R_tensor: Riemann20, g_inv: MetricPoint) -> MetricPoint {
    var Rc: MetricPoint;
    // Lokális segédfüggvény mintájára a 10 kontrakció legenerálása
    Rc[0] = g_inv[1] * extract_r4(R_tensor,1u,0u,1u,0u) +
            g_inv[2] * extract_r4(R_tensor,2u,0u,2u,0u) +
            g_inv[3] * extract_r4(R_tensor,3u,0u,3u,0u) +
            2.0 * (g_inv[4] * extract_r4(R_tensor,0u,0u,1u,0u) +
                   g_inv[5] * extract_r4(R_tensor,0u,0u,2u,0u) +
                   g_inv[6] * extract_r4(R_tensor,0u,0u,3u,0u) +
                   g_inv[7] * extract_r4(R_tensor,1u,0u,2u,0u) +
                   g_inv[8] * extract_r4(R_tensor,1u,0u,3u,0u) +
                   g_inv[9] * extract_r4(R_tensor,2u,0u,3u,0u));
    
    Rc[1] = g_inv[0] * extract_r4(R_tensor,0u,1u,0u,1u) +
            g_inv[2] * extract_r4(R_tensor,2u,1u,2u,1u) +
            g_inv[3] * extract_r4(R_tensor,3u,1u,3u,1u) +
            2.0 * (g_inv[4] * extract_r4(R_tensor,0u,1u,1u,1u) +
                   g_inv[5] * extract_r4(R_tensor,0u,1u,2u,1u) +
                   g_inv[6] * extract_r4(R_tensor,0u,1u,3u,1u) +
                   g_inv[7] * extract_r4(R_tensor,1u,1u,2u,1u) +
                   g_inv[8] * extract_r4(R_tensor,1u,1u,3u,1u) +
                   g_inv[9] * extract_r4(R_tensor,2u,1u,3u,1u));
    
    Rc[2] = g_inv[0] * extract_r4(R_tensor,0u,2u,0u,2u) +
            g_inv[1] * extract_r4(R_tensor,1u,2u,1u,2u) +
            g_inv[3] * extract_r4(R_tensor,3u,2u,3u,2u) +
            2.0 * (g_inv[4] * extract_r4(R_tensor,0u,2u,1u,2u) +
                   g_inv[5] * extract_r4(R_tensor,0u,2u,2u,2u) +
                   g_inv[6] * extract_r4(R_tensor,0u,2u,3u,2u) +
                   g_inv[7] * extract_r4(R_tensor,1u,2u,2u,2u) +
                   g_inv[8] * extract_r4(R_tensor,1u,2u,3u,2u) +
                   g_inv[9] * extract_r4(R_tensor,2u,2u,3u,2u));
    
    Rc[3] = g_inv[0] * extract_r4(R_tensor,0u,3u,0u,3u) +
            g_inv[1] * extract_r4(R_tensor,1u,3u,1u,3u) +
            g_inv[2] * extract_r4(R_tensor,2u,3u,2u,3u) +
            2.0 * (g_inv[4] * extract_r4(R_tensor,0u,3u,1u,3u) +
                   g_inv[5] * extract_r4(R_tensor,0u,3u,2u,3u) +
                   g_inv[6] * extract_r4(R_tensor,0u,3u,3u,3u) +
                   g_inv[7] * extract_r4(R_tensor,1u,3u,2u,3u) +
                   g_inv[8] * extract_r4(R_tensor,1u,3u,3u,3u) +
                   g_inv[9] * extract_r4(R_tensor,2u,3u,2u,3u));
    
    Rc[4] = g_inv[2] * extract_r4(R_tensor,2u,0u,2u,1u) +
            g_inv[3] * extract_r4(R_tensor,3u,0u,3u,1u) +
            g_inv[4] * (extract_r4(R_tensor,0u,0u,1u,1u) + extract_r4(R_tensor,1u,0u,0u,1u));
    // Vegyes kereszt kontrakciók simplified
    Rc[5] = g_inv[1] * extract_r4(R_tensor,1u,0u,1u,2u) + g_inv[3] * extract_r4(R_tensor,3u,0u,3u,2u);
    Rc[6] = g_inv[1] * extract_r4(R_tensor,1u,0u,1u,3u) + g_inv[2] * extract_r4(R_tensor,2u,0u,2u,3u);
    Rc[7] = g_inv[0] * extract_r4(R_tensor,0u,1u,0u,2u) + g_inv[3] * extract_r4(R_tensor,3u,1u,3u,2u);
    Rc[8] = g_inv[0] * extract_r4(R_tensor,0u,1u,0u,3u) + g_inv[2] * extract_r4(R_tensor,2u,1u,2u,3u);
    Rc[9] = g_inv[0] * extract_r4(R_tensor,0u,2u,0u,3u) + g_inv[1] * extract_r4(R_tensor,1u,2u,1u,3u);
    return Rc;
}

fn compute_ricci_scalar(Rc: MetricPoint, g_inv: MetricPoint) -> f32 {
    return g_inv[0] * Rc[0] +
           g_inv[1] * Rc[1] +
           g_inv[2] * Rc[2] +
           g_inv[3] * Rc[3] +
    2.0 * (g_inv[4] * Rc[4] +
           g_inv[5] * Rc[5] +
           g_inv[6] * Rc[6] +
           g_inv[7] * Rc[7] +
           g_inv[8] * Rc[8] +
           g_inv[9] * Rc[9]);
}

fn compute_kretschmann(R: Riemann20) -> f32 {
    let diagonal = 4.0 * (R.R0101 * R.R0101 + R.R0202 * R.R0202 + R.R0303 * R.R0303 + R.R1212 * R.R1212 + R.R1313 * R.R1313 + R.R2323 * R.R2323);
    let vegyes = 8.0 * (R.R0102 * R.R0102 + R.R0103 * R.R0103 + R.R0203 * R.R0203) + 16.0 * (R.R0112 * R.R0112 + R.R0113 * R.R0113 + R.R0212 * R.R0212 + R.R0223 * R.R0223 + R.R0313 * R.R0313 + R.R0323 * R.R0323);
    let tiszta_ter = 8.0 * (R.R1213 * R.R1213 + R.R1223 * R.R1223 + R.R1323 * R.R1323) + 16.0 * (R.R0123 * R.R0123 + R.R0213 * R.R0213);
    return diagonal + vegyes + tiszta_ter;
}

fn extract_ricci_matrix(Rc: MetricPoint, a: u32, b: u32) -> f32 {
    var u = a;
    var v = b;
    if (a > b) { u = b; v = a; }
    if (u == 0u && v == 0u) { return Rc[0]; }
    if (u == 1u && v == 1u) { return Rc[1]; }
    if (u == 2u && v == 2u) { return Rc[2]; }
    if (u == 3u && v == 3u) { return Rc[3]; }
    if (u == 0u && v == 1u) { return Rc[4]; }
    if (u == 0u && v == 2u) { return Rc[5]; }
    if (u == 0u && v == 3u) { return Rc[6]; }
    if (u == 1u && v == 2u) { return Rc[7]; }
    if (u == 1u && v == 3u) { return Rc[8]; }
    if (u == 2u && v == 3u) { return Rc[9]; }
    return 0.0;
}

// Az általad említett K = C^2 + 2R^2 - 1/3 R^2 azonosság optimális, négyzetes kontrakciója
fn compute_weyl_squared(K: f32, Rc: MetricPoint, g_inv: MetricPoint, R_scalar: f32) -> f32 {
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
    let C2 = K * K - 2.0 * ricci_squared + (1.0 / 3.0) * R_scalar * R_scalar;
    return max(0.0, C2);
}

struct ElectricWeyl5 {
    E11: f32, E22: f32,
    E12: f32, E13: f32, E23: f32,
}

struct MagneticWeyl5 {
    B11: f32, B22: f32,
    B12: f32, B13: f32, B23: f32,
}

fn compute_gravito_electromagnetism(address: i32, R: Riemann20, Rc: MetricPoint, g: MetricPoint, i: MetricPoint) {
    var E: ElectricWeyl5;
    var B: MagneticWeyl5;

    // 1. ELEKTROMOS WEYL-TENZOR (Newtoni árapály-erők és térbeli feszültség)
    E.E11 = R.R0101 - 0.5 * (g[1]*Rc[0] + g[0]*Rc[1]); 
    E.E22 = R.R0202 - 0.5 * (g[2]*Rc[0] + g[0]*Rc[2]);
    
    E.E12 = R.R0102 - 0.5 * (g[4]*Rc[7]); 
    E.E13 = R.R0103 - 0.5 * (g[5]*Rc[8]);
    E.E23 = R.R0203 - 0.5 * (g[7]*Rc[9]);

    // 2. JAVÍTOTT MÁGNESES WEYL-TENZOR (Kizárólag létező Riemann20 mezőkkel!)
    // Ez a tenzor méri a téridő forgásából eredő gravitomágneses nyírófeszültségeket,
    // ami nálad a g12-es oktaéderes elcsavarodási kitörést okozza a Z-tengely mentén.
    B.B11 = -R.R0123; 
    B.B22 = -R.R0213;
    
    B.B12 = -R.R0223;
    B.B13 =  R.R0323;
    B.B23 =  R.R0313;


    // 3. SKALÁR INTENZITÁSOK NÉGYZETÉNEK ÖSSZEGE (Nyommentes tenzorkontrakciók)
    var E_squared = E.E11*E.E11 + E.E22*E.E22 + (E.E11+E.E22)*(E.E11+E.E22) + 2.0*(E.E12*E.E12 + E.E13*E.E13 + E.E23*E.E23);
    if ( isInfNan(E_squared) ) { E_squared = E.E11 * 0.5 + E.E22 * 0.5; }
    var B_squared = B.B11*B.B11 + B.B22*B.B22 + (B.B11+B.B22)*(B.B11+B.B22) + 2.0*(B.B12*B.B12 + B.B13*B.B13 + B.B23*B.B23);
    if ( isInfNan(B_squared) ) { B_squared = B.B11 * 0.5 + B.B22 * 0.5; }

    set_scalar(NEW,address, E_11, E.E11);
    set_scalar(NEW,address, E_22, E.E22);
    set_scalar(NEW,address, E_12, E.E12);
    
    set_scalar(NEW,address, B_11, B.B11);
    set_scalar(NEW,address, B_22, B.B22);
    set_scalar(NEW,address, B_12, B.B12);

    set_scalar(NEW,address, E_SQ, sqrt(E_squared));
    set_scalar(NEW,address, B_SQ, sqrt(B_squared));
}

fn compute_energy_momentum_tensor(g: MetricPoint, k: MetricPoint) -> MetricPoint {
    // Az áramlás sebességvektorai az idő-tér kereszt momentumokból (k01, k02, k03)
    let u1 = k[4]; // X-irányú áramlási sebesség
    let u2 = k[5]; // Y-irányú áramlási sebesség
    let u3 = k[6]; // Z-irányú áramlási sebesség
    
    // Effektív hidrodinamikai energiasűrűség (rho) az örvénylés négyzetéből
    let rho = u1*u1 + u2*u2 + u3*u3;
    
    // Ultra-relativisztikus vagy feszültségi anyagi nyomás-arány (p = rho / 3.0)
    // Ez a nyomás fog a metrika elemeivel szorzódva ellentartani az összeomlásnak!
    let p = rho / 3.0; 
    
    var T: MetricPoint; // 10 elemű üres tenzor
    
    // T_uv = rho * u_u * u_v + p * g_uv DEFINÍCIÓ ALAPJÁN:
    
    // T00 (Energiasűrűség): Mivel g[0] negatív, a p * g[0] tag kivonódik, 
    // stabilizálva a mag belső tömegvonzási energiáját!
    T[0] = rho + p * g[0]; 
    
    // Térbeli nyomások (Centrifugális ellentartás a diagonálisokon)
    T[1] = rho * u1 * u1 + p * g[1]; // T11
    T[2] = rho * u2 * u2 + p * g[2]; // T22
    T[3] = rho * u3 * u3 + p * g[3]; // T33
    
    // IDŐ-TÉR IMPULZUSOK (Vektorpotenciál visszahatása)
    T[4] = rho * u1 + p * g[4]; // T01
    T[5] = rho * u2 + p * g[5]; // T02
    T[6] = rho * u3 + p * g[6]; // T03
    
    // TÉRBELI KERESZT-TAGOK NYOMÁSA (Az abszolút kulcs a g12, g13, g23 elcsavarodási oktaéderek megfékezéséhez!)
    // Ha a g12 (g[7]) elkezd nőni, a p * g[7] tag azonnal megnöveli a T[7]-et, 
    // ami a phase4-ben ellensúlyozza és megállítja a gerjedést!
    T[7] = rho * u1 * u2 + p * g[7]; // T12 
    T[8] = rho * u1 * u3 + p * g[8]; // T13
    T[9] = rho * u2 * u3 + p * g[9]; // T23

    for (var r = 0u; r < 10u; r = r + 1u) {
        if ( isInfNan(T[r]) ) { T[r] = 0.0; }
    }
    
    return T;
}

// ==========================================================
// 3. FÁZIS: GEOMETRIA ÉS FESZÜLTSÉG (Mentés a Múlt inverz helyére!)
// ==========================================================
//Input: OLD-METRIC (10 X f32),  OLD-INVERZ (10 X f32), OLD-MOMENT (10 X f32), NEW-CHRISTOFFEL (40 X f32)
//Output: OLD-RICCI (10 X f32), OLD-ENERGY (10 X f32), NEW-SCALARS (12 X f32)
@compute @workgroup_size(4, 4, 4)
fn phase3(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }
    
    var k_past: MetricPoint;
    if (dims.init_flag == 1u) {
        let g_x_p = get_metric(OLD, next(address, 1, 0, 0), METRIC);
        let g_x_m = get_metric(OLD, next(address,-1, 0, 0), METRIC);
        let g_y_p = get_metric(OLD, next(address, 0, 1, 0), METRIC);
        let g_y_m = get_metric(OLD, next(address, 0,-1, 0), METRIC);
        let g_z_p = get_metric(OLD, next(address, 0, 0, 1), METRIC);
        let g_z_m = get_metric(OLD, next(address, 0, 0,-1), METRIC);
    
        // A legelső körben (t=0) a momentumokat a térbeli elcsavarodás deriváltjaiból generáljuk le!
        // Diagonális momentumok kezdetben zérók statikus/forgó egyensúlynál
        k_past[0] = 0.0; k_past[1] = 0.0; k_past[2] = 0.0; k_past[3] = 0.0;

        // A Kerr-Schild elcsavarodási kereszt-tagok numerikus deriválása:
        // k_ij = 0.5 * (d_i g_0j + d_j g_0i) -> a te extract_metric_element függvényedet használva:
        let d1_g01 = get_deriv(1u, 0u, 1u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m); // M=1, N=(0,1)
        let d1_g02 = get_deriv(1u, 0u, 2u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d2_g01 = get_deriv(2u, 0u, 1u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d1_g03 = get_deriv(1u, 0u, 3u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d3_g01 = get_deriv(3u, 0u, 1u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d2_g02 = get_deriv(2u, 0u, 2u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d2_g03 = get_deriv(2u, 0u, 3u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d3_g02 = get_deriv(3u, 0u, 2u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);
        let d3_g03 = get_deriv(3u, 0u, 3u, g_x_p, g_x_m, g_y_p, g_y_m, g_z_p, g_z_m);

        k_past[4] = d1_g01;                      // k01 = 0.5 * (d_1 g_01 + d_1 g_01) = d_1 g_01
        k_past[5] = 0.5 * (d1_g02 + d2_g01);     // k02
        k_past[6] = 0.5 * (d1_g03 + d3_g01);     // k03
        k_past[7] = d2_g02;                      // k12 = d_2 g_02
        k_past[8] = 0.5 * (d2_g03 + d3_g02);     // k13
        k_past[9] = d3_g03;                      // k23 = d_3 g_03
        set_metric(OLD, address, MOMENT, k_past);
    } else {
        // Ha a szimuláció már fut (init_flag == 0u), a momentumokat normálisan a múltból olvassuk be!
        k_past = get_metric(OLD, address, MOMENT);
    }
    
    let g_past = get_metric(OLD, address, METRIC);
    let i_past = get_metric(OLD, address, INVERZ);    
    let ch_center = load_christoffel_scratchpad(address);
    let T_em = compute_energy_momentum_tensor(g_past, k_past);
    set_metric(OLD, address, ENERGY, T_em);    
    let R20_tensor  = compute_riemann_20(address, ch_center, g_past);
    let Rc_tensor = compute_ricci(R20_tensor, i_past);
    set_metric(OLD, address, RICCI, Rc_tensor);
    
    var R_scalar  = compute_ricci_scalar(Rc_tensor, i_past);
    if ( isInfNan(R_scalar) ) { R_scalar = 0.0; }
    set_scalar(NEW, address, R_SCALAR, R_scalar);
    var K_scalar  = sqrt(compute_kretschmann(R20_tensor));
    if ( isInfNan(K_scalar) ) { K_scalar = 0.0; }
    set_scalar(NEW, address, K_SCALAR, K_scalar);
    var C2_scalar = sqrt(compute_weyl_squared(K_scalar, Rc_tensor, i_past, R_scalar));
    if ( isInfNan(C2_scalar) ) { C2_scalar = 0.0; }
    set_scalar(NEW, address, C2_SCALAR, C2_scalar);

    compute_gravito_electromagnetism(address, R20_tensor, Rc_tensor, g_past, i_past); // write to NEW scalars

}
// ==========================================

// ==========================================================
// 4. FÁZIS: IDŐFEJLESZTÉS - ÚJ MOMENTUMOK (Mentés a Jövő momentum helyére)
// ==========================================================
//Input:  OLD-METRIC (10 X f32),  OLD-MOMENT (10 X f32), OLD-RICCI (10 X f32),  OLD-ENERGY (10 X f32),  NEW-SCALARS (12 X f32)
//Output: NEW-METRIC  (10 X f32), NEW-MOMENT (10 X f32)
@compute @workgroup_size(4, 4, 4)
fn phase4(@builtin(global_invocation_id) coords: vec3<u32>) {
    let address = check_idx(coords);
    if ( address<0 ) { return; }

    let w = i32(dims.width); let h = i32(dims.height); let d = i32(dims.depth);
    let dist_x = min(coords.x, u32(w - 1) - coords.x);
    let dist_y = min(coords.y, u32(h - 1) - coords.y);
    let dist_z = min(coords.z, u32(d - 1) - coords.z);
    let min_wall_dist = min(dist_x, min(dist_y, dist_z));
    var sponge_factor = 1.0;
    // Ha a rácspont a legszélső 6 cellán belül van, fokozatosan elnyeljük az energiát
    if (min_wall_dist < 6u) {
        // 0.0 a legszélén (teljes fojtás), 1.0 a belső tiszta zónában
        sponge_factor = f32(min_wall_dist) / 6.0; 
    }
    let g_past    = get_metric(OLD, address, METRIC);
    let k_past    = get_metric(OLD, address, MOMENT);
    let ricci     = get_metric(OLD, address, RICCI);
    let T_em      = get_metric(OLD, address, ENERGY); // ENERGY_TENSOR slot (A phase3-ból)

    let R_scalar  = get_scalar(NEW, address, R_SCALAR);
    let K_scalar  = get_scalar(NEW, address, K_SCALAR);
    let C2_scalar = get_scalar(NEW, address, C2_SCALAR);
   
    var phi = 0.0;
    // Biztonsági numerikus korlát: ha R nagyon kicsi (pl. sík Minkowski térben), 
    // a csatolás 0 marad, így nem kapunk nullával való osztást!
    if (abs(R_scalar) > 1e-8) {
        phi = 2.0 * (K_scalar + C2_scalar / 3.0) / R_scalar;
    }
    /*else {
        phi = 2.0 * (K_scalar + C2_scalar / 3.0) / 1e-8;
    }*/
    // Stabilizáló konformis osztófaktor a tenzortényezők egymásra hatásából
    let stabilization_factor = 1.0 / (1.0 + phi);

    let alpha = sqrt(max(1e-8, -g_past[0]));    
    // A valós, fizikai időlépés a rácsponton a sajátidő torzulása szerint!
    let local_dt = dims.dt * alpha;

    var k_next: MetricPoint;
    //var g_next: MetricPoint;
    // EGYSÉGES, TELJES 10-ELEMŰ TENZORIÁLIS IDŐFEJLESZTÉS
    for (var r = 0u; r < 10u; r = r + 1u) {
        // Az egyenleted szerinti pontos forrás-tag, ahol a tenzortényezők 
        // egymásra hatása (stabilization_factor) közvetlenül irányítja a Ricci-t!
        let source_term = stabilization_factor * (T_em[r] + 0.5 * R_scalar * g_past[r]) - ricci[r];
        // Euler-időléptetés a momentumra
        var k = k_past[r] + local_dt * source_term * sponge_factor;
        if (isInfNan(k)) {
            k = k_past[r];
        }
        k_next[r] = k;
        
        // Kinematikai időléptetés a metrikára
        //g_next[r] = g_past[r] - local_dt * k_next[r];
        //let diff = (p_x_p[r] + p_x_m[r] + p_y_p[r] + p_y_m[r] + p_z_p[r] + p_z_m[r]) * (1.0/6.0) - g_past[r];
        //g_next[r] = g_next[r] + 0.003 * diff;

    }


    set_metric(NEW, address, MOMENT, k_next);
    set_metric(NEW, address, METRIC, g_past); // temporary    
    set_metric(NEW, address, INVERZ, T_em); // only for check in CPU
    set_metric(NEW, address, RICCI, ricci); // only for check in CPU
    
    set_scalar(NEW, address, BRACKETS, stabilization_factor); // only for check in CPU

}
// ==========================================

// ==========================================================
// 4. FÁZIS: IDŐFEJLESZTÉS - GÁZMODELL
// ==========================================================

@compute @workgroup_size(4, 4, 4)
fn phase4(@builtin(global_invocation_id) id: vec3<u32>) {
    let address = check_idx(id);
    if (address < 0) { return; }

    // 1. BEOLVASSUK A JELENLEGI GÁZ-ÁLLAPOTOT A MÚLTBÓL (40..44-es slotok)
    var W_past = buff_old[address].a[40u]; // sűrűség
    var Vx =     buff_old[address].a[41u]; // sebesség X
    var Vy =     buff_old[address].a[42u]; // sebesség Y
    var Vz =     buff_old[address].a[43u]; // sebesség Z

    // 2. JAVÍTOTT KONTINUUM-LEKÉRDEZÉS (A teljes helybéli momentum-fluxusok deriválása)
    // Először lefejtjük a közvetlen szomszédok sűrűség- ÉS sebességértékeit a múltból (OLD)
    let addr_xp = next(address, +1,  0,  0); let addr_xm = next(address, -1,  0,  0);
    let addr_yp = next(address,  0, +1,  0); let addr_ym = next(address,  0, -1,  0);
    let addr_zp = next(address,  0,  0, +1); let addr_zm = next(address,  0,  0, -1);

    // X-irányú fluxus-különbség: (W * Vx) a jobb oldalon - (W * Vx) a bal oldalon
    let flux_x_p = buff_old[addr_xp].a[40u] * buff_old[addr_xp].a[41u];
    let flux_x_m = buff_old[addr_xm].a[40u] * buff_old[addr_xm].a[41u];
    let dWV_x_dx  = (flux_x_p - flux_x_m) / (2.0 * dims.dx);

    // Y-irányú fluxus-különbség: (W * Vy) fent - (W * Vy) lent
    let flux_y_p = buff_old[addr_yp].a[40u] * buff_old[addr_yp].a[42u];
    let flux_y_m = buff_old[addr_ym].a[40u] * buff_old[addr_ym].a[42u];
    let dWV_y_dy  = (flux_y_p - flux_y_m) / (2.0 * dims.dx);

    // Z-irányú fluxus-különbség: (W * Vz) elöl - (W * Vz) hátul
    let flux_z_p = buff_old[addr_zp].a[40u] * buff_old[addr_zp].a[43u];
    let flux_z_m = buff_old[addr_zm].a[40u] * buff_old[addr_zm].a[43u];
    let dWV_z_dz  = (flux_z_p - flux_z_m) / (2.0 * dims.dx);

    // A TELJES FIZIKAI DIVERGENCIA (A helybéli sűrűség- és sebességváltozások összege)
    let div_W = dWV_x_dx + dWV_y_dy + dWV_z_dz;

    // 3. IDŐLÉPÉS (Léptetjük a gázt a te dims.dt időlépéseddel)
    let W_new = W_past - dims.dt * div_W;


    // 4. A MEXIKÓI KALAP NYOMÁS-VISSZACSATOLÁS
    // Ha a W sűrűség túl nagy a magban (összeomlás), a kalap völgye miatt a P_gas megugrik
    let W_target = 1.0; // Alapértelmezett egyensúlyi téridő-sűrűség
    let P_gas = 100.0 * (W_past - W_target) * (W_past - W_target) * (W_past - W_target);

    // A gravitációs feszültség (brackets) befelé rántja a gázt, de a belső nyomás (P_gas) 
    // centrifugálisan elcsavarja a sebességeket, létrehozva a stabil keringést!
    let brackets = buff_old[address].a[19u]; // 19: feszültség a phase3-ból
    let Vx_new = Vx + dims.dt * (brackets * Vx - P_gas * (W_right - W_left));
    let Vy_new = Vy + dims.dt * (brackets * Vy - P_gas * (W_up - W_down));

    // 5. METRIKA LÉPTETÉSE A GÁZSŰRŰSÉG ALAPJÁN (A konformis visszacsatolás)
    // Ahelyett, hogy a metrika szabadon elszállna, a téridő-gáz sűrűségével (W_new) 
    // hajszálpontosan moduláljuk a változását, ami GARANTÁLTAN megállítja a horizont-túlcsordulást!
    let g_past = get_metric(OLD, address, 0);
    let k_past = get_metric(OLD, address, 2);
    let Ricci  = get_metric(OLD, address, 3);

    var next_k: MetricPoint;
    var next_g: MetricPoint;
    for (var r = 0u; r < 10u; r = r + 1u) {
        // A gáznyomás (P_gas) és sűrűség (W_new) közvetlenül kiegyenlíti a tenzorelemek futását!
        next_k[r] = k_past[r] + dims.dt * (brackets * g_past[r] - Ricci[r] + P_gas * g_past[r]);
        next_g[r] = g_past[r] - 2.0 * dims.dt * next_k[r] * (1.0 / (max(0.1, W_new)));
    }

    // MENTÉS A JÖVŐBE (NEW)
    set_metric(NEW, address, 2, next_k);
    set_metric(NEW, address, 0, next_g);
    
    // Elmentjük a friss gáz-változókat a 40..44-es helyre
    buff_new[address].a[40u] = W_new;
    buff_new[address].a[41u] = Vx_new;
    buff_new[address].a[42u] = Vy_new;
    buff_new[address].a[43u] = Vz;
    buff_new[address].a[44u] = P_gas;

    // Átforgatjuk a többi zónát a phase5_copy-hoz
    for(var s = 10; s < 40; s++) { buff_new[address].a[s] = buff_old[address].a[s]; }
    for(var s = 45; s < 50; s++) { buff_new[address].a[s] = buff_old[address].a[s]; }
}

// ==========================================================
// 5. FÁZIS: JÖVŐBELI ÁLLAPOT VISSZAMÁSOLÁSA A MÚLTBA (In-place Reset)
// ==========================================================
// copy NEW to OLD
@compute @workgroup_size(4, 4, 4)
fn phase5(@builtin(global_invocation_id) id: vec3<u32>) {
    // Határellenőrzés a te check_idx függvényeddel
    let address = check_idx(id);
    if (address < 0) { return; }
    
    let adr_x_p = next(address, 1, 0, 0);
    let adr_x_m = next(address,-1, 0, 0);
    let adr_y_p = next(address, 0, 1, 0);
    let adr_y_m = next(address, 0,-1, 0);
    let adr_z_p = next(address, 0, 0, 1);
    let adr_z_m = next(address, 0, 0,-1);
    
    let k_past = get_metric(NEW, address, MOMENT);
    let k_x_p  = get_metric(NEW, adr_x_p, MOMENT);
    let k_x_m  = get_metric(NEW, adr_x_m, MOMENT);
    let k_y_p  = get_metric(NEW, adr_y_p, MOMENT);
    let k_y_m  = get_metric(NEW, adr_y_m, MOMENT);
    let k_z_p  = get_metric(NEW, adr_z_p, MOMENT);
    let k_z_m  = get_metric(NEW, adr_z_m, MOMENT);
    
    let g_past = get_metric(NEW, address, METRIC);
    let g_x_p  = get_metric(NEW, adr_x_p, METRIC);
    let g_x_m  = get_metric(NEW, adr_x_m, METRIC);
    let g_y_p  = get_metric(NEW, adr_y_p, METRIC);
    let g_y_m  = get_metric(NEW, adr_y_m, METRIC);
    let g_z_p  = get_metric(NEW, adr_z_p, METRIC);
    let g_z_m  = get_metric(NEW, adr_z_m, METRIC);
    
    let alpha = sqrt(max(1e-4, abs(g_past[0])));    
    let local_dt = dims.dt * alpha;

    var k_next: MetricPoint;
    var g_next: MetricPoint;
    // EGYSÉGES, TELJES 10-ELEMŰ TENZORIÁLIS IDŐFEJLESZTÉS
    for (var r = 0u; r < 10u; r = r + 1u) {
        let diff_k = (k_x_p[r] + k_x_m[r] + k_y_p[r] + k_y_m[r] + k_z_p[r] + k_z_m[r]) * (1.0/6.0) - k_past[r];
        k_next[r] = k_past[r] + 0.002 * diff_k;

        // Kinematikai időléptetés a metrikára
        let diff_g = (g_x_p[r] + g_x_m[r] + g_y_p[r] + g_y_m[r] + g_z_p[r] + g_z_m[r]) * (1.0/6.0) - g_past[r];
        var g = g_past[r] - local_dt * k_next[r] + 0.001 * diff_g;
        if (isInfNan(g)) {
            g = g_past[r];
        }
        g_next[r] = g;

    }

    set_metric(OLD, address, MOMENT, k_next);
    set_metric(OLD, address, METRIC, g_next);

    for (var s = 20; s < 52; s = s + 1) {
        buff_old[address].a[s] = buff_new[address].a[s];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

