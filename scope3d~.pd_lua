local scope3d = pd.Class:new():register("scope3d~")

function scope3d:initialize(sel, atoms)
  self.SIZE = type(atoms[1]) == "number" and atoms[1] or 140
  self.FRAMEINTERVAL = self:interval_from_fps(50)
  self.inlets = {SIGNAL, SIGNAL, SIGNAL, DATA}
  self:reset()
  self.cameraDistance = 6
  self.gridLines = self:create_grid(-1, 1, 0.25)

  self:set_size(self.SIZE, self.SIZE)
  return true
end

function scope3d:interval_from_fps(fps)
  return 1 / fps * 1000
end

function scope3d:reset()
  self.BUFFERSIZE = 512
  self.bufferIndex = 1
  self.sampleIndex = 1
  self:reset_buffer()
  self.SAMPLING_INTERVAL = 8
  self.DRAW_GRID = 1
  self.STROKE_WIDTH = 1
  self.ZOOM = 1
  self.COLOR = {Colors.foreground}
  self.BACKGROUND = {Colors.background}
  self.PERSPECTIVE = 1
  self.rotationAngleX, self.rotationAngleY = 0, 0
  self.rotationStartAngleX, self.rotationStartAngleY = 0, 0
end

function scope3d:reset_buffer()
  self.signal = {}
  self.rotatedSignal = {}
  -- prefill ring buffer
  for i = 1, self.BUFFERSIZE do 
    self.signal[i] = {0, 0, 0}
    self.rotatedSignal[i] = {0, 0, 0}
  end
end

function scope3d:postinitialize()
  self.clock = pd.Clock:new():register(self, "tick")
  self.clock:delay(self.FRAMEINTERVAL)
end

function scope3d:finalize()
  self.clock:destruct()
end

function scope3d:tick()
  self:repaint()
  self.clock:delay(self.FRAMEINTERVAL)
end

function scope3d:create_grid(minVal, maxVal, step)
  local grid = {}
  for i = minVal, maxVal, step do
    table.insert(grid, {{i, 0, minVal}, {i, 0, maxVal}})
    table.insert(grid, {{minVal, 0, i}, {maxVal, 0, i}})
  end
  return grid
end

function scope3d:mouse_down(x, y)
  self.dragStartX, self.dragStartY = x, y
end

function scope3d:mouse_up(x, y)
  self.rotationStartAngleX, self.rotationStartAngleY = self.rotationAngleX, self.rotationAngleY
end

function scope3d:mouse_drag(x, y)
  self.rotationAngleY = self.rotationStartAngleY + ((x-self.dragStartX) / 2)
  self.rotationAngleX = self.rotationStartAngleX - ((y-self.dragStartY) / 2)
end

function scope3d:dsp(samplerate, blocksize)
    self.blocksize = blocksize
end

function scope3d:perform(in1, in2, in3)
  while self.sampleIndex <= self.blocksize do
    -- circular buffer
    self.signal[self.bufferIndex] = {in1[self.sampleIndex], in2[self.sampleIndex], in3[self.sampleIndex]}
    self.bufferIndex = (self.bufferIndex % self.BUFFERSIZE) + 1
    self.sampleIndex = self.sampleIndex + self.SAMPLING_INTERVAL
  end
  self.sampleIndex = self.sampleIndex - self.blocksize
end

function scope3d:paint(g)
  g.set_color(table.unpack(self.BACKGROUND))
  g.fill_all()

  -- draw ground grid
  if self.DRAW_GRID == 1 then
    g.set_color(192, 192, 192)
    for i = 1, #self.gridLines do
      local lineFrom, lineTo = table.unpack(self.gridLines[i])
      
      -- apply rotation to grid lines
      lineFrom = self:rotate_y(lineFrom, self.rotationAngleY)
      lineFrom = self:rotate_x(lineFrom, self.rotationAngleX)
      lineTo   = self:rotate_y(lineTo  , self.rotationAngleY)
      lineTo   = self:rotate_x(lineTo  , self.rotationAngleX)

      local startX, startY = self:projectVertex(lineFrom, self.ZOOM)
      local   endX,   endY = self:projectVertex(  lineTo, self.ZOOM)
      if lineFrom[3] > -self.cameraDistance and lineTo[3] > -self.cameraDistance then
        g.draw_line(startX, startY, endX, endY, 1)
      end
    end
  end

  for i = 1, self.BUFFERSIZE do
    local offsetIndex = (i + self.bufferIndex-2) % self.BUFFERSIZE + 1
    local rotatedVertex = self:rotate_y(self.signal[offsetIndex], self.rotationAngleY)
    self.rotatedSignal[i] = self:rotate_x(rotatedVertex, self.rotationAngleX)
  end

  g.set_color(table.unpack(self.COLOR))
  local p = path.start(self:projectVertex(self.rotatedSignal[1], self.ZOOM))
  for i = 2, self.BUFFERSIZE do
    p:line_to(self:projectVertex(self.rotatedSignal[i], self.ZOOM))
  end
  g.stroke_path(p, self.STROKE_WIDTH)
