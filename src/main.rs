use bytemuck::*;
//use eframe::egui;
use eframe::wgpu;
use std::sync::Arc;
//use wgpu::util::DeviceExt;
//use egui_wgpu::WgpuSetup;
//use eframe::Renderer;
//use egui_wgpu::Renderer;

// Ez kényszeríti a Rustot, hogy figyelje a shader fájlt
const WGSL_CODE: &str = include_str!("gridpoints.wgsl");

fn main() -> eframe::Result<()> {
    //let renderer = eframe::Renderer::Wgpu;
    //let renderer = eframe::Renderer::Glow;
    //let native_options = eframe::NativeOptions {
    //    renderer: renderer,
    //    ..Default::default()
    //};
    let wgpu_config = egui_wgpu::WgpuConfiguration {
        wgpu_setup: egui_wgpu::WgpuSetup::CreateNew(egui_wgpu::WgpuSetupCreateNew {
            // Átmásoljuk az adapter gyári limitjeit, így a 16-os limit érvényesül
            device_descriptor: Arc::new(|adapter| {
                wgpu::DeviceDescriptor {
                    label: Some("egui wgpu device"),
                    required_features: wgpu::Features::default(),
                    required_limits: adapter.limits(), // <--- Így az összes hardveres limit aktív lesz!
                    ..Default::default()
                }
            }),
            ..Default::default()
        }),
        ..Default::default()
    };
   
    
    let native_options = eframe::NativeOptions {
        wgpu_options: wgpu_config,
        ..Default::default()
    };
    
    let app = SpacetimeApp::new();
    eframe::run_native(
        "Spacetime Curvature Explorer",
        native_options,
        Box::new(|_cc|
            Ok(Box::new(app))),
    )
}


