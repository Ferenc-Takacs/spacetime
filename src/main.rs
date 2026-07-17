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
    pub bind_group: wgpu::BindGroup,
    pub buffer_a: wgpu::Buffer,
    pub buffer_b: wgpu::Buffer,
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
        let bytes_per_point = std::mem::size_of::<MetricPoint>() as u64; // 44 darab f32 pontonként
        let buffer_size = grid_size * bytes_per_point;

        let buffer_a = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spacetime Storage Buffer A"),
            size: buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        println!("{}",4);

        let buffer_b = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Spacetime Storage Buffer B"),
            size: buffer_size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        println!("{}",5);

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Spacetime Main Bind Group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: dims_buffer.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: buffer_a.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 2, resource: buffer_b.as_entire_binding() },
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
            io_buffer_size: buffer_size,
            compute_pipeline_1: compute_pipeline_1,
            compute_pipeline_2: compute_pipeline_2,
            compute_pipeline_3: compute_pipeline_3,
            compute_pipeline_4: compute_pipeline_4,
            bind_group: bind_group,
            buffer_a: buffer_a,
            buffer_b: buffer_b,
            device: device.into(),
            queue: queue.into(),
        })
    }
}


struct SpacetimeApp {
    pub grid: SpacetimeGrid,
    pub dims_data: GridDimensions,
    pub gpu_interface: Option<GpuInterface>,
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
        }
    }
    
}

impl eframe::App for SpacetimeApp {
    fn update(&mut self, ctx: &egui::Context, frame: &mut eframe::Frame) {
        
        egui::CentralPanel::default().frame(egui::Frame::NONE.inner_margin(0.0)).show(ctx, |ui| {

            ui.heading("Módosított Téregyenlet Szimulátor");
            ui.separator();
 
            if self.gpu_interface.is_none() {
                if let Some(render_state) = frame.wgpu_render_state() {
                    println!("Most már van GPU állapota, indulhat a gpu_init...");
                    if let Some(interface) = GpuInterface::init(render_state, &self) {
                        self.gpu_interface = Some(interface);
                        println!("GPU INTERFÉSZ KÉSZ!");
                    }
                }
            }
            if self.gpu_interface.is_none() {
                ctx.request_repaint();
                return;
            }
 
            ui.label(format!("Rács mérete: {}x{}x{}", self.grid.width, self.grid.height, self.grid.depth));

            // 3. A GOMBNYOMÁSRA KÖZVETLENÜL INDÍTJUK A SZÁMÍTÁST (Nincs async deadlock)
            if ui.button("Görbületi Feszültség Számítása").clicked() {
                println!("Számítás indítása a GPU-n...");
                
                if let Some(interface) = &self.gpu_interface {

                    let mut encoder = interface.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                        label: Some("Spacetime Command Encoder"),
                    });

                    {
                        let mut compute_pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                            label: Some("Spacetime Compute Pass"),
                            timestamp_writes: None,
                        });
                        
                        // @compute @workgroup_size(4, 4, 4)
                        let workgroups_x = (self.grid.width + 3) / 4;
                        let workgroups_y = (self.grid.height + 3) / 4;
                        let workgroups_z = (self.grid.depth + 3) / 4;

                        compute_pass.set_bind_group(0, &interface.bind_group, &[]);

                        compute_pass.set_pipeline(&interface.compute_pipeline_1);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_2);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_3);
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);

                        compute_pass.set_pipeline(&interface.compute_pipeline_4);                        
                        compute_pass.dispatch_workgroups(workgroups_x, workgroups_y, workgroups_z);
                    }
                    interface.queue.submit(std::iter::once(encoder.finish()));
                    let _ = interface.device.poll(wgpu::PollType::wait_indefinitely());
                    //interface.device.poll(wgpu::Maintain::Wait);
                    println!("Az időlépés sikeresen lefutott a videókártyán!");

                    
                    // Másolás a staging bufferbe
                    //encoder.copy_buffer_to_buffer(&interface.text_a, 0, &interface.staging_buffer, 0, interface.io_buffer_size);

                    // Visszaolvasás a GPU-ról a már jól bevált mpsc csatornával
                    /*if let Some(staging_buffer) = &interface.staging_buffer {
                        let buffer_slice = staging_buffer.slice(..);
                        let (tx, rx) = std::sync::mpsc::channel();
                        
                        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
                            tx.send(result).unwrap();
                        });

                        // A WGPU belső állapotát frissítjük a parancsok végrehajtásához
                        // v0.35 asztali környezetben az instance helyett közvetlenül a device.poll() is pörgethető így:
                        //device.poll(wgpu::Maintain::Wait);
                        let _ = interface.device.poll(wgpu::PollType::wait_indefinitely());

                        if let Ok(Ok(())) = rx.recv() {
                            let data_view = buffer_slice.get_mapped_range();
                            let result_invariants: &[f32] = bytemuck::cast_slice(&data_view);

                            println!("Sikeres számítás! Első 5 rácspont görbületi feszültsége:");
                            for i in 0..5 {
                                println!("  Pont [{}]: {}", i, result_invariants[i]);
                            }

                            drop(data_view);
                            staging_buffer.unmap();
                        }
                    }*/
                }
            }
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
    pub fn one_static_schwarzschild(&mut self, m: f32, r0: f32){
        // m: A fekete lyuk tömege, r0: Regulázási/tágulási paraméter (a módosított egyenletedből)
        for z in 0..self.depth {
            for y in 0..self.height {
                for x in 0..self.width {
                    let idx = (x + y * self.width + z * self.width * self.height) as usize;
                    // Átváltunk a rácsindexekből fizikai koordinátákba (középponthoz képest)
                    let rx = (x as f32 - self.width as f32 / 2.0) * self.dx;
                    let ry = (y as f32 - self.height as f32 / 2.0) * self.dx;
                    let rz = (z as f32 - self.depth as f32 / 2.0) * self.dx;
                    let r2 = rx*rx + ry*ry + rz*rz;
                    let r = r2.sqrt();
                    // SZINGULARITÁSMENTES SCHWARZSCHILD-FAKTOR (Példa a tágulásra)
                    let f = 1.0 - (2.0 * m * r2) / (r2 * r + r0 * r0 * r0);
                    self.data[idx].g[0] = -f;       // Idő komponens
                    self.data[idx].g[1] = 1.0 / f;
                    self.data[idx].g[2] = 1.0 / f;
                    self.data[idx].g[3] = 1.0 / f;
                }
            }
        }
    }
}

