local osci3d = pd.Class:new():register("osci3d~")

function osci3d:initialize(sel, atoms)
  self.BUFFERSIZE = 512
  self.SAMPLING_INTERVAL = 8
  self.DRAW_GRID = 1
  self.SIZE = type(atoms[1]) == "number" and atoms[1] or 480
  self.STROKE_WIDTH = 1
  self.ZOOM = 1
  self.COLOR = {Colors.foreground}

  self.PERSPECTIVE = 1

  self.inlets = {SIGNAL, SIGNAL, SIGNAL, DATA}
  self.outlets = 0
  self.signal = {}
  self.rotatedSignal = {}
  -- fill ring buffer
  for i = 1, self.BUFFERSIZE do 
    self.signal[i] = {0, 0, 0}
    self.rotatedSignal[i] = {0, 0, 0}
  end
  self.signalIndex = 1
  self.dragStartX, self.dragStartY = 0, 0
  self.rotationAngleX, self.rotationAngleY = 0, 0
  self.rotationStartAngleX, self.rotationStartAngleY = 0, 0
  self.cameraDistance = 6
  self.gridLines = self:createGrid(-2, 2, 0.5)
  self.gui = 1
  self:set_size(self.SIZE, self.SIZE)
  return true
end

function osci3d:postinitialize()
  self.clock = pd.Clock:new():register(self, "tick")
  self.clock:delay(20)
end

function osci3d:finalize()
  self.clock:destruct()
end

function osci3d:tick()
  self:repaint()
  self.clock:delay(20)
end

function osci3d:createGrid(minVal, maxVal, step)
  local grid = {}
  for i = minVal, maxVal, step do
    table.insert(grid, {{i, 0, minVal}, {i, 0, maxVal}})
    table.insert(grid, {{minVal, 0, i}, {maxVal, 0, i}})
  end
  return grid
end

function osci3d:mouse_down(x, y)
  self.dragStartX, self.dragStartY = x, y
end

function osci3d:mouse_up(x, y)
  self.rotationStartAngleX, self.rotationStartAngleY = self.rotationAngleX, self.rotationAngleY
end

function osci3d:mouse_drag(x, y)
  self.rotationAngleY = self.rotationStartAngleY + ((x-self.dragStartX) / 50)
  self.rotationAngleX = self.rotationStartAngleX - ((y-self.dragStartY) / 50)
end

function osci3d:perform(in1, in2, in3)
  for i = 1, #in1, self.SAMPLING_INTERVAL do
    -- circular buffer
    self.signal[self.signalIndex] = {in1[i], in2[i], in3[i]}
    self.signalIndex = (self.signalIndex % self.BUFFERSIZE) + 1
  end
end

function osci3d:paint(g)
  g.set_color(Colors.background)
  g.fill_all()

  -- draw ground grid
  if self.DRAW_GRID == 1 then
    g.set_color(192, 192, 192)
    for i = 1, #self.gridLines do
      local lineFrom, lineTo = table.unpack(self.gridLines[i])
      
      -- apply rotation to grid lines
      lineFrom = self:rotateY(lineFrom, self.rotationAngleY)
      lineFrom = self:rotateX(lineFrom, self.rotationAngleX)
      lineTo   = self:rotateY(lineTo  , self.rotationAngleY)
      lineTo   = self:rotateX(lineTo  , self.rotationAngleX)

      local startX, startY = self:projectVertex(lineFrom, self.ZOOM)
      local   endX,   endY = self:projectVertex(  lineTo, self.ZOOM)
      if lineFrom[3] > -self.cameraDistance and lineTo[3] > -self.cameraDistance then
        g.draw_line(startX, startY, endX, endY, 1)
      end
    end
  end

  for i = 1, self.BUFFERSIZE do
    local offsetIndex = (i + self.signalIndex-2) % self.BUFFERSIZE + 1
    local rotatedVertex = self:rotateY(self.signal[offsetIndex], self.rotationAngleY)
    self.rotatedSignal[i] = self:rotateX(rotatedVertex, self.rotationAngleX)
  end

  g.set_color(table.unpack(self.COLOR))
  local p = path.start(self:projectVertex(self.rotatedSignal[1], self.ZOOM))
  for i = 2, self.BUFFERSIZE do
    p:line_to(self:projectVertex(self.rotatedSignal[i], self.ZOOM))
  end
  g.stroke_path(p, self.STROKE_WIDTH)
end

function osci3d:rotateY(vertex, angle)
  local x, y, z = table.unpack(vertex)
  local cosTheta = math.cos(angle)
  local sinTheta = math.sin(angle)
  local newX = x * cosTheta - z * sinTheta
  local newZ = x * sinTheta + z * cosTheta
  return {newX, y, newZ}
end

function osci3d:rotateX(vertex, angle)
  local x, y, z = table.unpack(vertex)
  local cosTheta = math.cos(angle)
  local sinTheta = math.sin(angle)
  local newY = y * cosTheta - z * sinTheta
  local newZ = y * sinTheta + z * cosTheta
  return {x, newY, newZ}
end

function osci3d:projectVertex(vertex)
  local scale = self.cameraDistance / (self.cameraDistance + vertex[3] * self.PERSPECTIVE)
  local screenX = self.SIZE / 2 + (vertex[1] * scale * self.ZOOM * self.SIZE * 0.25)
  local screenY = self.SIZE / 2 - (vertex[2] * scale * self.ZOOM * self.SIZE * 0.25)
  return screenX, screenY
end

function osci3d:in_4_zoom(x)
  self.ZOOM = x[1]
end

function osci3d:in_4_grid(x)
  self.DRAW_GRID = x[1]
end

function osci3d:in_4_resize(x)
  self.SIZE = math.max(64, x[1])
  self:set_size(self.SIZE, self.SIZE)
end

function osci3d:in_4_buffer(x)
  self.BUFFERSIZE = math.max(2, math.floor(x[1]))
  self.signal = {}
  self.rotatedSignal = {}
  for i = 1, self.BUFFERSIZE do 
    self.signal[i] = {0, 0, 0}
    self.rotatedSignal[i] = {0, 0, 0}
  end
end

function osci3d:in_4_interval(x)
  self.SAMPLING_INTERVAL = math.max(1, math.floor(x[1]))
end

function osci3d:in_4_stroke(x)
  self.STROKE_WIDTH = math.max(1, x[1])
end

function osci3d:in_4_perspective(x)
  self.PERSPECTIVE = x[1]
end

function osci3d:in_4_reset()
  self.rotationAngleX, self.rotationAngleY = 0, 0
  self.COLOR = {Colors.foreground}
  self.ZOOM = 1
end

function osci3d:in_4_color(x)
  self.COLOR = {x[1], x[2], x[3]}
end