struct GpuInterface {
    pub io_buffer_size: u64,
    pub compute_pipeline_1: wgpu::ComputePipeline,
    pub compute_pipeline_2: wgpu::ComputePipeline,
    pub compute_pipeline_3: wgpu::ComputePipeline,
    pub compute_pipeline_4: wgpu::ComputePipeline,
    pub bind_group_a_to_b: wgpu::BindGroup,
    pub bind_group_b_to_a: wgpu::BindGroup,
    pub dims_buffer: wgpu::Buffer,
    pub buffer_a: wgpu::Buffer,
    pub buffer_b: wgpu::Buffer,
    pub staging_buffer: wgpu::Buffer,
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct GridDimensions {
    width: u32,
    height: u32,
    depth: u32,
    dx: f32,
    dt: f32,
    step_index: u32,
    init_flag: u32,
    pad2: u32,
}


impl GpuInterface {
    fn init(render_state: &egui_wgpu::RenderState, app: &SpacetimeApp) -> Option<Self> {
        
        let limits = render_state.adapter.limits();
        if limits.max_storage_buffers_per_shader_stage  < 4 {
            eprintln!("Hiba: A GPU nem támogatja a Storage Texture-öket (VirtualBox/régi driver).");
            return None;
        }

        let device = render_state.device.clone();
        let queue = render_state.queue.clone();
        println!("limits.max_storage_buffers_per_shader_stage : {:?}",limits.max_storage_buffers_per_shader_stage );

        let dims_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Grid Dimensions Uniform Buffer"),
            size: std::mem::size_of::<GridDimensions>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        queue.write_buffer(&dims_buffer, 0, bytemuck::bytes_of(&app.dims_data));
        println!("{}",1);

        // Shader és Pipeline felépítése
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Spacetime Curvature Shader"),
            source: wgpu::ShaderSource::Wgsl(WGSL_CODE.into()),
        });
        println!("{}",2);



        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Spacetime Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None, },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
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
        println!("{}",3);

        let grid_size = (app.grid.width * app.grid.height * app.grid.depth) as u64;
        let bytes_per_point = 44*4; //std::mem::size_of::<MetricPoint>() as u64; // 44 darab f32 pontonként
        let io_buffer_size = grid_size * bytes_per_point;

        let buffer_a = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spacetime Storage Buffer A"),
            size: io_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        println!("{}",4);

        let buffer_b = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spacetime Storage Buffer B"),
            size: io_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        println!("{}",5);

        let staging_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Staging Buffer"),
            size: io_buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        println!("{}",5);

        queue.write_buffer(&buffer_a, 0, bytemuck::cast_slice(&app.grid.data));
        queue.write_buffer(&buffer_b, 0, bytemuck::cast_slice(&app.grid.data));

        // BIND GROUP 1: buff_A a múlt (be), buff_B a jövő (ki) -> Páros körök
        let bind_group_a_to_b = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Bind Group: A to B"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: dims_buffer.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: buffer_a.as_entire_binding() }, // Múlt (read_write)
                wgpu::BindGroupEntry { binding: 2, resource: buffer_b.as_entire_binding() }, // Jövő (read_write)
            ],
        });

        // BIND GROUP 2: Szerepek felcserélve! buff_B a múlt, buff_A a jövő -> Páratlan körök
        let bind_group_b_to_a = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Bind Group: B to A"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: dims_buffer.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: buffer_b.as_entire_binding() }, // Múlt (read_write)
                wgpu::BindGroupEntry { binding: 2, resource: buffer_a.as_entire_binding() }, // Jövő (read_write)
            ],
        });
        println!("{}", 6);
        
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Compute Pipeline Layout"),
            bind_group_layouts: &[&bind_group_layout],
            //bind_group_layouts: &[Some(&bind_group_layout)], // for v0.35
            //immediate_size: 0, // v0.35 kompatibilis mező // for v0.35
            push_constant_ranges: &[], // for v0.33
        });
        println!("{}",7);

        let compute_pipeline_1 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase1"),
            compilation_options: Default::default(),
            cache: None,
        });
        println!("{}",8);

        let compute_pipeline_2 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase2"),
            compilation_options: Default::default(),
            cache: None,
        });
        println!("{}",9);

        let compute_pipeline_3 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase3"),
            compilation_options: Default::default(),
            cache: None,
        });
        println!("{}",10);

        let compute_pipeline_4 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase4"),
            compilation_options: Default::default(),
            cache: None,
        });

        println!("A teljes Riemann-csővezeték sikeresen felépült a konstruktorban!");

        Some(Self{
            io_buffer_size: io_buffer_size,
            compute_pipeline_1: compute_pipeline_1,
            compute_pipeline_2: compute_pipeline_2,
            compute_pipeline_3: compute_pipeline_3,
            compute_pipeline_4: compute_pipeline_4,
            bind_group_a_to_b: bind_group_a_to_b,
            bind_group_b_to_a: bind_group_b_to_a,
            dims_buffer: dims_buffer,
            buffer_a: buffer_a,
            buffer_b: buffer_b,
            staging_buffer: staging_buffer,
            device: device.into(),
            queue: queue.into(),
        })
    }
}


struct SpacetimeApp {
    pub grid: SpacetimeGrid,
    pub dims_data: GridDimensions,
    pub gpu_interface: Option<GpuInterface>,

    pub view_texture: Option<egui::TextureHandle>,
    pub selected_z_slice: i32,
    pub selected_scalar: i32, // 0: R, 1: K, 2: C2, 3: Feszültség 
    pub min_val: f32,
    pub max_val: f32,
}

impl SpacetimeApp {
    fn new() -> Self {
        let width  = 64;
        let height = 64;
        let depth  = 64;
        let dx: f32 = 0.1;
        let dt: f32 = dx * 0.5;
        let grid = SpacetimeGrid::new(width, height, depth, dx);
        let dims_data = GridDimensions { width: width, height: height, depth: depth, dx: dx, dt: dt, step_index: 0, init_flag: 1, pad2: 0,};
        Self {
            grid,
            dims_data,
            gpu_interface: None,
            view_texture: None,
            selected_z_slice: 32,
            selected_scalar: 3, // 0: R, 1: K, 2: C2, 3: Feszültség    
            min_val: 0.0,
            max_val: 0.0,
        }
    }
    
