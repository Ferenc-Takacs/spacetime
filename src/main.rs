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
    #[allow(unused)]
    pub buffer_b: wgpu::Buffer,
    pub staging_buffer: wgpu::Buffer,
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pub dims_data: GridDimensions,
    pub buffer_data: Vec<MetricPoints>,
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
    pad1: u32,
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

        // Shader és Pipeline felépítése
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Spacetime Curvature Shader"),
            source: wgpu::ShaderSource::Wgsl(WGSL_CODE.into()),
        });
        println!("Shader OK");



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

        let grid_size = (app.grid.width * app.grid.height * app.grid.depth) as u64;
        let bytes_per_point = 52*4; //std::mem::size_of::<MetricPoints>() as u64; // 52 darab f32 pontonként
        let io_buffer_size = grid_size * bytes_per_point;

        let buffer_a = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spacetime Storage Buffer A"),
            size: io_buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let buffer_b = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spacetime Storage Buffer B"),
            size: io_buffer_size,
            usage: wgpu::BufferUsages::STORAGE,// | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let staging_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Staging Buffer"),
            size: io_buffer_size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        
        let buffer_data = vec![MetricPoints::zeroed(); grid_size as usize];

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

        
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Compute Pipeline Layout"),
            bind_group_layouts: &[&bind_group_layout],
            //bind_group_layouts: &[Some(&bind_group_layout)], // for v0.35
            //immediate_size: 0, // v0.35 kompatibilis mező // for v0.35
            push_constant_ranges: &[], // for v0.33
        });

        let compute_pipeline_1 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase1"),
            compilation_options: Default::default(),
            cache: None,
        });

        let compute_pipeline_2 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase2"),
            compilation_options: Default::default(),
            cache: None,
        });

        let compute_pipeline_3 = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Spacetime Compute Pipeline 1"),
            layout: Some(&pipeline_layout),
            module: &shader,
            entry_point: Some("phase3"),
            compilation_options: Default::default(),
            cache: None,
        });

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
            dims_data: app.dims_data,
            buffer_data: buffer_data,
        })
    }
    
    fn copy_dims(&mut self, dims: GridDimensions) {
        self.dims_data = dims;
    }

    fn get_dims(&self, dims: & mut GridDimensions) {
        *dims = self.dims_data.clone();
    }

    fn get_buffer(&self, grid_data: &mut Vec<MetricPoints>) {
        *grid_data = self.buffer_data.clone();
        //println!("{}", self.buffer_data.len());
    }

    fn write_buffer(&mut self, grid_data: &Vec<MetricPoints>) {
        self.buffer_data = grid_data.clone();
        self.queue.write_buffer(&self.buffer_a, 0, bytemuck::cast_slice(&self.buffer_data));
    }
    
    fn run_one_simulation_step( &mut self) {

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Spacetime Command Encoder"),
        });

        // @compute @workgroup_size(4, 4, 4)
        let workgroups_x = (self.dims_data.width + 3) / 4;
        let workgroups_y = (self.dims_data.height + 3) / 4;
        let workgroups_z = (self.dims_data.depth + 3) / 4;
        
        self.queue.write_buffer(&self.dims_buffer, 0, bytemuck::bytes_of(&self.dims_data));
        
        {
            let mut compute_pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Spacetime Compute Pass"),
                timestamp_writes: None,
            });
            
            compute_pass.set_bind_group(0, &self.bind_group, &[]);

            compute_pass.set_pipeline(&self.compute_pipeline_1);
            compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

            compute_pass.set_pipeline(&self.compute_pipeline_2);
            compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

            compute_pass.set_pipeline(&self.compute_pipeline_3);
            compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

            compute_pass.set_pipeline(&self.compute_pipeline_4);                        
            compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

            compute_pass.set_pipeline(&self.compute_pipeline_5);                        
            compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);
            
            self.dims_data.step_index += 1;
        }

        //let staging_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
        //    label: Some("Staging Buffer"),
        //    size: self.io_buffer_size,
        //    usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        //    mapped_at_creation: false,
        //});
        encoder.copy_buffer_to_buffer( &self.buffer_a, 0, &self.staging_buffer, 0, self.io_buffer_size );

        //self.queue.submit(Some(encoder.finish()));
        self.queue.submit(std::iter::once(encoder.finish()));

        let total_f32_elements = (self.dims_data.width * self.dims_data.height * self.dims_data.depth) as usize * 52;
        let mut local_data_copy = vec![0.0f32; total_f32_elements];
        
        let buffer_slice = self.staging_buffer.slice(..);
        let (sender, receiver) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |v| { let _ = sender.send(v);});
        let _ = self.device.poll(wgpu::PollType::wait_indefinitely());
        if let Ok(Ok(())) = receiver.try_recv() {
            {
                let data_view = buffer_slice.get_mapped_range();
                let result_data: &[f32] = bytemuck::cast_slice(&data_view);
                local_data_copy.copy_from_slice(result_data);
                drop(data_view);
            }
        }
        else {
            println!("Hiba: A GPU nem tudta megfelelően feltérképezni a memóriát!");
        }
        self.staging_buffer.unmap();

        let mut src_f32_idx = 0;
        for p in &mut self.buffer_data {
            p.data.copy_from_slice(&local_data_copy[src_f32_idx..src_f32_idx + 52]);
            src_f32_idx += 52;
        }
    }
    
}


