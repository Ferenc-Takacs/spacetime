struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dxyz: f32,
    dt: f32,
    step_index: u32,
    pad1: u32,
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

fn next_(address: i32, dx: i32, dy: i32, dz: i32 ) -> i32 {
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

fn next(address: i32, dx: i32, dy: i32, dz: i32 ) -> i32 {
    let w = i32(dims.width);
    let h = i32(dims.height);
    let d = i32(dims.depth);
    let a = address / w;
    var x = address - a * w;
    var z = a / h;
    var y = a - z * h;
    x = x + dx;
    y = y + dy;
    z = z + dz;
    if (x < 0 || x >= w || y < 0 || y >= h || z < 0 || z >= d) {
        return -1;
    }
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

/*
const to_idx = array(
    0u, 4u, 5u, 6u,
    4u, 1u, 7u, 8u,
    5u, 7u, 2u, 9u,
    6u, 8u, 9u, 3u);
const from_idx0 = array(0u,1u,2u,3u,0u,0u,0u,1u,1u,2u);
const from_idx1 = array(0u,1u,2u,3u,1u,2u,3u,2u,3u,3u);
*/

fn To_idx(a: u32, b: u32) -> u32 {
    if( a==b ) { return a; }
    var A = a;
    var B = b;
    if(a>b ) { A = b; B = a; }
    if( A==0 && B==1) { return 4; }
    if( A==0 && B==2) { return 5; }
    if( A==0 && B==3) { return 6; }
    if( A==1 && B==2) { return 7; }
    if( A==1 && B==3) { return 8; }
    return 9;
}

struct Derive {
    g_center: MetricPoint,
    g_x_p: MetricPoint,
    g_x_m: MetricPoint,
    g_y_p: MetricPoint,
    g_y_m: MetricPoint,
    g_z_p: MetricPoint,
    g_z_m: MetricPoint,
    d_x: f32,
    d_y: f32,
    d_z: f32,
}

fn get_deriv(mu: u32, a: u32, b: u32, d: Derive) -> f32 {
    if (mu == 0u) {
        if (a == 0u && b == 0u) {
            // 1. LÉPÉS: A g00 elem tiszta térbeli gradiensei (d.d_x tartalmazza a rácssimítást!)
            let dx_g00 = (d.g_x_p[0u] - d.g_x_m[0u]) * d.d_x;
            let dy_g00 = (d.g_y_p[0u] - d.g_y_m[0u]) * d.d_y;
            let dz_g00 = (d.g_z_p[0u] - d.g_z_m[0u]) * d.d_z;
            // 2. LÉPÉS: A helyi áramlási sebességek (súlyok) kiolvasása a kereszt-komponensekből (g0i)
            let v_x = d.g_center[1u]; // g01 komponens
            let v_y = d.g_center[2u]; // g02 komponens
            let v_z = d.g_center[3u]; // g03 komponens
            // 3. LÉPÉS: A Folyó-modell szerinti súlyozott konvektív összegzés
            // A sebességvektorok és gradiensek szorzata másodpercenkénti változást ad ki, amit beszorzunk dims.dt-vel
            let dt_g00 = (v_x * dx_g00 + v_y * dy_g00 + v_z * dz_g00) * dims.dt;
            return dt_g00;
        }
        return 0.0;
    }
    else if (mu == 1u) { return (d.g_x_p[To_idx(a,b)] - d.g_x_m[To_idx(a,b)]) * d.d_x; }
    else if (mu == 2u) { return (d.g_y_p[To_idx(a,b)] - d.g_y_m[To_idx(a,b)]) * d.d_y; }
    else               { return (d.g_z_p[To_idx(a,b)] - d.g_z_m[To_idx(a,b)]) * d.d_z; }
}

fn get_christoffel_at(address: i32, d: i32) -> Christoffel40 {
    let g_inverz  = get_metric(OLD,address, INVERZ);
    var der: Derive;
    der.g_center = get_metric(OLD,address, METRIC);
    let adr_x_p = next(address, d, 0, 0);
    let adr_x_m = next(address,-d, 0, 0);
    if( adr_x_p < 0 ) {
        der.g_x_m = get_metric(OLD,adr_x_m, METRIC);
        //der.g_x_p = der.g_center; der.d_x = 1.0 / ( dims.dxyz + dims.dt * sqrt(max(1e-8, -der.g_center[0])));
        if( d == 2 ) {
            let ad_x_p = next(address, 1, 0, 0);
            if( ad_x_p < 0 ) { der.g_x_p = der.g_center; der.d_x = 1.0 / (2.0 * dims.dxyz); }
            else { der.g_x_p = get_metric(OLD,ad_x_p, METRIC); der.d_x = 1.0 / (3.0 * dims.dxyz); }
        }
        else { der.g_x_p = der.g_center; der.d_x = 1.0 / dims.dxyz; }
    }
    else if( adr_x_m < 0 ){ // adr_x_m < 0
        der.g_x_p = get_metric(OLD,adr_x_p, METRIC);
        //der.g_x_m = der.g_center; der.d_x = 1.0 / ( dims.dxyz + dims.dt * sqrt(max(1e-8, -der.g_center[0])));
        if( d == 2 ) {
            let ad_x_m = next(address,-1, 0, 0);
            if( ad_x_m < 0 ) { der.g_x_m = der.g_center; der.d_x = 1.0 / (2.0 * dims.dxyz); }
            else { der.g_x_m = get_metric(OLD,ad_x_m, METRIC); der.d_x = 1.0 / (3.0 * dims.dxyz); }
        }
        else { der.g_x_m = der.g_center; der.d_x = 1.0 / dims.dxyz; }
    }
    else {
        der.g_x_p = get_metric(OLD,adr_x_p, METRIC);
        der.g_x_m = get_metric(OLD,adr_x_m, METRIC);
        der.d_x = 1.0 / (2.0 * f32(d) * dims.dxyz);
    }
    
    let adr_y_p = next(address, 0, d, 0);
    let adr_y_m = next(address, 0,-d, 0);
    if( adr_y_p < 0 ) {
        der.g_y_m = get_metric(OLD,adr_y_m, METRIC);
        //der.g_y_p = der.g_center; der.d_y = 1.0 / ( dims.dxyz + dims.dt * sqrt(max(1e-8, -der.g_center[0])));
        if( d == 2 ) {
            let ad_y_p = next(address, 0, 1, 0);
            if( ad_y_p < 0 ) { der.g_y_p = der.g_center; der.d_y = 1.0 / (2.0 * dims.dxyz); }
            else { der.g_y_p = get_metric(OLD,ad_y_p, METRIC); der.d_y = 1.0 / (3.0 * dims.dxyz); }
        }
        else { der.g_y_p = der.g_center; der.d_y = 1.0 / dims.dxyz; }
    }
    else if( adr_y_m < 0 ){ // adr_y_m < 0
        der.g_y_p = get_metric(OLD,adr_y_p, METRIC);
        //der.g_y_m = der.g_center; der.d_y = 1.0 / ( dims.dxyz + dims.dt * sqrt(max(1e-8, -der.g_center[0])));
        if( d == 2 ) {
            let ad_y_m = next(address, 0,-1, 0);
            if( ad_y_m < 0 ) { der.g_y_m = der.g_center; der.d_y = 1.0 / (2.0 * dims.dxyz); }
            else { der.g_y_m = get_metric(OLD,ad_y_m, METRIC); der.d_y = 1.0 / (3.0 * dims.dxyz); }
        }
        else { der.g_y_m = der.g_center; der.d_y = 1.0 / dims.dxyz; }
    }
    else {
        der.g_y_p = get_metric(OLD,adr_y_p, METRIC);
        der.g_y_m = get_metric(OLD,adr_y_m, METRIC);
        der.d_y = 1.0 / (2.0 * f32(d) * dims.dxyz);
    }
    
    let adr_z_p = next(address, 0, 0, d);
    let adr_z_m = next(address, 0, 0,-d);
    if( adr_z_p < 0 ) {
        der.g_z_m = get_metric(OLD,adr_z_m, METRIC);
        //der.g_z_p = der.g_center; der.d_z = 1.0 / ( dims.dxyz + dims.dt * sqrt(max(1e-8, -der.g_center[0])));
        if( d == 2 ) {
            let ad_z_p = next(address, 0, 0, 1);
            if( ad_z_p < 0 ) { der.g_z_p = der.g_center; der.d_z = 1.0 / (2.0 * dims.dxyz); }
            else { der.g_z_p = get_metric(OLD,ad_z_p, METRIC); der.d_z = 1.0 / (3.0 * dims.dxyz); }
        }
        else { der.g_z_p = der.g_center; der.d_z = 1.0 / dims.dxyz; }
    }
    else if( adr_z_m < 0 ) { // adr_z_m < 0
        der.g_z_p = get_metric(OLD,adr_z_p, METRIC);
        //der.g_z_m = der.g_center; der.d_z = 1.0 / ( dims.dxyz + dims.dt * sqrt(max(1e-8, -der.g_center[0])));
        if( d == 2 ) {
            let ad_z_m = next(address, 0, 0,-1);
            if( ad_z_m < 0 ) { der.g_z_m = der.g_center; der.d_z = 1.0 / (2.0 * dims.dxyz); }
            else { der.g_z_m = get_metric(OLD,ad_z_m, METRIC); der.d_z = 1.0 / (3.0 * dims.dxyz); }
        }
        else { der.g_z_m = der.g_center; der.d_z = 1.0 / dims.dxyz; }
    }
    else {
        der.g_z_p = get_metric(OLD,adr_z_p, METRIC);
        der.g_z_m = get_metric(OLD,adr_z_m, METRIC);
        der.d_z = 1.0 / (2.0 * f32(d) * dims.dxyz);
    }

    var chris: Christoffel40;
    for (var L = 0u; L < 4u; L++) {
        var tmp : MetricPoint;
        for (var k = 0u; k < 10u; k++) {
            var M = k;
            var N = k;
            if( k==4u )      { M=0u; N=1u; }
            else if( k==5u ) { M=0u; N=2u; }
            else if( k==6u ) { M=0u; N=3u; }
            else if( k==7u ) { M=1u; N=2u; }
            else if( k==8u ) { M=1u; N=3u; }
            else if( k==9u ) { M=2u; N=3u; }
            var val = 0.0;
            for (var sig = 0u; sig < 4u; sig++) {
                let inv_g_L_sig = g_inverz[To_idx(L,sig)];
                let dM_gNsig = get_deriv(M, N, sig, der);
                let dN_gMsig = get_deriv(N, M, sig, der);
                let dsig_gMN = get_deriv(sig, M, N, der);
                val += 0.5 * inv_g_L_sig * (dM_gNsig + dN_gMsig - dsig_gMN);
            }
            tmp[k] = val;
        }
        for (var k = 0u; k < 10u; k++) {
            let i = L*10+k;
            chris[i] = tmp[k];
        }
    }
    return chris;
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

    let ch1 = get_christoffel_at(address,1);
    let ch2 = get_christoffel_at(address,2);
    var ch: Christoffel40;
    for (var i = 0u; i < 40u; i++) {
        ch[i] = (ch1[i] + ch2[i]) * 0.5;
    }
    store_christoffel_scratchpad(ch, address);
}
// ==========================================

fn deriv_gamma(address: i32, L: u32, M: u32, N: u32, dir: u32) -> f32 {
    var coords_plus  = address; var coords_minus = address;
    if (dir == 1u)      { coords_plus = next(address, 1, 0, 0); coords_minus = next(address, -1, 0, 0); }
    else if (dir == 2u) { coords_plus = next(address, 0, 1, 0); coords_minus = next(address, 0, -1, 0); }
    else if (dir == 3u) { coords_plus = next(address, 0, 0, 1); coords_minus = next(address, 0, 0, -1); }

    var ch_plus: Christoffel40;
    var ch_minus: Christoffel40;
    var mul = 0.5 / dims.dxyz;
    if (coords_plus < 0 ) { ch_plus = load_christoffel_scratchpad(address); mul = mul * 2.0; }
    else { ch_plus  = load_christoffel_scratchpad(coords_plus); }
    if (coords_minus < 0) { ch_minus = load_christoffel_scratchpad(address); mul = mul * 2.0; }
    else { ch_minus  = load_christoffel_scratchpad(coords_minus); }

    let idx = L * 10u + To_idx(M,N);
    return (ch_plus[idx] - ch_minus[idx]) * mul;
}

fn get_riemann_element(address: i32, chris: Christoffel40, L: u32, M: u32, N: u32, nu: u32) -> f32 {
    // Riemann formula: d_N Gamma^L_M_nu - d_nu Gamma^L_M_N + Gamma * Gamma tagok
    let term_deriv = deriv_gamma(address, L, M, nu, N) - deriv_gamma(address, L, M, N, nu);
    var term_nonlinear = 0.0;
    for (var s = 0u; s < 4u; s = s + 1u) {
        term_nonlinear += chris[L * 10u + To_idx(s,N)]  * chris[s * 10u + To_idx(M,nu)] 
                        - chris[L * 10u + To_idx(s,nu)] * chris[s * 10u + To_idx(M,N)];
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


fn compute_riemann_20(address: i32, chris: Christoffel40, g: MetricPoint) -> Riemann20 {
    var R: Riemann20;
    // Segéd-vektor az index leengedéséhez (R_abcd = g_am * R^m_bcd)
    var R_up = vec4(0.0);
    
    // 1. Blokk: Tiszta átlós bindex elemek
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,1u,0u,1u); }
    R.R0101 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,0u,2u); }
    R.R0202 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,3u,0u,3u); }
    R.R0303 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,1u,2u); }
    R.R1212 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,3u,1u,3u); }
    R.R1313 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,3u,2u,3u); }
    R.R2323 = g[5] * R_up.x + g[7] * R_up.y + g[2] * R_up.z + g[9] * R_up.w;
    
    // 2. Blokk: Kereszt-tagok
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,1u,0u,2u); }
    R.R0102 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,1u,0u,3u); }
    R.R0103 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,0u,3u); }
    R.R0203 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,1u,1u,2u); }
    R.R0112 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,1u,1u,3u); }
    R.R0113 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,1u,2u); }
    R.R0212 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,2u,3u); }
    R.R0223 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,3u,1u,3u); }
    R.R0313 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,3u,2u,3u); }
    R.R0323 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    
    // 3. Blokk: Térbeli vegyes tagok
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,1u,3u); }
    R.R1213 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,2u,3u); }
    R.R1223 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,3u,2u,3u); }
    R.R1323 = g[4] * R_up.x + g[1] * R_up.y + g[7] * R_up.z + g[8] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,1u,2u,3u); }
    R.R0123 = g[0] * R_up.x + g[4] * R_up.y + g[5] * R_up.z + g[6] * R_up.w;
    for(var m=0u; m<4u; m++)
        { R_up[m] = get_riemann_element(address,chris,m,2u,1u,3u); }
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
                    let g_ua = g_inv[To_idx(u,a)];
                    let g_vb = g_inv[To_idx(v,b)];
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
    //if ( isInfNan(E_squared) ) { E_squared = E.E11 * 0.5 + E.E22 * 0.5; }
    var B_squared = B.B11*B.B11 + B.B22*B.B22 + (B.B11+B.B22)*(B.B11+B.B22) + 2.0*(B.B12*B.B12 + B.B13*B.B13 + B.B23*B.B23);
    //if ( isInfNan(B_squared) ) { B_squared = B.B11 * 0.5 + B.B22 * 0.5; }

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

    //for (var r = 0u; r < 10u; r = r + 1u) {
    //    if ( isInfNan(T[r]) ) { T[r] = 0.0; }
    //}
    
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
    
    let g_past = get_metric(OLD, address, METRIC);
    let k_past = get_metric(OLD, address, MOMENT);
    
    let i_past = get_metric(OLD, address, INVERZ);
    let chris = load_christoffel_scratchpad(address);
    let T_em = compute_energy_momentum_tensor(g_past, k_past);
    set_metric(OLD, address, ENERGY, T_em);    
    let R20_tensor  = compute_riemann_20(address, chris, g_past);
    let Rc_tensor = compute_ricci(R20_tensor, i_past);
    set_metric(OLD, address, RICCI, Rc_tensor);
    
    var R_scalar  = compute_ricci_scalar(Rc_tensor, i_past);
    //if ( isInfNan(R_scalar) ) { R_scalar = 0.0; }
    set_scalar(NEW, address, R_SCALAR, R_scalar);
    var K_scalar  = sqrt(compute_kretschmann(R20_tensor));
    //if ( isInfNan(K_scalar) ) { K_scalar = 0.0; }
    set_scalar(NEW, address, K_SCALAR, K_scalar);
    var C2_scalar = sqrt(compute_weyl_squared(K_scalar, Rc_tensor, i_past, R_scalar));
    //if ( isInfNan(C2_scalar) ) { C2_scalar = 0.0; }
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

    var sponge_factor = 1.0;
    //let sponge_len = 4u;
    //let w = i32(dims.width); let h = i32(dims.height); let d = i32(dims.depth);
    //let dist_x = min(coords.x, u32(w - 1) - coords.x);
    //let dist_y = min(coords.y, u32(h - 1) - coords.y);
    //let dist_z = min(coords.z, u32(d - 1) - coords.z);
    
    
    //if (dist_x < sponge_len) {
    //    sponge_factor = sponge_factor * f32(dist_x) / f32(sponge_len); 
    //}
    //if (dist_y < sponge_len) {
    //    sponge_factor = sponge_factor * f32(dist_y) / f32(sponge_len); 
    //}
    //if (dist_z < sponge_len) {
    //    sponge_factor = sponge_factor * f32(dist_z) / f32(sponge_len); 
    //}
    
    
    // Ha a rácspont a legszélső 6 cellán belül van, fokozatosan elnyeljük az energiát
    //let min_wall_dist = min(dist_x, min(dist_y, dist_z));
    //if (min_wall_dist < sponge_len) {
    //    // 0.0 a legszélén (teljes fojtás), 1.0 a belső tiszta zónában
    //    sponge_factor = f32(min_wall_dist) / f32(sponge_len); 
    //}
    let g_past    = get_metric(OLD, address, METRIC);
    let k_past    = get_metric(OLD, address, MOMENT);
    let ricci     = get_metric(OLD, address, RICCI);
    let T_em      = get_metric(OLD, address, ENERGY); // ENERGY_TENSOR slot (A phase3-ból)

    let R_scalar  = get_scalar(NEW, address, R_SCALAR);
    let K_scalar  = get_scalar(NEW, address, K_SCALAR) * sponge_factor;;
    var C2_scalar = get_scalar(NEW, address, C2_SCALAR) * sponge_factor;;
    if (C2_scalar > 150.0) {
        C2_scalar = 150.0;
    }
    
    let ell_P_negyzet = 0.01;
    let phi = ell_P_negyzet * ((2.0 / 3.0) * K_scalar + (3.0 / 2.0) * C2_scalar);
    // Stabilizáló konformis osztófaktor a tenzortényezők egymásra hatásából
    let stabilization_factor = 1.0 / (1.0 + phi);

    let alpha = sqrt(max(1e-8, -g_past[0]));    
    // A valós, fizikai időlépés a rácsponton a sajátidő torzulása szerint!
    let local_dt = dims.dt * alpha;

    var k_next: MetricPoint;
    //var g_next: MetricPoint;
    // EGYSÉGES, TELJES 10-ELEMŰ TENZORIÁLIS IDŐFEJLESZTÉS
    // EGYSÉGES, TELJES 10-ELEMŰ TENZORIÁLIS IDŐFEJLESZTÉS
    for (var r = 0u; r < 10u; r = r + 1u) {        
        let systematic_distribution = g_past[r] - (ricci[r] / (abs(R_scalar) + 1e-4));        
        let source_term = stabilization_factor * T_em[r] + (local_dt * phi) * systematic_distribution;
        
        // 1. LÉPÉS: A komplementer feszültség-kapcsoló kiszámítása pontról pontra.
        // Ha az adott irányban (pl. ricci[r]) már túl nagy a feszültség, ez a tag 
        // lefojtja azt, és a megmaradó energiát átirányítja a szabad, nulla értékű helyekre!
        //let complementer_tension = g_past[r] * R_scalar - ricci[r];
        
        // 2. LÉPÉS: Az anizotróp tértágulási forrás (phi) helyi, irányított felépítése
        // A gamma=2/3 és delta=3/2 kétlépcsős kalibráció, szorozva a Planck-négyzettel (ami itt 1.0)
        //let local_phi = ell_P_negyzet * (2.0 / 3.0) * K_scalar + (3.0 / 2.0) * C2_scalar;
        // 3. LÉPÉS: A javított, golyóálló Forrás-tag felírása
        // A lambda-tag most már nem szorozza vakon a meglévő csúcsot, hanem az 
        // új complementer_tension operátoron keresztül a szabad irányokat pumpálja!
        //let source_term = T_em[r] + phi * complementer_tension - ricci[r];        
        
        let source_term_capped = clamp(source_term, -30.0, 30.0);
        // Euler-időléptetés a momentumra
        var k = (k_past[r] + local_dt * source_term_capped);// * sponge_factor;
        // Túlcsordulás és NaN elleni szoftveres védőgát feloldása
        //if (isInfNan(k)) {
        //    k = k_past[r] * 0.5; // Ha instabillá válna, finoman visszahúzzuk a rácsot
        //}
        k_next[r] = k;
    }

    set_metric(NEW, address, MOMENT, k_next);
    set_metric(NEW, address, METRIC, g_past); // temporary    
    set_metric(NEW, address, INVERZ, T_em); // only for check in CPU
    set_metric(NEW, address, RICCI, ricci); // only for check in CPU
    
    set_scalar(NEW, address, BRACKETS, stabilization_factor); // only for check in CPU

}
// ==========================================