    fn sclice_statistic( &mut self, ctx: &egui::Context, selected_scalar: i32, result_data: &[f32]) {
        let width = self.grid.width as usize;
        let height = self.grid.height as usize;
        let depth = self.grid.depth as usize;
        let mut current_min = f32::MAX;
        let mut current_max = f32::MIN;
        let scalar_offset = (40 + selected_scalar) as usize;
        for a in 0..(depth*width*height) {
            let val = result_data[a*44 + scalar_offset];
            if val.is_finite() {
                if val < current_min { current_min = val; }
                if val > current_max { current_max = val; }
            }
        }
        self.min_val = current_min;
        self.max_val = current_max;
        
        let mut color_pixels = vec![egui::Color32::BLACK; width * height];
        let z_slice = self.selected_z_slice as usize;
         //Skálázási faktor a normalizáláshoz (0.0 .. 1.0 közé hozzuk az értékeket)
        let range = current_max - current_min;
        let scale = if range.abs() > 1e-6 { 1.0/range } else { 1.0 };
        if scale == 1.0 { current_min -= 0.5; }

        for y in 0..height {
            for x in 0..width {
                let idx_1d = (x + (y * width) + (z_slice * width * height)) * 44;
                let val = result_data[idx_1d + scalar_offset];
                let intensity = ((val - current_min) * scale).clamp(0.0, 1.0);
                // Egy klasszikus asztrofizikai "Hot/Fire" vagy tiszta kék-piros hőtérkép színskála:
                let r = (intensity * 255.0) as u8;
                let g = ((intensity * intensity) * 255.0) as u8; // nem-lineáris zöld a lágy átmenethez
                let b = (128.0 * (1.0 - intensity)) as u8;       // halványuló kék a hideg pontoknak
                color_pixels[x + (y * width)] = egui::Color32::from_rgb(r, g, b);
            }
        }
        let color_image = egui::ColorImage::new([width, height], color_pixels);
        self.view_texture = Some(ctx.load_texture(
            "Spacetime Heatmap Slice",
            color_image,
            egui::TextureOptions::NEAREST, // Tiszta, pixeles rácsmegjelenítés elmosás nélkül
        ));
    }
}