end

function scope3d:rotate_y(vertex, angle)
  local x, y, z = table.unpack(vertex)
  local cosTheta = math.cos(angle * math.pi / 180)
  local sinTheta = math.sin(angle * math.pi / 180)
  local newX = x * cosTheta - z * sinTheta
  local newZ = x * sinTheta + z * cosTheta
  return {newX, y, newZ}
end

function scope3d:rotate_x(vertex, angle)
  local x, y, z = table.unpack(vertex)
  local cosTheta = math.cos(angle * math.pi / 180)
  local sinTheta = math.sin(angle * math.pi / 180)
  local newY = y * cosTheta - z * sinTheta
  local newZ = y * sinTheta + z * cosTheta
  return {x, newY, newZ}
end

function scope3d:projectVertex(vertex)
  local scale = self.cameraDistance / (self.cameraDistance + vertex[3] * self.PERSPECTIVE)
  local screenX = self.SIZE / 2 + (vertex[1] * scale * self.ZOOM * self.SIZE * 0.5)
  local screenY = self.SIZE / 2 - (vertex[2] * scale * self.ZOOM * self.SIZE * 0.5)
  return screenX, screenY
end

function scope3d:in_4_rotatex(x)
  if type(x[1]) == "number" then
    self.rotationAngleX = x[1]
  end
end

function scope3d:in_4_rotatey(x)
  if type(x[1]) == "number" then
    self.rotationAngleY = x[1]
  end
end

function scope3d:in_4_rotate(x)
  if type(x) == "table" and #x == 2 and
     type(x[1]) == "number" and
     type(x[2]) == "number" then
    self.rotationAngleX, self.rotationAngleY = x[1], x[2]
  end
end

function scope3d:in_4_zoom(x)
  self.ZOOM = type(x[1]) == "number" and x[1] or 1
end

function scope3d:in_4_grid(x)
  self.DRAW_GRID = type(x[1]) == "number" and x[1] or 1 - self.DRAW_GRID
end

function scope3d:in_4_size(x)
  if type(x[1]) == "number" then
    self.SIZE = math.max(64, x[1])
    self:set_size(self.SIZE, self.SIZE)
  end
end

function scope3d:in_4_buffer(x)
  if type(x[1]) == "number" then
    self.BUFFERSIZE = math.min(1024, math.max(2, math.floor(x[1])))
    self:reset_buffer()
  end
end

function scope3d:in_4_interval(x)
  if type(x[1]) == "number" then
    self.SAMPLING_INTERVAL = math.max(1, math.floor(x[1]))
  end
end

function scope3d:in_4_stroke(x)
  self.STROKE_WIDTH = type(x[1]) == "number" and math.max(1, x[1]) or 1
end

function scope3d:in_4_perspective(x)
  self.PERSPECTIVE = type(x[1]) == "number" and x[1] or 1
end

function scope3d:in_4_reset()
  self:reset()
end

function scope3d:in_4_framerate(x)
  if type(x[1]) == "number" then
    self.FRAMEINTERVAL = self:interval_from_fps(math.min(120, math.max(1, x[1])))
  end
end

function scope3d:in_4_color(x)
  if type(x) == "table" and #x == 3 and
     type(x[1]) == "number" and
     type(x[2]) == "number" and
     type(x[3]) == "number" then
    self.COLOR = {x[1], x[2], x[3]}
  end
end

function scope3d:in_4_background(x)
  if type(x) == "table" and #x == 3 and
     type(x[1]) == "number" and
     type(x[2]) == "number" and
     type(x[3]) == "number" then
    self.BACKGROUND = {x[1], x[2], x[3]}
  end
end