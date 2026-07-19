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
    pub compute_pipeline_5: wgpu::ComputePipeline,
    pub bind_group: wgpu::BindGroup,
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

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Bind Group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: dims_buffer.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: buffer_a.as_entire_binding() }, // Múlt (read_write)
                wgpu::BindGroupEntry { binding: 2, resource: buffer_b.as_entire_binding() }, // Jövő (read_write)
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

        let compute_pipeline_5 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase5"),
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
            compute_pipeline_5: compute_pipeline_5,
            bind_group: bind_group,
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
    slice_only_stats: bool,
    pub selected_scalar: i32, // 0: R, 1: K, 2: C2, 3: Feszültség 
    pub min_val: f32,
    pub max_val: f32,
}

impl SpacetimeApp {
    fn new() -> Self {
        let width  = 70;
        let height = 70;
        let depth  = 70;
        let dx: f32 = 0.01;
        let dt: f32 = dx * 0.00001;
        let grid = SpacetimeGrid::new(width, height, depth, dx);
        let dims_data = GridDimensions { width: width, height: height, depth: depth, dx: dx, dt: dt, step_index: 0, init_flag: 1, pad2: 0,};
        Self {
            grid,
            dims_data,
            gpu_interface: None,
            view_texture: None,
            selected_z_slice: 70/2, // depth/2
            slice_only_stats: true,
            selected_scalar: 3, // 0: R, 1: K, 2: C2, 3: Feszültség    
            min_val: 0.0,
            max_val: 0.0,
        }
    }
    
    fn sclice_statistic( &mut self, ctx: &egui::Context) {
        let width = self.grid.width as usize;
        let height = self.grid.height as usize;
        let depth = self.grid.depth as usize;
        let mut current_min = f32::MAX;
        let mut current_max = f32::MIN;
        let scalar_offset = (40 + self.selected_scalar) as usize;
        let z_slice = self.selected_z_slice as usize;
        for z in 0..depth {
            // Ha a Checkbox be van jelölve, a külső ciklus átugorja a többi Z-réteget
            if self.slice_only_stats && z != z_slice { continue; }            
            for y in 0..height {
                for x in 0..width {
                    let idx_1d = x + (y * width) + (z * width * height);
                    let val = self.grid.data[idx_1d].data[scalar_offset];
                    if val.is_finite() {
                        if val < current_min { current_min = val; }
                        if val > current_max { current_max = val; }
                    }
                }
            }
        }        
        self.min_val = current_min;
        self.max_val = current_max;

        // Segédfüggvény a SymLog transzformációhoz: lineáris [-1, 1] között, azon kívül logaritmikus
        let sym_log = |v: f32| -> f32 {
            if v.abs() <= 1.0 {
                v
            } else {
                v.signum() * (1.0 + v.abs().ln())
            }
        };

        // Kiszámítjuk a tömörített tartomány határait
        let log_min = sym_log(current_min);
        let log_max = sym_log(current_max);
        let log_range = log_max - log_min;
        let all_zero = log_range.abs() < 1e-6;
        
        let mut color_pixels = vec![egui::Color32::BLACK; width * height];
         //Skálázási faktor a normalizáláshoz (0.0 .. 1.0 közé hozzuk az értékeket)
        let range = current_max - current_min;
        let scale = if range.abs() > 1e-6 { 1.0/range } else { 1.0 };

        for y in 0..height {
            for x in 0..width {
                let idx_1d = x + (y * width) + (z_slice * width * height);
                let val = self.grid.data[idx_1d].data[scalar_offset];
                let mut r = 0;
                let mut g = 0;
                let mut b = 128;
                if all_zero {
                    let checker = (x / 8 + y / 8) % 2 == 0;
                    let gray = if checker { 45 } else { 25 };
                    r = gray; g = gray; b = gray;
                } else {
                    let log_val = sym_log(val);
                    let intensity = ((log_val - log_min) / log_range).clamp(0.0, 1.0);
                    r = (intensity * 255.0) as u8;
                    g = ((intensity * intensity) * 255.0) as u8;
                    b = ((1.0 - intensity) * 128.0) as u8;
                }
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
            
            let mut redraw = false;

            if self.gpu_interface.is_none() {
                if let Some(render_state) = frame.wgpu_render_state() {
                    println!("Most már van GPU állapota, indulhat a gpu_init...");
                    if let Some(interface) = GpuInterface::init(render_state, &self) {
                        redraw = true;
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
                        
                        interface.queue.write_buffer(&interface.dims_buffer, 0, bytemuck::bytes_of(&self.dims_data));
                        
                        compute_pass.set_bind_group(0, &interface.bind_group, &[]);

                        compute_pass.set_pipeline(&interface.compute_pipeline_1);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_2);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_3);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_4);                        
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_5);                        
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);
                    }