impl eframe::App for SpacetimeApp {
    fn update(&mut self, ctx: &egui::Context, frame: &mut eframe::Frame) {
        
        egui::CentralPanel::default().frame(egui::Frame::NONE.inner_margin(0.0)).show(ctx, |ui| {

            ui.heading("Módosított Téregyenlet Szimulátor");
            ui.separator();
            
            let buffer_size_f32 = self.grid.width * self.grid.height * self.grid.depth * 44;
            
            let mut local_data_copy = vec![0.0f32; buffer_size_f32 as usize];
            let mut scalar = -2;

            if self.gpu_interface.is_none() {
                if let Some(render_state) = frame.wgpu_render_state() {
                    println!("Most már van GPU állapota, indulhat a gpu_init...");
                    if let Some(interface) = GpuInterface::init(render_state, &self) {
                        local_data_copy = bytemuck::cast_slice(&self.grid.data).to_vec();
                        scalar = 3;
                        //self.sclice_statistic(ctx,-1, local_data_copy);
                        self.gpu_interface = Some(interface);
                        println!("GPU INTERFÉSZ KÉSZ!");
                    }
                }
            }
            if self.gpu_interface.is_none() {
                ctx.request_repaint();
                return;
            }
            ui.horizontal(|ui| {
                ui.label(format!("Rács mérete: {}x{}x{}", self.grid.width, self.grid.height, self.grid.depth));
                ui.separator();
                ui.label(format!("Aktuális időlépés (t): {}", self.dims_data.step_index));
            });

            // 3. A GOMBNYOMÁSRA KÖZVETLENÜL INDÍTJUK A SZÁMÍTÁST (Nincs async deadlock)
            if ui.button("Görbületi Feszültség Számítása").clicked() {
                println!("Számítás indítása a GPU-n...");
                
                if let Some(interface) = &self.gpu_interface {

                    let active_bind_group = if self.dims_data.step_index % 2 == 0 {
                        &interface.bind_group_a_to_b
                    } else {
                        &interface.bind_group_b_to_a
                    };
                    interface.queue.write_buffer(&interface.dims_buffer, 0, bytemuck::bytes_of(&self.dims_data));

                    let mut encoder = interface.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                        label: Some("Spacetime Command Encoder"),
                    });

                    // @compute @workgroup_size(4, 4, 4)
                    let workgroups_x = (self.grid.width + 3) / 4;
                    let workgroups_y = (self.grid.height + 3) / 4;
                    let workgroups_z = (self.grid.depth + 3) / 4;
                    
                    {
                        let mut compute_pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                            label: Some("Spacetime Compute Pass"),
                            timestamp_writes: None,
                        });
                        
                        compute_pass.set_bind_group(0, active_bind_group, &[]);

                        compute_pass.set_pipeline(&interface.compute_pipeline_1);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_2);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_3);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_4);                        
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);
                    }
                    
                    let future_buffer = if self.dims_data.step_index % 2 == 0 {
                        &interface.buffer_b // Ha a step_index páros volt, a B pufferbe írt a shader
                    } else {
                        &interface.buffer_a // Ha páratlan, az A pufferbe írt
                    };

                    encoder.copy_buffer_to_buffer( future_buffer, 0, &interface.staging_buffer, 0, interface.io_buffer_size );

                    interface.queue.submit(std::iter::once(encoder.finish()));

                    let buffer_slice = interface.staging_buffer.slice(..);
 
                    // Létrehozunk egy szálbiztos Atomic bool-t az aszinkron állapot követésére
                    use std::sync::atomic::{AtomicBool, Ordering};
                    use std::sync::Arc;
                    let is_mapped = Arc::new(AtomicBool::new(false));
                    let is_mapped_clone = is_mapped.clone();

                    // Regisztráljuk a callback-et, ami CSAK átbillenti a flag-et, ha kész a GPU
                    buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
                        if result.is_ok() {
                            is_mapped_clone.store(true, Ordering::SeqCst);
                        }
                    });

                    while !is_mapped.load(Ordering::SeqCst) {
                        let _ = interface.device.poll(wgpu::PollType::Poll);
                        std::thread::yield_now(); 
                    }
                    println!("Az időlépés sikeresen lefutott a videókártyán!");
                    {
                        let data_view = buffer_slice.get_mapped_range();
                        let result_data: &[f32] = bytemuck::cast_slice(&data_view);
                        local_data_copy.copy_from_slice(result_data);
                        scalar = self.selected_scalar;

                        // Kiszámítjuk a rács abszolút középpontjának (32, 32, 32) 1D indexét a 44 f32-es hasábban:
                        let x = 31; // 0..63
                        let y = 30; // 0..63
                        let z = 33; // 0..63
                        let center_1d_index = ((x + (y * self.grid.width) + (z * self.grid.width * self.grid.height)) * 44) as usize;
                        let r_scalar  = result_data[center_1d_index + 40]; // R
                        let k_scalar  = result_data[center_1d_index + 41]; // K
                        let c2_scalar = result_data[center_1d_index + 42]; // C²
                        let brackets  = result_data[center_1d_index + 43]; // Feszültség

                        println!("--- Szingularitásmentes Kerr-Toroid Középpont ({},{},{}) ---", x, y, z);
                        println!("  Ricci görbület (R):     {}", r_scalar);
                        println!("  Kretschmann skalár (K):  {}", k_scalar);
                        println!("  Weyl invariáns (C²):     {}", c2_scalar);
                        println!("  Effektív G Feszültség:  {}", brackets);

                        drop(data_view);
                    }
                    interface.staging_buffer.unmap();
                    self.dims_data.step_index += 1;
                    self.dims_data.init_flag = 0; // Az első időlépés után az inicializáció örökre kikapcsol

                }
            }
            if scalar != -2 {
                self.sclice_statistic(ctx, scalar, &local_data_copy);
            }
            ui.separator();
            ui.vertical(|ui| {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        if let Some(texture) = self.view_texture.as_ref() {
                            ui.label("Élő 2D Görbületi Metszet (X-Y sík):");
                            ui.image((texture.id(), egui::vec2(480.0, 480.0)));
                        } else {
                            ui.colored_label(
                                egui::Color32::LIGHT_GRAY,
                                "Nincs kiszámított adat.\nKattints az 'Időlépés Futtatása' gombra a hőtérkép legenerálásához!",
                            );
                        }
                    });
                    ui.vertical(|ui| {
                        ui.heading("Szimulációs Statisztikák");
                        ui.label(format!("Aktuális időlépés (t): {}", self.dims_data.step_index));
                        ui.label(format!("Keresett skalár minimuma: {}", self.min_val));
                        ui.label(format!("Keresett skalár maximuma: {}", self.max_val));
                        
                        ui.separator();
                        ui.label("Megjelenítendő invariáns:");
                        ui.radio_value(&mut self.selected_scalar, 0, "Ricci Skalár (R)");
                        ui.radio_value(&mut self.selected_scalar, 1, "Kretschmann (K)");
                        ui.radio_value(&mut self.selected_scalar, 2, "Weyl-négyzet (C²)");
                        ui.radio_value(&mut self.selected_scalar, 3, "Gravitációs Feszültség");

                        ui.add(egui::Slider::new(&mut self.selected_z_slice, 0..=63).text("Z-tengely szelet"));
                    });
                });
            });
            
        });
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
#[warn(unused)]
pub struct MetricPoint {
    pub g: [f32; 10],
    pub i: [f32; 10],
    pub k: [f32; 10],
    pub c: [f32; 10],
    pub s: [f32; 4],
}

