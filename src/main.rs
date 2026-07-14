use bytemuck::*;
use wgpu::util::DeviceExt; // Ez a trait kell a könyvjelző-alapú buffer létrehozáshoz

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dx: f32, // Tűpontosan 4 bájt, az igazítás sértetlen marad
}

// Egy aszinkron függvény, mivel a wgpu inicializálása async
async fn run() {
    // 1. Definiáljuk a rács méreteit (pl. egy 64x64x64-es kocka a térben)
    let width = 64;
    let height = 64;
    let depth = 64;
    let dx_space:f32 = 0.1;
    
    // Létrehozzuk a kezdeti rácsot a CPU oldalon (egyelőre csupa nullával feltöltve)
    let mut grid = SpacetimeGrid::new(width, height, depth, dx_space);
    
    // --- Tesztadatok feltöltése (opcionális példa a teszteléshez) ---
    // Itt szimulálhatsz egy kezdeti Minkowski (sík) metrikát: g00=-1, g11=1, g22=1, g33=1
    for point in grid.data.iter_mut() {
        point.g00 = -1.0;
        point.g11 = 1.0;
        point.g22 = 1.0;
        point.g33 = 1.0;
    }

    // 2. Alapvető WGPU objektumok inicializálása (Instance, Adapter, Device, Queue)
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::DX12, // Kényszerített DX12 a Vulkan crash elkerülésére
        flags: wgpu::InstanceFlags::default(),
        backend_options: wgpu::BackendOptions::default(),
        display: None, // Compute (ablak nélküli) feladatoknál ez fixen None
        memory_budget_thresholds: wgpu::MemoryBudgetThresholds::default(), // Alapértelmezett memóriakorlátok

    });

    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
            apply_limit_buckets: false, 
        })
        .await
        .expect("Nem található megfelelő GPU adapter!");


    let (device, queue) = adapter
        .request_device(
            &wgpu::DeviceDescriptor {
                label: Some("Spacetime Device"),
                required_features: wgpu::Features::empty(),
                // Új kötelező mező: letiltjuk a kísérleti funkciókat a stabilitásért
                experimental_features: wgpu::ExperimentalFeatures::disabled(),
                required_limits: wgpu::Limits::default(),
                memory_hints: wgpu::MemoryHints::default(),
                // Új kötelező mező: kikapcsoljuk az API hívások nyomon követését (fájlba írását)
                trace: wgpu::Trace::Off,
            },
        )
        .await
        .unwrap();


    // 3. A BEMENETI METRIKA STORAGE BUFFER LÉTREHOZÁSA (Input Grid)
    // A `create_buffer_init` automatikusan kiszámítja a méretet és feltölti a 'grid.data' bájtaival
    let input_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("Input Spacetime Grid Buffer"),
        contents: bytemuck::cast_slice(&grid.data),
        // STORAGE: elérhető a compute shaderben, COPY_DST: írható a CPU felől később is
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
    });



    let dims_data = GridDimensions { width, height, depth, dx: dx_space };
    let dims_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("Grid Dimensions Uniform Buffer"),
        contents: bytemuck::bytes_of(&dims_data),
        usage: wgpu::BufferUsages::UNIFORM,
    });



    // 4. A KIMENETI INVARIÁNS BUFFER LÉTREHOZÁSA (Output Invariants)
    // Ide fogja a GPU írni a rácspontonkénti 1 darab f32-es eredményt (pl. Kretschmann-skálát)
    let total_points = (width * height * depth) as u64;
    let output_buffer_size = total_points * std::mem::size_of::<f32>() as u64;
    
    let output_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Output Invariants Buffer"),
        size: output_buffer_size,
        // STORAGE: a shader írja, COPY_SRC: átmásolhatjuk egy staging bufferbe, hogy a CPU kiolvassa
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });


    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("Invariants Bind Group Layout"),
        entries: &[
            // Binding 0: Dimenziók (Uniform)
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            // Binding 1: Bemeneti metrika rács (Storage, Read-only)
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: true },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            // Binding 2: Kimeneti invariánsok (Storage, Read-write)
            wgpu::BindGroupLayoutEntry {
                binding: 2,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: false },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
        ],
    });


    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("Invariants Bind Group"),
        layout: &bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: dims_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: input_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 2,
                resource: output_buffer.as_entire_binding(),
            },
        ],
    });

    println!("Minden buffer sikeresen inicializálva a GPU-n!");
    println!("Bemeneti buffer mérete: {} bájt", grid.data.len() * std::mem::size_of::<MetricPoint>());
    println!("Kimeneti buffer mérete: {} bájt", output_buffer_size);
    
    // 6. A WGSL SHADER MODUL BETÖLTÉSE
    // Beolvassuk a korábban megírt shader fájlt (feltételezve, hogy a src/gorbület.wgsl helyen van)
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("Spacetime Curvature Shader"),
        source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(include_str!("points.wgsl"))),
    });

    // 7. COMPUTE PIPELINE LAYOUT LÉTREHOZÁSA
    // Összekötjük a korábban létrehozott bind_group_layout-ot a pipeline-nal
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("Compute Pipeline Layout"),
        bind_group_layouts: &[Some(&bind_group_layout)],
        immediate_size: 0,
    });

    // 8. A TÉNYLEGES COMPUTE PIPELINE LÉTREHOZÁSA
    let compute_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("Spacetime Compute Pipeline"),
        layout: Some(&pipeline_layout),
        module: &shader,
        entry_point: Some("main"), // A WGSL-ben szereplő fn main() neve
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });

    // 9. PARANCSOK ÖSSZEÁLLÍTÁSA A GPU SZÁMÁRA (Command Encoder)
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("Spacetime Command Encoder"),
    });

    {
        // Elindítjuk a Compute Pass-t a megfelelő deszkriptorral
        let mut compute_pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("Spacetime Compute Pass"),
            timestamp_writes: None,
        });

        // Beállítjuk a pipeline-t és a hozzá tartozó adat-puffereket (bind group)
        compute_pass.set_pipeline(&compute_pipeline);
        compute_pass.set_bind_group(0, &bind_group, &[]);

        // Kiszámoljuk, hány Workgroup-ot kell indítanunk. 
        // Mivel a shaderben @workgroup_size(4, 4, 4) van, a rács méretét osztani kell 4-gyel.
        // Példa: 64 / 4 = 16 workgroup irányonként.
        let workgroups_x = (width + 3) / 4;
        let workgroups_y = (height + 3) / 4;
        let workgroups_z = (depth + 3) / 4;

        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);
    } // A compute_pass itt lezárul (Drop), így az encoder újra szabadon használható

    // 10. A PARANCSOK ELKÜLDÉSE A GPU-NAK
    // A queue.submit() végrehajtja a számítást a háttérben
    queue.submit(std::iter::once(encoder.finish()));

    println!("A számítási feladat sikeresen elküldve a GPU-nak!");
    
    // 11. A STAGING BUFFER LÉTREHOZÁSA A CPU-N VALÓ OLVASÁSHOZ
    let staging_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Staging Buffer for Reading Output"),
        size: output_buffer_size,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });

    // 12. ÚJ PARANCSKÜLDÉS A MÁSOLÁSHOZ
    let mut copy_encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("Copy Command Encoder"),
    });

    // Átmásoljuk a teljes kimeneti adatot a staging pufferbe
    copy_encoder.copy_buffer_to_buffer(&output_buffer, 0, &staging_buffer, 0, output_buffer_size);
    queue.submit(std::iter::once(copy_encoder.finish()));

    // 13. A PUFFER FELTÉRKÉPEZÉSE (ASZINKRON MAP A V30 API-VAL)
    let buffer_slice = staging_buffer.slice(..);
    
    // Létrehozunk egy szálbiztos csatornát (channel) az aszinkron visszajelzéshez
    let (tx, rx) = std::sync::mpsc::channel();
    
    // wgpu v30 map_async: pontosan 2 argumentum (MapMode, Callback)
    buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).unwrap();
    });

    // Megkérjük a global instance-t, hogy pörgesse át a háttérfolyamatokat és várjon (true)
    instance.poll_all(true);

    // Megvárjuk, amíg a callback lefut a csatornán keresztül
    if let Ok(Ok(())) = rx.recv() {
        // KICSOMAGOLÁS: Mivel a get_mapped_range() egy Result-ot ad vissza, kicsomagoljuk az Ok-val
        if let Ok(data_view) = buffer_slice.get_mapped_range() {
            
            // A bytemuck segítségével a nyers bájtokat f32 értékek tömbjeként értelmezzük
            let result_invariants: &[f32] = bytemuck::cast_slice(&data_view);

            println!("Sikeres adatvisszaolvasás a GPU-ról!");
            println!("Összesen beolvasott pont: {}", result_invariants.len());

            // 14. ELLENŐRZŐ KIÍRÁS
            println!("Első 5 rácspont értéke a kimeneten:");
            for i in 0..5 {
                println!("  Pont [{}]: {}", i, result_invariants[i]);
            }

            // Fontos: a leképezést meg kell szüntetni (drop), mielőtt a buffer megsemmisülne
            drop(data_view);
            staging_buffer.unmap();
        } else {
            eprintln!("Hiba történt a buffer tartományának (get_mapped_range) elérésekor!");
        }
    } else {
        eprintln!("Hiba történt a GPU buffer aszinkron map-elése közben!");
    }
    
}