// ==========================================================
// 5. FÁZIS: JÖVŐBELI ÁLLAPOT VISSZAMÁSOLÁSA A MÚLTBA (In-place Reset)
// ==========================================================
// copy NEW to OLD
@compute @workgroup_size(4, 4, 4)
fn phase5(@builtin(global_invocation_id) id: vec3<u32>) {
    // Határellenőrzés a te check_idx függvényeddel
    let address = check_idx(id);
    if (address < 0) { return; }
    let k_past = get_metric(NEW, address, MOMENT);
    
    let adr_x_p = next(address, 1, 0, 0);
    let adr_x_m = next(address,-1, 0, 0);
    let adr_y_p = next(address, 0, 1, 0);
    let adr_y_m = next(address, 0,-1, 0);
    let adr_z_p = next(address, 0, 0, 1);
    let adr_z_m = next(address, 0, 0,-1);
    var num = 0.0;
    var k_avr: MetricPoint;
    if( adr_x_p >= 0 ) {
        let m = get_metric(NEW, adr_x_p, MOMENT);
        for( var r = 0u; r < 10u; r = r + 1u) { k_avr[r] = k_avr[r] + m[r]; }
        num = num + 1.0; }
    if( adr_x_m >= 0 ) {
        let m = get_metric(NEW, adr_x_m, MOMENT);
        for( var r = 0u; r < 10u; r = r + 1u) { k_avr[r] = k_avr[r] + m[r]; }
        num = num + 1.0; }
    if( adr_y_p >= 0 ) {
        let m = get_metric(NEW, adr_y_p, MOMENT);
        for( var r = 0u; r < 10u; r = r + 1u) { k_avr[r] = k_avr[r] + m[r]; }
        num = num + 1.0; }
    if( adr_y_m >= 0 ) {
        let m = get_metric(NEW, adr_y_m, MOMENT);
        for( var r = 0u; r < 10u; r = r + 1u) { k_avr[r] = k_avr[r] + m[r]; }
        num = num + 1.0; }
    if( adr_z_p >= 0 ) {
        let m = get_metric(NEW, adr_z_p, MOMENT);
        for( var r = 0u; r < 10u; r = r + 1u) { k_avr[r] = k_avr[r] + m[r]; }
        num = num + 1.0; }
    if( adr_z_m >= 0 ) {
        let m = get_metric(NEW, adr_z_m, MOMENT);
        for( var r = 0u; r < 10u; r = r + 1u) { k_avr[r] = k_avr[r] + m[r]; }
        num = num + 1.0; }
    
    //let g_x_p  = get_metric(NEW, adr_x_p, METRIC);
    //let g_x_m  = get_metric(NEW, adr_x_m, METRIC);
    //let g_y_p  = get_metric(NEW, adr_y_p, METRIC);
    //let g_y_m  = get_metric(NEW, adr_y_m, METRIC);
    //let g_z_p  = get_metric(NEW, adr_z_p, METRIC);
    //let g_z_m  = get_metric(NEW, adr_z_m, METRIC);
    
    let g_past = get_metric(NEW, address, METRIC);
    let alpha = sqrt(max(1e-4, abs(g_past[0])));    
    let local_dt = dims.dt * alpha;

    var k_next: MetricPoint;
    var g_next: MetricPoint;
    // EGYSÉGES, TELJES 10-ELEMŰ TENZORIÁLIS IDŐFEJLESZTÉS
    for (var r = 0u; r < 10u; r = r + 1u) {
        let diff_k = (k_avr[r]/num - k_past[r])*(7.0-num);
        k_next[r] = k_past[r] + 0.008 * diff_k;

        // Kinematikai időléptetés a metrikára
        //let diff_g = (g_x_p[r] + g_x_m[r] + g_y_p[r] + g_y_m[r] + g_z_p[r] + g_z_m[r]) * (1.0/6.0) - g_past[r];
        var g = g_past[r] - local_dt * k_next[r];// + 0.001 * diff_g;
        //if (isInfNan(g)) {
        //    g = g_past[r];
        //}
        g_next[r] = g;

    }

    set_metric(OLD, address, MOMENT, k_next);
    set_metric(OLD, address, METRIC, g_next);

    for (var s = 20; s < 52; s = s + 1) {
        buff_old[address].a[s] = buff_new[address].a[s];
    }
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