                    encoder.copy_buffer_to_buffer( &interface.buffer_a, 0, &interface.staging_buffer, 0, interface.io_buffer_size );

                    interface.queue.submit(Some(encoder.finish()));
                    //interface.queue.submit(std::iter::once(encoder.finish()));
                    
// version A
                    
                    let buffer_slice = interface.staging_buffer.slice(..);
                    let (sender, receiver) = std::sync::mpsc::channel();
                    buffer_slice.map_async(wgpu::MapMode::Read, move |v| sender.send(v).unwrap());
                    let _ = interface.device.poll(wgpu::PollType::wait_indefinitely());
                    let total_f32_elements = (self.grid.width * self.grid.height * self.grid.depth) as usize * 44;
                    let mut local_data_copy = vec![0.0f32; total_f32_elements];
                    if let Ok(Ok(())) = receiver.try_recv() {
                        let data_view = buffer_slice.get_mapped_range();
                        let result_data: &[f32] = bytemuck::cast_slice(&data_view);
                        local_data_copy.copy_from_slice(result_data);
                        drop(data_view);
                        interface.staging_buffer.unmap();
                    }
// version C
                    /*let device_clone = interface.device.clone();
                    let staging_buffer_clone = interface.staging_buffer.clone();                    
                    let total_f32_elements = (self.grid.width * self.grid.height * self.grid.depth) as usize * 44;
                    let (sender, receiver) = std::sync::mpsc::channel();
                    std::thread::spawn(move || {
                        let buffer_slice = staging_buffer_clone.slice(..);
                        let (map_sender, map_receiver) = std::sync::mpsc::channel();
                        buffer_slice.map_async(wgpu::MapMode::Read, move |res| { let _ = map_sender.send(res); });
                        let _ = device_clone.poll(wgpu::PollType::wait_indefinitely());
                        if let Ok(Ok(())) = map_receiver.recv() {
                            let data_view = buffer_slice.get_mapped_range();
                            let result_data: &[f32] = bytemuck::cast_slice(&data_view);
                            let mut local_copy = vec![0.0f32; total_f32_elements];
                            local_copy.copy_from_slice(result_data);
                            drop(data_view);
                            staging_buffer_clone.unmap();
                            let _ = sender.send(local_copy);
                        }
                    });
                    if let Ok(local_data_copy) = receiver.recv() {
                        println!("Az időlépés sikeresen lefutott, a háttérszál átadta a valós adatokat!");
                        let mut src_f32_idx = 0;
                        for p in &mut self.grid.data {
                            p.data.copy_from_slice(&local_data_copy[src_f32_idx..src_f32_idx + 44]);
                            src_f32_idx += 44;
                        }
                        self.dims_data.step_index += 1;
                        self.dims_data.init_flag = 0; // Az első időlépés után az inicializáció örökre kikapcsol
                        let ctx_clone = ui.ctx().clone();
                        self.sclice_statistic(&ctx_clone);
                        //redraw = true;
                    }*/
// version B
                    // Létrehozunk egy szálbiztos Atomic bool-t az aszinkron állapot követésére
                    /*
                    let buffer_slice = interface.staging_buffer.slice(..);
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

                    let total_f32_elements = (self.grid.width * self.grid.height * self.grid.depth) as usize * 44;
                    let mut local_data_copy = vec![0.0f32; total_f32_elements];
                    {
                        let data_view = buffer_slice.get_mapped_range();
                        let result_data: &[f32] = bytemuck::cast_slice(&data_view);
                        local_data_copy.copy_from_slice(result_data);
                        drop(data_view);
                    }*/
// end of version B                
                    //interface.staging_buffer.unmap();

                    let mut src_f32_idx = 0;
                    for p in &mut self.grid.data {
                        p.data.copy_from_slice(&local_data_copy[src_f32_idx..src_f32_idx + 44]);
                        src_f32_idx += 44;
                    }
                    redraw = true;