fn main() {
    // Mivel a wgpu async, elindítjuk a futtató környezetet
    pollster::block_on(run());
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct MetricPoint {
    // Diagonális elemek
    pub g00: f32, pub g11: f32, pub g22: f32, pub g33: f32,
    // Kereszt-tagok (nem-diagonális eset)
    pub g01: f32, pub g02: f32, pub g03: f32,
    pub g12: f32, pub g13: f32, pub g23: f32,
}

// A teljes 3D rácsot tartalmazó struktúra
pub struct SpacetimeGrid {
    pub width: u32,
    pub height: u32,
    pub depth: u32,
    pub data: Vec<MetricPoint>,
}

impl SpacetimeGrid {
    // Kényelmi függvény a rács létrehozásához üres adatokkal
    pub fn new(width: u32, height: u32, depth: u32, dx_space: f32) -> Self {
        let size = (width * height * depth) as usize;
        let data = vec![MetricPoint::zeroed(); size];
        let mut grid =  SpacetimeGrid{ width, height, depth, data };
        // Tesztadatok feltöltése: Schwarzschild-metrika kezdeti feltétel
        let m = 1.0; // A fekete lyuk tömege
        let r0 = 0.4;         // Regulázási/tágulási paraméter (a módosított egyenletedből)
        for z in 0..depth {
            for y in 0..height {
                for x in 0..width {
                    let idx = (x + y * width + z * width * height) as usize;
                    
                    // Átváltunk a rácsindexekből fizikai koordinátákba (középponthoz képest)
                    let rx = (x as f32 - width as f32 / 2.0) * dx_space;
                    let ry = (y as f32 - height as f32 / 2.0) * dx_space;
                    let rz = (z as f32 - depth as f32 / 2.0) * dx_space;
                    let r2 = rx*rx + ry*ry + rz*rz;
                    let r = r2.sqrt();
                    // SZINGULARITÁSMENTES SCHWARZSCHILD-FAKTOR (Példa a tágulásra)
                    let f = 1.0 - (2.0 * m * r2) / (r2 * r + r0 * r0 * r0);
                    grid.data[idx].g00 = -f;       // Idő komponens
                    grid.data[idx].g11 = 1.0 / f;
                    grid.data[idx].g22 = 1.0 / f;
                    grid.data[idx].g33 = 1.0 / f;
                    // Kereszt-tagok kezdetben zérók
                    grid.data[idx].g01 = 0.0; grid.data[idx].g02 = 0.0; grid.data[idx].g03 = 0.0;
                    grid.data[idx].g12 = 0.0; grid.data[idx].g13 = 0.0; grid.data[idx].g23 = 0.0;
                }
            }
        }
        grid
    }
}