struct SpacetimeApp {
    pub grid: SpacetimeGrid,
    pub dims_data: GridDimensions,
    pub gpu_interface: Option<std::sync::Arc<std::sync::Mutex<GpuInterface>>>,
    pub gpu_receiver: Option<std::sync::mpsc::Receiver<bool>>, // Háttérszál visszajelző csatorna
    pub gpu_in_progress: bool, // true = épp fut a számítás a háttérben, false = szabad a pálya

    pub view_texture: Option<egui::TextureHandle>,
    pub selected_z_slice: i32,
    pub slice_only_stats: bool,
    pub min_max_frame: usize,
    pub selected_scalar: i32, // 0: R, 1: K, 2: C2, 3: Feszültség
    pub selected_inf: bool,
    pub min_val: f32,
    pub max_val: f32,
    pub is_running_gpu: bool,
    //pub steps_per_frame: i32,

    pub is_recording: bool,
    pub waiting_for_screenshot: bool,
    pub maximum_z: i32, 
    pub original_z: i32,
    pub anim : Vec<image::DynamicImage>,
}

impl SpacetimeApp {
    fn new() -> Self {
        let width  = 53;
        let height = 53;
        let depth  = 53;
        let dx: f32 = 0.5;
        let dt: f32 = dx * 0.001;
        let m = 1.6;
        let r0 = 10.0;
        let grid = SpacetimeGrid::new(width, height, depth, dx, dt, m, r0);
        let dims_data = GridDimensions { width: width, height: height, depth: depth, dx: dx, dt: dt, step_index: 0, pad1: 0, pad2: 0,};
        Self {
            grid,
            dims_data,
            gpu_interface: None,
            gpu_receiver: None,
            gpu_in_progress: false,
            view_texture: None,
            selected_z_slice: width as i32/2, // depth/2
            slice_only_stats: true,
            min_max_frame: 0,
            selected_scalar: 43, // 0: R, 1: K, 2: C2, 3: Feszültség
            selected_inf: false,
            min_val: 0.0,
            max_val: 0.0,
            is_running_gpu: false,
            //steps_per_frame: 1,
            
            is_recording: false,
            waiting_for_screenshot: false,
            maximum_z: 0,
            original_z: 0,
            anim: Vec::new(),
        }
    }
    
    
    fn sclice_statistic( &mut self, ctx: &egui::Context) {
        if self.grid.data.is_empty()  || self.grid.data.len() == 0 {
            return; 
        }
        let width = self.grid.width as usize;
        let height = self.grid.height as usize;
        let depth = self.grid.depth as usize;
        if self.is_running_gpu {
            for z in 0..depth {
                for y in 0..height {
                    for x in 0..width {
                        let idx_1d = x + (y * width) + (z * width * height);
                        for d in 0..52 {
                            let val = self.grid.data[idx_1d].data[d];
                            if !val.is_finite() {
                                self.is_running_gpu = false;
                            }
                        }
                    }
                }
            }
        }
        
        let mut current_min = f32::MAX;
        let mut current_max = f32::MIN;
        let scalar_offset = self.selected_scalar as usize;
        self.selected_inf = false;
        let z_slice = self.selected_z_slice as usize;
        let x_min = self.min_max_frame;
        let x_max = width-self.min_max_frame;
        let y_min = self.min_max_frame;
        let y_max = height-self.min_max_frame;
        let z_min = self.min_max_frame;
        let z_max = depth-self.min_max_frame;
        for z in z_min..z_max {
            // Ha a Checkbox be van jelölve, a külső ciklus átugorja a többi Z-réteget
            if self.slice_only_stats && z != z_slice { continue; }            
            for y in y_min..y_max {
                for x in x_min..x_max {
                    let idx_1d = x + (y * width) + (z * width * height);
                    let val = self.grid.data[idx_1d].data[scalar_offset];
                    if val.is_finite() {
                        if val < current_min { current_min = val; }
                        if val > current_max { current_max = val; }
                    }
                    else {
                        self.selected_inf = true;
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

        for y in 0..height {
            for x in 0..width {
                let idx_1d = x + (y * width) + (z_slice * width * height);
                let val = self.grid.data[idx_1d].data[scalar_offset];
                let r;
                let g;
                let b;
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

        let mut redraw = false;

        ctx.input(|i| {
            for event in &i.events {
                if let egui::Event::Screenshot { image, .. } = event {
                    let size = image.size;
                    let pixels = &image.pixels;
                    let mut byte_pixels = Vec::with_capacity(pixels.len() * 4);
                    for pixel in pixels {
                        byte_pixels.push(pixel.r());
                        byte_pixels.push(pixel.g());
                        byte_pixels.push(pixel.b());
                        byte_pixels.push(pixel.a());
                    }
                    if let Some(buf) = image::ImageBuffer::<image::Rgba<u8>, _>::from_raw(
                        size[0] as u32,
                        size[1] as u32,
                        byte_pixels,
                    ) {
                        let img: image::DynamicImage = buf.into();
                        self.anim.push(img);
                    }
                    if self.selected_z_slice < self.maximum_z-1 {
                        self.selected_z_slice += 1;
                    }
                    else {
                        use webp_animation::{Encoder, EncoderOptions, EncodingConfig, EncodingType, LossyEncodingConfig};
                        let w = self.anim.first().unwrap().width();
                        let h = self.anim.first().unwrap().height();
                        let mut options  = EncoderOptions::default();
                        let mut config  = EncodingConfig::default();
                        let lossy =  LossyEncodingConfig::default();
                        let lossless = true;
                        let quality = 0.5;
                        config.quality = quality as f32;
                        config.encoding_type = if lossless {EncodingType::Lossless} else {EncodingType::Lossy(lossy)} ;
                        config.method = 3;
                        options .kmin  = 3;
                        options .kmax  = 5;
                        options.encoding_config = Some(config);
                        let mut encoder = Encoder::new_with_options((w,h),options)
                            .expect("Hiba a WebP animációs enkóder létrehozásakor");
                        let mut timestamp: i32 = 0;
                        for (_i, frame_img) in self.anim.iter().enumerate() {
                            let raw_data = frame_img.to_rgba8();
                            encoder.add_frame(raw_data.as_raw(), timestamp).expect("Hiba");
                            timestamp += 100 as i32;
                        }
                        let final_webp_data = encoder.finalize(timestamp)
                            .expect("Hiba az animáció lezárásakor");
                        let output_data = final_webp_data.to_vec();
                        let filename = format!("screenshots\\s_no_{}_var_{}.webp", self.dims_data.step_index, self.selected_scalar);
                        std::fs::write(&filename, output_data).expect("Fájl írási hiba");
                        self.selected_z_slice = self.original_z;
                        self.is_recording = false;
                        println!("Kész! {}",filename);
                    }
                    self.waiting_for_screenshot = false;
                }
            }
        });

        // 4. KÉNYSZERÍTETT ÚJRARAJZOLÁS: Ha tart a felvétel, azonnal kérjük a következő frame-et
        if self.is_recording {
            self.sclice_statistic(ctx);
            ctx.request_repaint();
        }

        if self.is_recording && !self.waiting_for_screenshot {
            if self.selected_z_slice < self.maximum_z {
                ctx.send_viewport_cmd(egui::ViewportCommand::Screenshot(egui::UserData::default()));
                self.waiting_for_screenshot = true;
            } else { // ready
                
            }
        }
        
        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize(egui::vec2(814.0, 572.0)));

        egui::CentralPanel::default().frame(egui::Frame::NONE.inner_margin(0.0)).show(ctx, |ui| {

            if self.gpu_interface.is_none() {
                if let Some(render_state) = frame.wgpu_render_state() {
                    println!("wgpu_render_state state exist, start ...");
                    if let Some(interface) = GpuInterface::init(render_state, &self) {
                        self.gpu_interface = Some(Arc::new(std::sync::Mutex::new(interface)));
                        self.gpu_in_progress = false;
                        self.gpu_receiver = None;
                        redraw = true;
                        println!("GPU OK");
                    }
                }
            }
            if self.gpu_interface.is_none() {
                ctx.request_repaint();
                return;
            }

            ui.separator();
            // IDŐLÉPÉST VEZÉRLŐ GOMBOK
            let mut press_once = false;
            ui.horizontal(|ui| {
                if ui.button("One Step Simulate").clicked() {
                    //self.run_one_simulation_step();
                    press_once = true;
                    //redraw = true;
                }

                // START / STOP GOMB
                let button_text = if self.is_running_gpu { "⏸ STOP Simulate" } else { "▶ START Simulate" };
                if ui.button(button_text).clicked() {
                    self.is_running_gpu = !self.is_running_gpu;
                }
                // AUTOMATIKUS MEGHÍVÁS: Ha fut a szimuláció, minden frame-en végrehajtunk egy időlépést
                if self.is_running_gpu || press_once {
                    if !self.gpu_in_progress {
                        if let Some(interface_arc) = &self.gpu_interface {                    
                            self.gpu_in_progress = true; // Zároljuk a felületet az újabb indítások ellen
                            if let Ok(mut interface) = interface_arc.lock() {
                                interface.copy_dims(self.dims_data);
                            }
                            // Klónozzuk az Arc mutatót a háttérszál számára (ez elképesztően olcsó művelet)
                            let interface_for_thread = interface_arc.clone();
                            let ctx_clone = ui.ctx().clone();
                            // Létrehozzuk az MPSC csatornát az időlépés végének jelzésére
                            let (tx, rx) = std::sync::mpsc::channel();
                            self.gpu_receiver = Some(rx);
                            std::thread::spawn(move || {
                                if let Ok(mut interface) = interface_for_thread.lock() {
                                    interface.run_one_simulation_step();
                                }
                                let _ = tx.send(true);
                                ctx_clone.request_repaint();
                            });
                        }
                    }
                }

                if let Some(receiver) = &self.gpu_receiver {
                    // A try_recv() nem-blokkoló: ha a háttérszál még dolgozik, azonnal továbblép, nincs akadás!
                    if let Ok(true) = receiver.try_recv() {
                        // Megérkezett a jel! Kivesszük az adatokat az interfészből a te get_buffer függvényeddel
                        if let Some(interface_arc) = &self.gpu_interface {
                            if let Ok(interface) = interface_arc.lock() {
                                interface.get_buffer(&mut self.grid.data);
                                interface.get_dims(&mut self.dims_data);
                            }
                        }
                        // Azonnal legeneráljuk az új hőtérkép textúrát a frissen beérkezett rácsból
                        //let ctx_clone = ui.ctx().clone();
                        self.sclice_statistic(ctx);
                        redraw = true;
                        // Felszabadítjuk a rendszert, a következő frame-en indulhat a következő automatikus kör!
                        self.gpu_in_progress = false;
                        self.gpu_receiver = None;
                        //println!("A szimuláció sikeresen beolvasta a {}. időlépést a RAM-ból!", self.dims_data.step_index);
                    }
                }
                
                if !self.is_running_gpu && ui.button("Save data (csv)").clicked() {
                    use std::fs::File;
                    use std::io::{Write, BufWriter};

                    let width = self.grid.width as i32;
                    let height = self.grid.height as i32;
                    let depth = self.grid.depth as i32;
                    let filename = format!(
                        "data_i{}_dx{:.4}_m{}_r{}.csv",
                        self.dims_data.step_index, self.dims_data.dx, self.grid.m, self.grid.r0
                    );
                    if let Ok(file) = File::create(&filename) {
                        let mut writer = BufWriter::new(file);
                        let head = "x,y,z,g00,g11,g22,g33,g01,g02,g03,g12,g13,g23,k00,k11,k22,k33,k01,k02,k03,k12,k13,k23,T00,T11,T22,T33,T01,T02,T03,T12,T13,T23,R00,R11,R22,R33,R01,R02,R03,R12,R13,R23,R,K,C2,Lambda,E11,E22,E12,|E|,B11,B22,B12,|B|\n";
                        let _ = writer.write_all(head.as_bytes());
                        for z in 0..self.grid.depth {
                            for y in 0..self.grid.height {
                                for x in 0..self.grid.width {
                                    let idx_1d = (x + (y * self.grid.width) + (z * self.grid.width * self.grid.height)) as usize;
                                    let gr = &self.grid.data[idx_1d];
                                    let cx = x as i32 - width / 2;
                                    let cy = y as i32 - height / 2;
                                    let cz = z as i32 - depth / 2;
                                    let mut row_string = format!("{},{},{},", cx, cy, cz);
                                    for i in 0..52 {
                                        if i == 51 {
                                            row_string += &format!("{}\n", gr.data[i]);
                                        } else {
                                            row_string += &format!("{},", gr.data[i]);
                                        }
                                    }
                                    let _ = writer.write_all(row_string.as_bytes());
                                }
                            }
                        }
                        let _ = writer.flush();
                        println!("A szimulációs adatok sikeresen kimentve a '{}' fájlba!", filename);
                    }
                }
                
                if !self.is_running_gpu && ui.button("Load data (csv)").clicked() {
                    use std::fs::File;
                    use std::io::{BufRead, BufReader};
                    let mut ok = true;
                    let dialog = rfd::FileDialog::new()
                        .set_title("Open CSV File ...")
                        .add_filter("csv", &["csv"]);
                    if let Some(filename) = dialog.pick_file() {
                        if let Ok(file) = File::open(&filename) {
                            if let Some(name) = filename.file_stem().and_then(|s| s.to_str()) {                                
                                let np: Vec<&str> = name.split('_').collect();
                                if np.len() >= 5 && np[1].starts_with('i') && np[2].starts_with("dx") &&
                                  np[3].starts_with('m') && np[4].starts_with('r') {
                                    if let Ok(val) = np[1][1..].parse::<u32>() { self.dims_data.step_index = val; } else { ok = false; }
                                    if let Ok(val) = np[2][2..].parse::<f32>() { self.dims_data.dx = val; } else { ok = false; }
                                    if let Ok(val) = np[3][1..].parse::<f32>() { self.grid.m = val; } else { ok = false; }
                                    if let Ok(val) = np[4][1..].parse::<f32>() { self.grid.r0 = val; } else { ok = false; }
                                }
                            } else { ok = false; }
                            let width = self.grid.width as usize;
                            let height = self.grid.height as usize;
                            let reader = BufReader::new(file);
                            let mut head = false;
                            for line_result in reader.lines() {
                                if ok  && let Ok(line_str) = line_result {
                                    let trimmed = line_str.trim();
                                    if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(';') {
                                        continue;
                                    }
                                    if !head {
                                        if !trimmed.starts_with("x,y,z,g00,") { ok = false; break; }
                                        head = true;
                                        continue;
                                    }
                                    let parts: Vec<&str> = trimmed.split(',').collect();
                                    if parts.len() >= 55 {
                                        let cx = parts[0].parse::<i32>().unwrap_or(0);
                                        let cy = parts[1].parse::<i32>().unwrap_or(0);
                                        let cz = parts[2].parse::<i32>().unwrap_or(0);
                                        let x = (cx + (self.grid.width as i32) / 2) as u32;
                                        let y = (cy + (self.grid.height as i32) / 2) as u32;
                                        let z = (cz + (self.grid.depth as i32) / 2) as u32;
                                        if x < self.grid.width && y < self.grid.height && z < self.grid.depth {
                                            let idx_1d = x as usize + (y as usize * width) + (z as usize * width * height);
                                            for i in 0..52 {
                                                if let Ok(val) = parts[i + 3].trim().parse::<f32>() {
                                                    self.grid.data[idx_1d].data[i] = val;
                                                }
                                            }
                                        } else { ok = false; break; }
                                    } else { ok = false;  break; }
                                } else { ok = false;  break; }
                            }
                            if ok && let Some(interface_arc) = &self.gpu_interface {                    
                                if let Ok(mut interface) = interface_arc.lock() {
                                    println!("A szimulációs adatok sikeresen visszaolvasva");
                                    interface.write_buffer(&self.grid.data);
                                    interface.copy_dims(self.dims_data);
                                } else { ok = false; }
                            } else { ok = false; }
                        } else { ok = false; }
                        if ok {
                            self.sclice_statistic(ctx);
                            ui.ctx().request_repaint();
                        }
                    }
                }
                
                if !self.is_running_gpu && ui.button("Save z animation").clicked() {
                    self.anim = Vec::new();
                    self.original_z = self.selected_z_slice;
                    self.maximum_z = self.grid.depth as i32;
                    self.selected_z_slice = 0;
                    self.is_recording = true;
                    self.waiting_for_screenshot = false;
                    self.sclice_statistic(ctx);
                    ui.ctx().request_repaint();
                }
            });
            ui.separator();
        });

        egui::Window::new(format!("Space grid size: {}x{}x{}", self.grid.width, self.grid.height, self.grid.depth))
            .fixed_pos(egui::pos2(0.0, 35.0))
            .fixed_size(egui::vec2(800.0, 500.0))
            .show(ctx, |ui| {
            ui.vertical(|ui| {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        if let Some(texture) = self.view_texture.as_ref() {
                            let size = 480.0;
                            egui::Frame::canvas(ui.style())
                                .stroke(egui::Stroke::new(1.5, egui::Color32::LIGHT_GRAY))
                                .show(ui, |ui| {
                                    let image_response = ui.image((texture.id(), egui::vec2(size, size)));
                                    //if !self.is_running_gpu {
                                        if !self.grid.data.is_empty() && self.grid.data.len() != 0 {
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
                                                    let val    = self.grid.data[idx_1d].data[self.selected_scalar as usize];
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
                                                        ui.label(format!("{}", val));
                                                    });
                                                }
                                            }
                                        }
                                    //}
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
                        ui.label(format!("Maximum: {} {}", self.max_val, if self.selected_inf{"*"}else{""}));
                        ui.horizontal(|ui| {
                            ui.label(format!("dx: {}", self.dims_data.dx));
                            ui.label(format!("dt: {}", self.dims_data.dt));
                            ui.label(format!("m: {}",  self.grid.m));
                            ui.label(format!("r0: {}", self.grid.r0));
                        });
                        
                        ui.separator();
                        ui.horizontal(|ui| {
                            ui.vertical(|ui| {
                                ui.label(" Metric:");
                                if ui.radio_value(&mut self.selected_scalar, 0, "00").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 1, "11").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 2, "22").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 3, "33").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 4, "01").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 5, "02").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 6, "03").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 7, "12").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 8, "13").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 9, "23").changed() { redraw = true; }
                            });
                            ui.vertical(|ui| {
                                ui.label(" Moments:");
                                if ui.radio_value(&mut self.selected_scalar, 10, "00").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 11, "11").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 12, "22").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 13, "33").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 14, "01").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 15, "02").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 16, "03").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 17, "12").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 18, "13").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 19, "23").changed() { redraw = true; }
                            });
                            ui.vertical(|ui| {
                                ui.label(" Energy:");
                                if ui.radio_value(&mut self.selected_scalar, 20, "00").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 21, "11").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 22, "22").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 23, "33").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 24, "01").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 25, "02").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 26, "03").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 27, "12").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 28, "13").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 29, "23").changed() { redraw = true; }
                            });
                            ui.vertical(|ui| {
                                ui.label(" Ricci tenzor:");
                                if ui.radio_value(&mut self.selected_scalar, 30, "00").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 31, "11").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 32, "22").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 33, "33").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 34, "01").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 35, "02").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 36, "03").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 37, "12").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 38, "13").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 39, "23").changed() { redraw = true; }
                            });
                        });
                        ui.horizontal(|ui| {
                            ui.vertical(|ui| {
                                if ui.radio_value(&mut self.selected_scalar, 40, "Ricci Skalár (R)").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 41, "Kretschmann (K)").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 42, "Weyl-négyzet (C²)").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 43, "Gravity tension").changed() { redraw = true; }
                            });
                            ui.vertical(|ui| {
                                if ui.radio_value(&mut self.selected_scalar, 44, "E.11").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 45, "E.22").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 46, "E.12").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 47, "|E|").changed() { redraw = true; }
                            });
                            ui.vertical(|ui| {
                                if ui.radio_value(&mut self.selected_scalar, 48, "B.11").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 49, "B.22").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 50, "B.12").changed() { redraw = true; }
                                if ui.radio_value(&mut self.selected_scalar, 51, "|B|").changed() { redraw = true; }
                            });
                        });

                        ui.scope(|ui| {
                            ui.style_mut().spacing.slider_width = 240.0; 
                            if ui.add(egui::Slider::new(&mut self.selected_z_slice, 0..=(self.grid.depth as i32 - 1)).text("Z")).changed() { 
                                redraw = true; 
                            }
                        });
                        ui.horizontal(|ui| {
                            if ui.checkbox(&mut self.slice_only_stats, "min/max at Z").changed() {
                                redraw = true;
                            }
                            let fmax = (self.grid.depth/6)as usize;
                            ui.style_mut().spacing.slider_width = 50.0; 
                            if ui.add(egui::Slider::new(&mut self.min_max_frame, 0..=fmax).text("min/max frame")).changed() { 
                                redraw = true; 
                            }
                        });
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
pub struct MetricPoints {
    pub data: [f32; 52],
}