                    self.dims_data.step_index += 1;
                    self.dims_data.init_flag = 0; // Az első időlépés után az inicializáció örökre kikapcsol
                }

            }
            ui.separator();
            ui.vertical(|ui| {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        if let Some(texture) = self.view_texture.as_ref() {
                            let size = 480.0;
                            egui::Frame::canvas(ui.style())
                                .stroke(egui::Stroke::new(1.5, egui::Color32::LIGHT_GRAY))
                                .show(ui, |ui| {
                                    let image_response = ui.image((texture.id(), egui::vec2(size, size)));
                                    if let Some(hover_pos) = image_response.hover_pos() {
                                        let rect = image_response.rect;
                                        let local_x = hover_pos.x - rect.min.x;
                                        let local_y = hover_pos.y - rect.min.y;
                                        let width = self.grid.width as usize;
                                        let height = self.grid.height as usize;
                                        let depth = self.grid.depth as usize;
                                        let grid_x = ((local_x / size) * width as f32) as usize;
                                        let grid_y = ((local_y / size) * height as f32) as usize;
                                        let grid_z = self.selected_z_slice as usize;
                                        if grid_x < width && grid_y < height && grid_z < depth {
                                            let idx_1d = grid_x + (grid_y * width) + (grid_z * width * height);
                                            let r_val    = self.grid.data[idx_1d].data[40];
                                            let k_val    = self.grid.data[idx_1d].data[41];
                                            let c2_val   = self.grid.data[idx_1d].data[42];
                                            let br_val   = self.grid.data[idx_1d].data[43];
                                            #[allow(deprecated)]
                                            egui::show_tooltip_at(
                                                ctx,
                                                ui.layer_id(),
                                                egui::Id::new("grid_tooltip"),
                                                ctx.pointer_latest_pos().unwrap_or(egui::Pos2::ZERO) + egui::vec2(20.0, 20.0),
                                                |ui: &mut egui::Ui| {
                                                ui.heading(format!("Rácspont: ({}, {}, {})",
                                                    grid_x as i32-self.grid.width as i32/2,
                                                    grid_y as i32-self.grid.height as i32/2,
                                                    grid_z as i32-self.grid.depth as i32/2));
                                                ui.separator();
                                                ui.label(format!("Ricci Skalár (R): {:.6}", r_val));
                                                ui.label(format!("Kretschmann  (K): {:.6}", k_val));
                                                ui.label(format!("Weyl-négyzet (C²): {:.6}", c2_val));
                                                ui.label(format!("Grav. Feszültség: {:.6}", br_val));
                                            });
                                        }
                                    }
                                });
                        } else {
                            ui.colored_label(
                                egui::Color32::LIGHT_GRAY,
                                "Nincs kiszámított adat.\nKattints az 'Időlépés Futtatása' gombra a hőtérkép legenerálásához!",
                            );
                        }
                    });
                    ui.vertical(|ui| {
                        ui.heading("Szimulációs Statisztikák");
                        ui.label(format!("Időlépés (t): {}", self.dims_data.step_index));
                        ui.label(format!("Minimum: {}", self.min_val));
                        ui.label(format!("Maximum: {}", self.max_val));
                        ui.label(format!("dx: {}", self.dims_data.dx));
                        ui.label(format!("dt: {}", self.dims_data.dt));
                        
                        ui.separator();
                        ui.label("Megjelenítendő invariáns:");
                        if ui.radio_value(&mut self.selected_scalar, 0, "Ricci Skalár (R)").changed() { redraw = true; }
                        if ui.radio_value(&mut self.selected_scalar, 1, "Kretschmann (K)").changed() { redraw = true; }
                        if ui.radio_value(&mut self.selected_scalar, 2, "Weyl-négyzet (C²)").changed() { redraw = true; }
                        if ui.radio_value(&mut self.selected_scalar, 3, "Gravitációs Feszültség").changed() { redraw = true; }

                        if ui.add(egui::Slider::new(&mut self.selected_z_slice, 0..=(self.grid.depth as i32 - 1)).text("Z-tengely szelet")).changed() { redraw = true; }
                        if ui.checkbox(&mut self.slice_only_stats, "Csak az aktuális szelet min/max").changed() {
                            redraw = true;
                        }
                    });
                });
            });
            if redraw {
                self.sclice_statistic(ctx);
            }
        });
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
#[warn(unused)]
pub struct MetricPoint {
    pub data: [f32; 44],
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
                    self.data[idx].data[0] = -f;          // g00 (Idő)
                    self.data[idx].data[1] = psi_factor;  // g11 (X térbeli)
                    self.data[idx].data[2] = psi_factor;  // g22 (Y térbeli)
                    self.data[idx].data[3] = psi_factor;  // g33 (Z térbeli)

                    // Kirajzoláshoz tesztként elmentjük a G feszültség helyére (s[3]) az f faktort
                    self.data[idx].data[43] = f; 
                }
            }
        }
        println!("Az Izotróp nemszinguláris Schwarzschild mező sikeresen generálva!");
    }
}