// A teljes 3D rácsot tartalmazó struktúra
pub struct SpacetimeGrid {
    pub width: u32,
    pub height: u32,
    pub depth: u32,
    pub dx: f32,
    pub data: Vec<MetricPoint>,
}

impl SpacetimeGrid {
    // Kényelmi függvény a rács létrehozásához üres adatokkal
    pub fn new(width: u32, height: u32, depth: u32, dx: f32) -> Self {
        let size = (width * height * depth) as usize;
        let data = vec![MetricPoint::zeroed(); size]; // nullára inicializálunk!!!
        let mut grid =  SpacetimeGrid{ width, height, depth, dx, data };
        grid.one_static_schwarzschild(1.0,0.4); // Tesztadatok feltöltése
        grid
    }
    pub fn one_static_schwarzschild(&mut self, m: f32, r0: f32) {
        let cx = self.width as f32 / 2.0;
        let cy = self.height as f32 / 2.0;
        let cz = self.depth as f32 / 2.0;

        for z in 0..self.depth {
            for y in 0..self.height {
                for x in 0..self.width {
                    let idx = (x + y * self.width + z * self.width * self.height) as usize;

                    // Tűpontos fizikai koordináták a rács abszolút közepéhez képest
                    let rx = (x as f32 - cx) * self.dx;
                    let ry = (y as f32 - cy) * self.dx;
                    let rz = (z as f32 - cz) * self.dx;
                    
                    let r2 = rx*rx + ry*ry + rz*rz;
                    let r = r2.sqrt();

                    // 1. SZABÁLYOSÍTOTT SCHWARZSCHILD IDŐ-FAKTOR (A te tágulási képleted)
                    let f = 1.0 - (2.0 * m * r2) / (r2 * r + r0 * r0 * r0);
                    
                    // 2. IZOTRÓP TÉRBELI FAKTOR (Nincs nullával való osztás!)
                    // Sima, folytonos átmenetet biztosít a végtelen távolság (1.0) és a mag között
                    let regularized_r = (r2 + r0*r0).sqrt();
                    let psi_factor = 1.0 + (2.0 * m) / regularized_r;

                    // 3. TENZOR ELEMEK BEÍRÁSA (idx = 0..9)
                    self.data[idx].g[0] = -f;          // g00 (Idő)
                    self.data[idx].g[1] = psi_factor;  // g11 (X térbeli)
                    self.data[idx].g[2] = psi_factor;  // g22 (Y térbeli)
                    self.data[idx].g[3] = psi_factor;  // g33 (Z térbeli)

                    // Kirajzoláshoz tesztként elmentjük a G feszültség helyére (s[3]) az f faktort
                    self.data[idx].s[3] = f; 
                }
            }
        }
        println!("Az Izotróp nemszinguláris Schwarzschild mező sikeresen generálva!");
    }
}