// A teljes 3D rácsot tartalmazó struktúra
pub struct SpacetimeGrid {
    pub width: u32,
    pub height: u32,
    pub depth: u32,
    pub dx: f32,
    pub dt: f32,
    pub m: f32,
    pub r0: f32,
    pub data: Vec<MetricPoints>,
}

impl SpacetimeGrid {
    // Kényelmi függvény a rács létrehozásához üres adatokkal
    pub fn new(width: u32, height: u32, depth: u32, dx: f32, dt: f32, m: f32, r0: f32) -> Self {
        let size = (width * height * depth) as usize;
        let data = vec![MetricPoints::zeroed(); size]; // nullára inicializálunk!!!
        let mut grid =  SpacetimeGrid{ width, height, depth, dx, dt, m, r0, data };
        grid.one_static_schwarzschild(); // Tesztadatok feltöltése
        grid
    }
    pub fn one_static_schwarzschild(&mut self) {
        let cx = (self.width-1) as f32 / 2.0;
        let cy = (self.height-1) as f32 / 2.0;
        let cz = (self.depth-1) as f32 / 2.0;

        let a_spin = 0.02; 

        for z in 0..self.depth {
            for y in 0..self.height {
                for x in 0..self.width {
                    let idx = (x + y * self.width + z * self.width * self.height) as usize;

                    let rx = (x as f32 - cx) * self.dx;
                    let ry = (y as f32 - cy) * self.dx;
                    let rz = (z as f32 - cz) * self.dx;
                    
                    let r2 = rx*rx + ry*ry + rz*rz;
                    let r = r2.sqrt();
                    let regularized_r = (r2 + self.r0*self.r0).sqrt();
                    // 1. SZABÁLYOSÍTOTT SCHWARZSCHILD IDŐ-FAKTOR (A te tágulási képleted)
                    let f = 1.0 - (2.0 * self.m * r2) / (r2 * r + self.r0 * self.r0 * self.r0);
                    
                    let denom = regularized_r * regularized_r + a_spin * a_spin;
                    let l_0 = 1.0;
                    let l_1 = (regularized_r * rx + a_spin * ry) / denom;
                    let l_2 = (regularized_r * ry - a_spin * rx) / denom;
                    let l_3 = rz / regularized_r;

                    // Diagonális metrika (Minkowski + Kerr-Schild faktor)
                    self.data[idx].data[0] = -1.0 + f * l_0 * l_0 - 1.0 / denom;
                    self.data[idx].data[1] =  1.0 + f * l_1 * l_1;
                    self.data[idx].data[2] =  1.0 + f * l_2 * l_2;
                    self.data[idx].data[3] =  1.0 + f * l_3 * l_3;

                    // BEINDÍTJUK A TÉRIDŐ KERESZT-TAGJAIT (Idő-Tér elcsavarodás)
                    self.data[idx].data[4] = f * l_0 * l_1; // g01
                    self.data[idx].data[5] = f * l_0 * l_2; // g02
                    self.data[idx].data[6] = f * l_0 * l_3; // g03

                    // Térbeli elcsavarodások (X-Y, X-Z, Y-Z)
                    self.data[idx].data[7] = f * l_1 * l_2; // g12
                    self.data[idx].data[8] = f * l_1 * l_3; // g13
                    self.data[idx].data[9] = f * l_2 * l_3; // g23

                    // Kirajzoláshoz tesztként elmentjük a G feszültség helyére (s[3]) az f faktort
                    self.data[idx].data[43] = f;

                }
            }
        }
        self.calculate_moments();
        println!("Az Izotróp nemszinguláris Schwarzschild mező sikeresen generálva!");
    }

