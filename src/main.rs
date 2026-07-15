use bytemuck::*;
//use wgpu::util::DeviceExt; // Ez a trait kell a könyvjelző-alapú buffer létrehozáshoz
use eframe::egui;

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dx: f32, // Tűpontosan 4 bájt, az igazítás sértetlen marad
}


fn main() -> eframe::Result<()> {
    /*let has_wgpu = pollster::block_on(check_wgpu_support());
    
    let renderer = if has_wgpu {
        println!("WGPU támogatott, Shader mód bekapcsolva.");
        eframe::Renderer::Wgpu
    } else {
        println!("WGPU nem elérhető. Váltás GLOW (OpenGL) módra - CPU fallback.");
        eframe::Renderer::Glow
    };*/

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_resizable(false)
            .with_inner_size([800.0, 600.0]),
        //renderer: renderer,
        ..Default::default()
    };

    //let options = eframe::NativeOptions::default();
    eframe::run_native(
        "Spacetime Curvature Explorer",
        options,
        Box::new(|cc|
            Ok(Box::new(SpacetimeApp::new(cc)))),
    )
    // Mivel a wgpu async, elindítjuk a futtató környezetet
    //pollster::block_on(run());
}


struct SpacetimeApp {
    pub grid: SpacetimeGrid,
    pub compute_pipeline: wgpu::ComputePipeline,
    pub bind_group: wgpu::BindGroup,
    pub input_buffer: wgpu::Buffer,
    pub output_buffer: wgpu::Buffer,
    pub staging_buffer: wgpu::Buffer,
    pub output_buffer_size: u64,
}

impl SpacetimeApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let width = 64;
        let height = 64;
        let depth = 64;
        let dx: f32 = 0.1;
        let grid = SpacetimeGrid::new(width, height, depth, dx);
        
        // 2. ELKÉRJÜK A GUI ÁLTAL INICIALIZÁLT HARDVERES RENDERSZINTET
        let render_state = cc
            .wgpu_render_state
            .as_ref()
            .expect("A WGPU nem inicializálódott megfelelően az eframe-ben!");

        let device = &render_state.device;

        // --- IDE KÖLTÖZIK AZ ÖSSZES INITIALIZÁCIÓS KÓD (Egyetlen egyszer fut le) ---

        let dims_data = GridDimensions { width, height, depth, dx };
        let dims_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Grid Dimensions Uniform Buffer"),
            contents: bytemuck::bytes_of(&dims_data),
            usage: wgpu::BufferUsages::UNIFORM,
        });

        // Bemeneti metrika storage buffer
        let input_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Input Spacetime Grid Buffer"),
            contents: bytemuck::cast_slice(&grid.data),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        });

        // Kimeneti invariánsok buffer
        let total_points = (width * height * depth) as u64;
        let output_buffer_size = total_points * std::mem::size_of::<f32>() as u64;
        let output_buffer = device.create_buffer(wgpu::BufferDescriptor {
            label: Some("Output Invariants Buffer"),
            size: output_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        // Staging buffer a CPU olvasáshoz
        let staging_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Staging Buffer"),
            size: output_buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Bind Group Layout felépítése (v0.35 szabvány szerint)
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Invariants Bind Group Layout"),
            entries: &[
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
                wgpu::BindGroupEntry { binding: 0, resource: dims_buffer.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: input_buffer.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 2, resource: output_buffer.as_entire_binding() },
            ],
        });

        // Shader és Pipeline felépítése
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Spacetime Curvature Shader"),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(include_str!("points.wgsl"))),
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Compute Pipeline Layout"),
            bind_group_layouts: &[&bind_group_layout],
            immediate_size: 0, // v0.35 kompatibilis mező
        });

        let compute_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("main"),
            compilation_options: wgpu::PipelineCompilationOptions::default(),
            cache: None,
        });

        println!("A teljes Riemann-csővezeték sikeresen felépült a konstruktorban!");

        Self {
            grid,
            compute_pipeline,
            bind_group,
            input_buffer,
            output_buffer,
            staging_buffer,
            output_buffer_size,
        }
    }
}

impl eframe::App for SpacetimeApp {
    fn logic(&mut self, _ctx: &egui::Context, _: &mut eframe::Frame) {
    }
    fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame) {
        ui.heading("Módosított Téregyenlet Szimulátor");
        ui.separator();
        ui.label(format!("Rács mérete: {}x{}x{}", self.grid.width, self.grid.height, self.grid.depth));

        // 3. A GOMBNYOMÁSRA KÖZVETLENÜL INDÍTJUK A SZÁMÍTÁST (Nincs async deadlock)
        if ui.button("Görbületi Feszültség Számítása").clicked() {
            println!("Számítás indítása a GPU-n...");

            if let Some(render_state) = frame.wgpu_render_state() {
                let device = &render_state.device;
                let queue = &render_state.queue;

                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("Spacetime Command Encoder"),
                });

                {
                    let mut compute_pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                        label: Some("Spacetime Compute Pass"),
                        timestamp_writes: None,
                    });
                    compute_pass.set_pipeline(&self.compute_pipeline);
                    compute_pass.set_bind_group(0, &self.bind_group, &[]);

                    let workgroups_x = (self.grid.width + 3) / 4;
                    let workgroups_y = (self.grid.height + 3) / 4;
                    let workgroups_z = (self.grid.depth + 3) / 4;
                    compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);
                }

                // Másolás a staging bufferbe
                encoder.copy_buffer_to_buffer(&self.output_buffer, 0, &self.staging_buffer, 0, self.output_buffer_size);
                queue.submit(std::iter::once(encoder.finish()));

                // Visszaolvasás a GPU-ról a már jól bevált mpsc csatornával
                let buffer_slice = self.staging_buffer.slice(..);
                let (tx, rx) = std::sync::mpsc::channel();
                
                buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
                    tx.send(result).unwrap();
                });

                // A WGPU belső állapotát frissítjük a parancsok végrehajtásához
                // v0.35 asztali környezetben az instance helyett közvetlenül a device.poll() is pörgethető így:
                device.poll(wgpu::MaintainProcess::wait());

                if let Ok(Ok(())) = rx.recv() {
                    if let Ok(data_view) = buffer_slice.get_mapped_range() {
                        let result_invariants: &[f32] = bytemuck::cast_slice(&data_view);

                        println!("Sikeres számítás! Első 5 rácspont görbületi feszültsége:");
                        for i in 0..5 {
                            println!("  Pont [{}]: {}", i, result_invariants[i]);
                        }

                        drop(data_view);
                        self.staging_buffer.unmap();
                    }
                }
            }
        }
    }
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

