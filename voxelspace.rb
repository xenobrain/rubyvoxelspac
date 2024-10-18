SCALE = 175.0
LOD = 0.005
MAX_Z_FAR = 600.0
MIN_Z_FAR = 175.0
MIN_SCREEN_W = 70
MIN_SCREEN_H = 60
MAX_SCREEN_W = 360
MAX_SCREEN_H = 120
DRS_FRAME_WINDOW = 10
Z_FAR_ADJUST_SPEED = 1
SCREEN_ADJUST_SPEED = 1

def tick args
  #args.state.started ||= false
  #args.state.started = true if args.inputs.keyboard.space
  #return unless args.state.started

  defaults args
  render args
  input args
  calc args
end

def defaults args
  # Sample time at beginning of tick
  args.state.current_time = Time.now

  args.state.camera ||= create_camera args

  args.state.clear_color = [70, 164, 189]
  args.state.lod ||= LOD
  args.state.scale ||= SCALE
  args.state.screen_w ||= MAX_SCREEN_W
  args.state.screen_h ||= MAX_SCREEN_H
  args.state.frame_times ||= Array.new(DRS_FRAME_WINDOW, 0.01667)

  args.pixel_array(:terrain).w = args.state.screen_w
  args.pixel_array(:terrain).h = args.state.screen_h

  args.state.terrain_colormap ||= args.gtk.get_pixels 'sprites/maps/C1W.png'
  args.state.terrain_heightmap ||= args.gtk.get_pixels('sprites/maps/D1.png').pixels.map { |p| p & 0xFF }
end

def render args
  args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: 'sprites/sky.jpg' }
  render_terrain args
end

def input args
  camera = args.state.camera

  if args.inputs.keyboard.i
    camera.x += Math.cos camera.angle
    camera.y += Math.sin camera.angle
  end
  if args.inputs.keyboard.k
    camera.x -= Math.cos camera.angle
    camera.y -= Math.sin camera.angle
  end
  if args.inputs.keyboard.space
    camera.height += 1
  end
  if args.inputs.keyboard.control
    camera.height -= 1
  end

  camera.horizon -= args.inputs.controller_one.up_down * 1.1 #inverted controls
  camera.angle += args.inputs.controller_one.left_right * 0.01

  # thrust
  thrust = args.state.camera.thrust

  # TODO: Get forward vector and add thrust
  camera.x += Math.cos camera.angle
  camera.y += Math.sin camera.angle

  if args.inputs.controller_one.r2
    camera.x += Math.cos camera.angle
    camera.y += Math.sin camera.angle
  end
  if args.inputs.controller_one.l2
    camera.x -= Math.cos camera.angle
    camera.y -= Math.sin camera.angle
  end

  if args.inputs.controller_one.a
    puts "fire!"
  end
end

def calc args
  return unless args.state.tick_count.positive?

  # Get elapsed time since beginning of tick
  elapsed = Time.now - args.state.current_time
  args.state.frame_times.shift
  args.state.frame_times << elapsed

  delta_time = args.state.frame_times.sum / DRS_FRAME_WINDOW
  args.outputs.labels << { x: 10, y: 600, text: "frame_time(avg): #{elapsed}" }

  # DRS
  screen_w = args.state.screen_w
  z_far = args.state.camera.z_far

  if delta_time < 0.013 # Duplicated code is not a bug, this is meant to be cumulative to the < 0.015 check
    args.state.camera.z_far = (z_far + Z_FAR_ADJUST_SPEED*3).clamp MIN_Z_FAR, MAX_Z_FAR
  end

  if delta_time < 0.015
    args.state.screen_w = (screen_w + SCREEN_ADJUST_SPEED).clamp MIN_SCREEN_W, MAX_SCREEN_W
    args.state.camera.z_far = (z_far + Z_FAR_ADJUST_SPEED*2).clamp MIN_Z_FAR, MAX_Z_FAR
  end

  if delta_time > 0.018
    args.state.camera.z_far = (z_far - Z_FAR_ADJUST_SPEED).clamp MIN_Z_FAR, MAX_Z_FAR
  end

  if delta_time > 0.020
    args.state.camera.z_far = (z_far - Z_FAR_ADJUST_SPEED*3).clamp MIN_Z_FAR, MAX_Z_FAR
    args.state.screen_w = (screen_w - SCREEN_ADJUST_SPEED*3).clamp MIN_SCREEN_W, MAX_SCREEN_W
  end

  args.outputs.labels << { x: 10, y: 500, text: "screen_w: #{args.state.screen_w}, z_far #{args.state.camera.z_far}" }
end

def render_terrain args
  heights = args.state.terrain_heightmap
  colors = args.state.terrain_colormap.pixels
  pixels = args.pixel_array(:terrain).pixels
  map_n = args.state.terrain_colormap.w
  screen_w = args.state.screen_w
  screen_h = args.state.screen_h
  i_screen_w = 1.0 / screen_w
  scale = args.state.scale

  cr, cg, cb = *args.state.clear_color

  camera = args.state.camera
  sin = Math.sin camera.angle
  cos = Math.cos camera.angle
  cam_horizon = camera.horizon
  cam_height = camera.height
  lod = args.state.lod
  z_far = camera.z_far
  i_far = 1.0 / z_far
  cam_x = camera.x
  cam_y = camera.y

  plx = cos * z_far + sin * z_far
  ply = sin * z_far - cos * z_far
  prx = cos * z_far - sin * z_far
  pry = sin * z_far + cos * z_far

  x = 0
  while x < screen_w
    dx = (plx + (prx - plx) * i_screen_w * x) * i_far
    dy = (ply + (pry - ply) * i_screen_w * x) * i_far
    max_height = screen_h
    ray_x = cam_x
    ray_y = cam_y

    z = 1.0
    dz = 1.0
    while z < z_far
      ray_x += dx
      ray_y += dy

      map_offset = map_n * (ray_y & (map_n - 1)) + (ray_x & (map_n - 1))
      projected_height = ((cam_height - (heights.at map_offset)) / z * scale + cam_horizon).to_int

      if projected_height < max_height
        fog_t = (z * i_far)**6
        color = colors.at map_offset

        r = color & 0x000000FF
        g = (color & 0x0000FF00) >> 8
        b = (color & 0x00FF0000) >> 16
        color = color & 0xFFFFFF00 | (r + fog_t * (cr - r)).to_int
        color = color & 0xFFFF00FF | (g + fog_t * (cg - g)).to_int << 8
        color = color & 0xFF00FFFF | (b + fog_t * (cb - b)).to_int << 16

        y = projected_height
        while y < max_height
          pixels[screen_w * y + x] = color if y >= 0
          y += 1
        end

        max_height = projected_height
      end

      z += dz
      dz += lod
    end

    x += 1
  end

  args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :terrain }
end

def create_camera args
  { x: 512.0, y: 512.0, height: 70.0, horizon: 60.0, z_far: MAX_Z_FAR, angle: 1.5 * Math::PI }
end