    fn extract_metric_element(p: &Metricpoint, a: u32, b: u32) -> f32 {
        let mut u = a;
        let mut v = b;
        if a > b { u = b; v = a; }
        if u == 0 && v == 0 { return p.d[0]; }
        if u == 1 && v == 1 { return p.d[1]; }
        if u == 2 && v == 2 { return p.d[2]; }
        if u == 3 && v == 3 { return p.d[3]; }
        if u == 0 && v == 1 { return p.d[4]; }
        if u == 0 && v == 2 { return p.d[5]; }
        if u == 0 && v == 3 { return p.d[6]; }
        if u == 1 && v == 2 { return p.d[7]; }
        if u == 1 && v == 3 { return p.d[8]; }
        if u == 2 && v == 3 { return p.d[9]; }
        return 0.0;
    }

    fn get_deriv(&self, mu: u32, a: u32, b: u32, d: &Derive) -> f32 {
        if mu == 0 { // nothing
            return 0.0;
        }
        else if mu == 1 { return (Self::extract_metric_element(&d.g_x_p, a, b) - Self::extract_metric_element(&d.g_x_m, a, b)) * d.d_x; }
        else if mu == 2 { return (Self::extract_metric_element(&d.g_y_p, a, b) - Self::extract_metric_element(&d.g_y_m, a, b)) * d.d_y; }
        else            { return (Self::extract_metric_element(&d.g_z_p, a, b) - Self::extract_metric_element(&d.g_z_m, a, b)) * d.d_z; }
    }

    fn get_metric(&self, x: i32, y: i32, z: i32, same: &mut bool) -> Metricpoint {
        let x_ = x.clamp(0, self.width as i32 - 1);
        let y_ = y.clamp(0, self.height as i32 - 1);
        let z_ = z.clamp(0, self.depth as i32 - 1);
        *same = x==x_ && y==y_ && z==z_;
        let idx = (x_ as u32 + y_ as u32 * self.width + z_ as u32 * self.width * self.height) as usize;
        let mets =  self.data[idx];
        let mut met = Metricpoint{ d: [0.0; 10], };
        for i in 0..10 {
            met.d[i] = mets.data[i];
        }
        return met;
    }

    fn set_metric(&mut self, x: u32,y: u32,z: u32, met: &Metricpoint, offs: usize) {
        let idx = (x + y * self.width + z * self.width * self.height) as usize;
        let mut mets = self.data[idx];
        for i in 0..10 {
            mets.data[i+offs] = met.d[i];
        }
        self.data[idx] = mets;
    }

    pub fn calculate_moments(&mut self) {

        for z_ in 0..self.depth {
            let z = z_ as i32;
            for y_ in 0..self.height {
                let y = y_ as i32;
                for x_ in 0..self.width {
                    let x = x_ as i32;

                    let mut der = Derive::new();
                    let mut same_p = true;
                    let mut same_m = true;
                    der.d_x = 1.0 / (2.0 * self.dx);
                    der.d_y = der.d_x;
                    der.d_z = der.d_x;
                    der.d_t = self.dt;
                    der.g_center = self.get_metric(x,y,z, &mut same_p);
                    der.g_x_p = self.get_metric(x+1,y  ,z  , &mut same_p);
                    der.g_x_m = self.get_metric(x-1,y  ,z  , &mut same_m);
                    if !same_p || !same_m { der.d_x = der.d_x * 2.0;}
                    der.g_y_p = self.get_metric(x  ,y+1,z  , &mut same_p);
                    der.g_y_m = self.get_metric(x  ,y-1,z  , &mut same_m);
                    if !same_p || !same_m { der.d_y = der.d_y * 2.0;}
                    der.g_z_p = self.get_metric(x  ,y  ,z+1, &mut same_p);
                    der.g_z_m = self.get_metric(x  ,y  ,z-1, &mut same_m);
                    if !same_p || !same_m { der.d_z = der.d_z * 2.0;}
                    // A legelső körben (t=0) a momentumokat a térbeli elcsavarodás deriváltjaiból generáljuk le!
                    // Diagonális momentumok kezdetben zérók statikus/forgó egyensúlynál
                    let mut k_past = Metricpoint{ d: [0.0; 10], };
                    //k_past.d[0] = 0.0; k_past.d[1] = 0.0; k_past.d[2] = 0.0; k_past.d[3] = 0.0;
                    // A Kerr-Schild elcsavarodási kereszt-tagok numerikus deriválása:
                    // k_ij = 0.5 * (d_i g_0j + d_j g_0i) -> a te extract_metric_element függvényedet használva:
                    let d1_g01 = self.get_deriv(1, 0, 1, &der); // M=1, N=(0,1)
                    let d2_g02 = self.get_deriv(2, 0, 2, &der);
                    let d3_g03 = self.get_deriv(3, 0, 3, &der);
                    
                    let d1_g02 = self.get_deriv(1, 0, 2, &der);
                    let d2_g01 = self.get_deriv(2, 0, 1, &der);
                    
                    let d1_g03 = self.get_deriv(1, 0, 3, &der);
                    let d3_g01 = self.get_deriv(3, 0, 1, &der);
                    
                    let d2_g03 = self.get_deriv(2, 0, 3, &der);
                    let d3_g02 = self.get_deriv(3, 0, 2, &der);
                    
                    k_past.d[4] = d1_g01;                      // k01 = 0.5 * (d_1 g_01 + d_1 g_01) = d_1 g_01
                    k_past.d[5] = 0.5 * (d1_g02 + d2_g01);     // k02
                    k_past.d[6] = 0.5 * (d1_g03 + d3_g01);     // k03
                    k_past.d[7] = d2_g02;                      // k12 = d_2 g_02
                    k_past.d[8] = 0.5 * (d2_g03 + d3_g02);     // k13
                    k_past.d[9] = d3_g03;                      // k23 = d_3 g_03
                    self.set_metric(x_,y_,z_, &k_past, 10);

                }
            }
        }
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
#[warn(unused)]
pub struct Metricpoint {
    pub d: [f32; 10],
}

struct Derive {
    g_center: Metricpoint,
    g_x_p:    Metricpoint,
    g_x_m:    Metricpoint,
    g_y_p:    Metricpoint,
    g_y_m:    Metricpoint,
    g_z_p:    Metricpoint,
    g_z_m:    Metricpoint,
    d_x:      f32,
    d_y:      f32,
    d_z:      f32,
    d_t:      f32,
}
impl Derive {
    fn new() -> Self {
        Self {
            g_center: Metricpoint{ d: [0.0; 10],},
            g_x_p:    Metricpoint{ d: [0.0; 10],},
            g_x_m:    Metricpoint{ d: [0.0; 10],},
            g_y_p:    Metricpoint{ d: [0.0; 10],},
            g_y_m:    Metricpoint{ d: [0.0; 10],},
            g_z_p:    Metricpoint{ d: [0.0; 10],},
            g_z_m:    Metricpoint{ d: [0.0; 10],},
            d_x:      0.0,
            d_y:      0.0,
            d_z:      0.0,
            d_t:      0.0,
       }
    }
}

