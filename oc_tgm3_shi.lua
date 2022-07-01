local os = require "os"
local event = require "event"
local component = require "component"
local gpu = component.gpu
local keyboard = require "keyboard"
local beep_available = component.isAvailable("beep")

local w, h = gpu.getViewport()

if w < 36 or h < 25 then
  error("That will be quite uncomfortable to play like this.")
  return 1
end
local in_menu = true
local menu_slice = 0
local menu_select = 1
local block_design = "██"

local board = {}
local full_lines = {}
local render_board = {}
local prev_render_board = {} --duplicate of it is for GPU optimization purposes.
local input_table = 
{
  keyboard.keys.left, --left key input
  keyboard.keys.up, --up key input or cw rotation
  keyboard.keys.right, --right key input
  keyboard.keys.down, --down key input or soft drop
  keyboard.keys.z, --z key input or ccw rotation
  keyboard.keys.x, --x key input or cw rotation
  keyboard.keys.c, --c key input or hold
  keyboard.keys.lcontrol, --left control key input or ccw rotation
  keyboard.keys.space, --space key input or hard drop
}
local menu_inputs =
{
  keyboard.keys.left, --left key input
  keyboard.keys.up, --up key input
  keyboard.keys.right, --right key input
  keyboard.keys.down, --down key input
  keyboard.keys.space,
  keyboard.keys.lshift
}
local prev_inputs = {["up"] = false, ["down"] = false, ["left"] = false, ["right"] = false, 
["cw"] = false, ["ccw"] = false, ["cw2"] = false, ["ccw2"] = false, ["hold"] = false,}
local bag = {}
local minos, mino_index = 4, 0
local hold_ID = 0
local is_held = false
local texture_ID = 1
local rotation_index = 0
local piece_pos = {x = 5, y = 21}
local spawn_delay = 25
local spawn_ticks = 0
local line_spawn_delay = 10
local line_drop_ticks = 0
local line_drop_delay = 15
local lock_delay = 30
local lock_ticks = 0
local gravity_tiles = 0
local is_ground = false
local is_spawned = false
local is_cleared = false
local running = true
local das_l, das_r = 0, 0
local das, prev_das = 10, 10
local arr, prev_arr = 2, 2
local sdf = 20
local pieces = 0
local line_count, level = 0, 1
local line_clone_left = 0
local piece_latencies = {}
local last_piece_time = 0.0
local time_frame = 0
local frame_scale = 1
local total_time, dt = 0.0, 0.0
function initBoard()
  board, render_board = {}, {}
  for i = 1, 400 do
    table.insert(board, 0)
    table.insert(render_board, "  ")
  end
  for i = 0, 21 do
    gpu.set(w/2-11, (h/2+7)-i, "<                    >")
  end
end
function mean(t)
    local sum = 0
    
    for _, v in ipairs(t) do
        sum = sum + v
    end
    return sum / #t
end
function getGravity()
  return 20
end
function getLockDelay()
  if level < 200 then return 18
  elseif level < 300 then return 17
  elseif level < 500 then return 15
  elseif level < 600 then return 13
  elseif level < 1100 then return 12
  elseif level < 1200 then return 10
  elseif level < 1300 then return 8
  else return 15 end
end
function getSpawnDelay()
  if level < 300 then return 12
  else return 6 end
end
function getLineDropDelay()
  if level < 1300 then return getLineSpawnDelay() - 2
  else return 6 end
end
function getLineSpawnDelay()
  if level < 100 then return 8
  elseif level < 200 then return 7
  elseif level < 500 then return 6
  elseif level < 1300 then return 5
  else return 6 end
end
function getGarbageLimit()
  if level < 500 then return math.huge
  elseif level < 600 then return 20
  elseif level < 700 then return 18
  elseif level < 800 then return 10
  elseif level < 900 then return 9
  else return 8 end
end
function getDAS()
    if level < 100 then return 9
  elseif level < 500 then return 7
  else return 5 end
end
function getPPS()
    if #piece_latencies == 0 then return 0 end
    piece_latencies[#piece_latencies + 1] = time_frame - last_piece_time
    local meanPPS = (mean(piece_latencies)/60) ^ -1
    table.remove(piece_latencies)
    return meanPPS
end
initBoard()
function borderedFloor(input, min, max)
  return math.floor(math.min(math.max(input, min), max))
end
function frameToMilli(frames)
  return math.floor(frames * 16.666 + 0.5)
end
function mulRGB(color, mr, mg, mb)
  local r, g, b
  r = math.floor(color/4^8)
  g = math.floor(color/2^8)%256
  b = color % 256  
  r = borderedFloor(r * mr, 0, 255)
  g = borderedFloor(g * mg, 0, 255)
  b = borderedFloor(b * mb, 0, 255)
  local result = (r * (4^8)) + (g * 256) + b
  return result
end
local color_matrix = 
{ 
  0xFFFF00, --O
  0x00FFFF, --I
  0x00FF00, --S
  0xFF0000, --Z
  0xFF8000, --L
  0x0000FF, --J
  0xFF00FF, --T
}
function renderBlock(x,y, str, clrid, fade)
  local block
  if clrid then block = clrid else block = board[y*10+x] end
  if str == nil then str = render_board[y * 10 + x] end
  if block > 0 then
    if fade then
      gpu.setForeground(mulRGB(color_matrix[block], 1-fade, 1-fade, 1-fade))
    else
      gpu.setForeground(color_matrix[block])
    end
  end
  gpu.set((w/2-12)+x*2,(h/2+7)-y,str)
end
local piece_blob_storage = 
{
    [0] =
    {0,0}, {1,0}, {1,1}, {0,1}, -- O piece rotation 0
    {0,0}, {1,0}, {1,1}, {0,1}, -- O piece rotation 1
    {0,0}, {1,0}, {1,1}, {0,1}, -- O piece rotation 2
    {0,0}, {1,0}, {1,1}, {0,1}, -- O piece rotation 3

    {0,0}, {-1,0}, {2,0}, {1,0}, -- I piece rotation 0
    {1,0}, {1,-1}, {1,1}, {1,-2}, -- I piece rotation 1
    {0,-1}, {-1,-1}, {2,-1}, {1,-1}, -- I piece rotation 2
    {0,0}, {0,-1}, {0,1}, {0,-2}, -- I piece rotation 2

    {0,0}, {-1,0}, {1,1}, {0,1}, -- S piece rotation 0
    {0,0}, {0,1}, {1,0}, {1,-1}, -- S piece rotation 1
    {0,0}, {-1,-1}, {1,0}, {0,-1}, -- S piece rotation 2
    {0,0}, {-1,1}, {-1,0}, {0,-1}, -- S piece rotation 3

    {0,0}, {0,1}, {-1,1}, {1,0}, -- Z piece rotation 0
    {0,0}, {1,1}, {0,-1}, {1,0}, -- Z piece rotation 1
    {0,0}, {0,-1}, {-1,0}, {1,-1}, -- Z piece rotation 2
    {0,0}, {0,1}, {-1,-1}, {-1,0}, -- Z piece rotation 3

    {0,0}, {-1,0}, {1,1}, {1,0}, -- L piece rotation 0
    {0,0}, {0,-1}, {0,1}, {1,-1}, -- L piece rotation 1
    {0,0}, {-1,0}, {-1,-1}, {1,0}, -- L piece rotation 2
    {0,0}, {0,-1}, {0,1}, {-1,1}, -- L piece rotation 3

    {0,0}, {-1,0}, {-1,1}, {1,0}, -- J piece rotation 0
    {0,0}, {0,-1}, {0,1}, {1,1}, -- J piece rotation 1
    {0,0}, {-1,0}, {1,-1}, {1,0}, -- J piece rotation 2
    {0,0}, {0,-1}, {0,1}, {-1,-1}, -- J piece rotation 3

    {0,0}, {-1,0}, {0,1}, {1,0}, -- T piece rotation 0
    {0,0}, {0,-1}, {0,1}, {1,0}, -- T piece rotation 1
    {0,0}, {-1,0}, {0,-1}, {1,0}, -- T piece rotation 2
    {0,0}, {-1,0}, {0,1}, {0,-1}, -- T piece rotation 3
}
local piece_ID_reference =
{
    [0] =
    {0, 4}, -- O piece
    {16, 4}, -- I piece
    {32, 4}, -- S piece
    {48, 4}, -- Z piece
    {64, 4}, -- L piece
    {80, 4}, -- J piece
    {96, 4}, -- T piece
}
function beep(frequency, seconds)
  if beep_available then 
    component.beep.beep({[frequency] = seconds})
  end
end
function spawnPiece(int)
  mino_index, minos = piece_ID_reference[int][1], piece_ID_reference[int][2]
  rotation_index = 0
  texture_ID = int + 1
  pieces = pieces + 1
  if level%100 < 99 then
    level = level + 1
  end
  if pieces % 7 == 1 then
    putNewPiecesIntoBag()
  end
  renderBag()
  gpu.setForeground(0xFFFFFF)
  piece_pos = {x = 5, y = 21}
  lock_ticks = 0
  spawn_ticks = 0
  is_spawned = true
  is_ground = false
end
function directMovePiece(x,y)
  piece_pos.x = piece_pos.x + x
  piece_pos.y = piece_pos.y + y
end
function checkCollision(x,y)
  if x < 1 or x > 10 then return true end
  if y < 0 or y > 39 then return true end
  return board[y*10+x] > 0
end
function putNewPiecesIntoBag()
  local new_bag = {0, 1, 2, 3, 4, 5, 6}
  for i = 1, 7 do
    local x = math.random(#new_bag)
    table.insert(bag, table.remove(new_bag, x))
  end
end
function checkPieceCollision(px,py)
  for i = 1, minos do
    local mino = piece_blob_storage[mino_index + i - 1]
    if checkCollision(mino[1] + piece_pos.x + px, mino[2] + piece_pos.y + py) then
      --print("collision at: x:"..mino[1] + piece_pos.x + px.. " y:"..mino[2] + piece_pos.y + py)
      return false
    end
  end
  return true
end
function movePiece(x,y)
  if checkPieceCollision(x,y) then
    directMovePiece(x,y)
    is_ground = false
    lock_ticks = 0
    return true
  end
  return false
end
function getPieceMino(int)
  local mino = piece_blob_storage[mino_index + int-1]
  return (mino[2] + piece_pos.y) * 10 + (mino[1] + piece_pos.x)
end
function formatTime(frames)
  -- returns a mm:ss:hh (h=hundredths) representation of the time in frames given 
  if frames < 0 then return formatTime(0) end
  local min, sec, hund
  min  = math.floor(frames/3600)
  sec  = math.floor(frames/60) % 60
  hund = math.floor(frames/.06) % 1000
  str = string.format("%02d:%02d.%03d", min, sec, hund)
  return str
end
function draw()
  for y = 0, 39 do
    for x = 1, 10 do
      prev_render_board[y*10+x] = render_board[y*10+x]
      local board_str = "  "
      if board[y*10+x] > 0 then board_str = block_design end
      render_board[y*10+x] = board_str
      if prev_render_board[y*10+x] ~= render_board[y*10+x] then
        renderBlock(x,y)
      end
    end
  end
  if is_spawned then
    for i = 1, minos do
      local mino = piece_blob_storage[mino_index + i - 1]
      render_board[getPieceMino(i)] = 0
      renderBlock(mino[1] + piece_pos.x, mino[2] + piece_pos.y, block_design, texture_ID, lock_ticks / lock_delay)
    end 
  end
  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(0)
  gpu.fill(w/2+11, h/2, 20, h/2, " ")
  gpu.set(w/2+11, h/2, "Time: "..formatTime(time_frame))
  gpu.set(w/2+11, h/2+1, "Lock:")
  gpu.set(w/2+11, h/2+2, math.max(frameToMilli(lock_delay-lock_ticks), 0).."/"..frameToMilli(lock_delay).."ms")
  gpu.set(w/2+11, h/2+3, string.sub("PPS: "..getPPS(), 1, 10))
  gpu.set(w/2+11, h/2+4, "Lines: "..line_count)
  gpu.set(w/2+11, h/2+5, "Level: "..level)
end
function renderBag(max)
  gpu.fill(w/2+11, 0, 20, h/2, " ")
  for i = 1, 5 do
    local x, y = 13, 25 - i * 3
    local refs = piece_ID_reference[bag[i]]
    local mino_index, minos = refs[1], refs[2]
    for j = 1, minos do
      local mino = piece_blob_storage[mino_index + j - 1]
      renderBlock(x + mino[1], y + mino[2], block_design, bag[i]+1)
    end
  end
end
function checkAndClearLines()
  local clear_count = 0
  for y = 39, 0, -1 do
    local full_line = true
    local transformedY = y * 10
    -- Checking if a single mino is empty on a line.
    for i = 1, 10 do
      if board[i + transformedY] <= 0 then
        full_line = false
        break
      end
    end
    if full_line then
      is_cleared = true
      table.insert(full_lines, y)
      line_count = line_count + 1
      clear_count = clear_count + 1
      -- Line clearing
      for i = 1, 10 do
        board[transformedY + i] = 0
      end
    end
  end
  level = level + ({[0]= 0, 1, 2, 4, 6})[clear_count]
  if is_cleared then
    beep(300, 0.1)
  end
end
function blockOut()
  os.sleep(0.3)
  if gpu.maxDepth() > 1 then gpu.setBackground(0x7F7F7F) end
  for i = 0, 21 do
    os.sleep(0.03)
    gpu.fill(w/2-10, (h/2+7)-i,20, 1, " ")
  end
  gpu.set(w/2-9,h/2-9,"Blocked out!")
  gpu.set(w/2-9,h/2-8,"Lines: "..line_count)
  in_menu = true
  changeMenu(0)
  das = prev_das
  arr = prev_arr
  beep(360,0.3)
end
function lockPiece()
  beep(100,0.1)
  for i = 1, minos do
    if board[getPieceMino(i)] > 0 then
      blockOut()
      return
    end
    board[getPieceMino(i)] = texture_ID
  end
  checkAndClearLines()
  piece_latencies[#piece_latencies + 1] = time_frame - last_piece_time
  if #piece_latencies >= 25 then
    table.remove(piece_latencies, 1)
  end
  last_piece_time = time_frame
  is_spawned = false
end
local jlstz_offset_matrix = {
[0]={0, 0}, {0, 0}, {0, 0}, {0, 0},
    {0, 0}, {1,0}, {0, 0}, {-1, 0},
    {0, 0}, {1, -1}, {0, 0}, {-1, -1},
    {0, 0}, {0, 2}, {0, 0}, {0, 2},
    {0, 0}, {1, 2}, {0, 0}, {-1, 2} 
}
local i_offset_matrix = {
[0]={0, 0}, {0, 0}, {0, 0}, {0, 0},
    {0, 0}, {2, 0}, {3, 0}, {-1,0},
    {2, 0}, {-1,0}, {1, 0}, {0, 0},
    {-1,0}, {1, 1}, {2,-1}, {0,-2},
    {2, 0}, {0,-2}, {-2,0}, {0, 2},
}
function rotatePiece(add_rot_index, max_rot_index)
  if not max_rot_index then max_rot_index = 4 end --why does it have to be like this???
  local old_rot_index = rotation_index
  rotation_index = rotation_index + add_rot_index
  if rotation_index > max_rot_index - 1 then
    rotation_index = rotation_index - max_rot_index
  end
  if rotation_index < 0 then
    rotation_index = rotation_index + max_rot_index
  end
  local cur_offset_data = jlstz_offset_matrix
  if texture_ID == 2 then
    cur_offset_data = i_offset_matrix
  end
  mino_index = mino_index + (rotation_index - old_rot_index) * 4
  local offset_val1, offset_val2, end_offset = {x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}
  local blobIndexSize = #cur_offset_data / 4;
  local can_move = false
  for test_index = 0, blobIndexSize do
    offset_val1.x = cur_offset_data[old_rot_index + test_index * 4][1]
    offset_val1.y = cur_offset_data[old_rot_index + test_index * 4][2]
    offset_val2.x = cur_offset_data[rotation_index + test_index * 4][1]
    offset_val2.y = cur_offset_data[rotation_index + test_index * 4][2]
    end_offset.x = offset_val1.x - offset_val2.x
    end_offset.y = offset_val1.y - offset_val2.y
    if checkPieceCollision(end_offset.x, end_offset.y) then
      beep(440,0.05)
      can_move = true
      movePiece(end_offset.x, end_offset.y)
      is_ground = false
      break;
    end
  end
  if not can_move then
    mino_index = mino_index - (rotation_index - old_rot_index) * 4;
    rotation_index = old_rot_index;
  end
  return can_move
end
function holdPiece()
  if is_held then return end
  is_held = true
  if hold_ID > 0 then
    local temp = texture_ID
    texture_ID = hold_ID
    hold_ID = temp
    rotation_index = 0
    local mino = piece_ID_reference[texture_ID - 1]
    mino_index, minos = mino[1], mino[2]
    piece_pos = {x = 5, y = 21}
    is_ground = false
  else
    hold_ID = texture_ID
    spawnPiece(table.remove(bag, 1))
  end
  gpu.fill(w/2-20, 0, 8, h, " ")
  local x, y = -3, 22
  local refs = piece_ID_reference[hold_ID - 1]
  local mino_index, minos = refs[1], refs[2]
  for j = 1, minos do
    local mino = piece_blob_storage[mino_index + j - 1]
    renderBlock(x + mino[1], y + mino[2], block_design, hold_ID)
  end
end
function update(dt)
  lock_delay = getLockDelay()
  spawn_delay = getSpawnDelay()
  line_drop_delay = getLineDropDelay()
  line_spawn_delay = getLineSpawnDelay()
  das = getDAS()
  arr = 1
  local both_sides_pressed = (keyboard.isKeyDown(input_table[1]) and keyboard.isKeyDown(input_table[3]))
  if keyboard.isKeyDown(input_table[1]) and is_spawned and not both_sides_pressed then
    if das_l == 0 then
      if movePiece(-1, 0) then
      beep(400, 0.05) end
    end
    if das_l >= das - 1 and (das_l % arr < 1 or arr == 0) then
      if arr == 0 then
        while movePiece(-1, 0) do end --That seems like an infinite loop
      else
        if movePiece(-1, 0) then
        beep(400, 0.05) end
      end
    end
    das_l = das_l + dt
  elseif is_spawned then
    das_l = 0
  end  
  if keyboard.isKeyDown(input_table[3]) and is_spawned and not both_sides_pressed then
    if das_r == 0 then
      if movePiece(1, 0) then
      beep(400, 0.05) end
    end
    if das_r >= das - 1 and (das_r % arr < 1 or arr == 0) then
      if arr == 0 then
        while movePiece(1, 0) do end
      else
        if movePiece(1, 0) then
        beep(400, 0.05) end
      end
    end
    das_r = das_r + dt
  elseif is_spawned then
    das_r = 0
  end
  if is_spawned then
    if keyboard.isKeyDown(input_table[7]) and not prev_inputs.hold then
      holdPiece()
    end
    if (keyboard.isKeyDown(input_table[2]) and not prev_inputs.cw) or (keyboard.isKeyDown(input_table[6]) and not prev_inputs.cw2) then
      rotatePiece(1, 4)
    end
    if (keyboard.isKeyDown(input_table[5]) and not prev_inputs.ccw) or (keyboard.isKeyDown(input_table[8]) and not prev_inputs.ccw2) then
      rotatePiece(-1, 4)
    end
    if keyboard.isKeyDown(input_table[9]) and not prev_inputs.up then
      while movePiece(0, -1) do end --That seems like an infinite loop.
      beep(125,0.133)
      lock_ticks = lock_delay
    end
    if checkPieceCollision(0, 0) then
    elseif rotatePiece(1, 4) then
    elseif not rotatePiece(-1, 4) then
      lockPiece()
    end
  else
    if is_cleared then
      line_drop_ticks = line_drop_ticks + dt
      if line_drop_ticks >= line_drop_delay then
        for index, line in pairs(full_lines) do
          -- Matrix drop
          for i = line * 10 + 1, #board - 10 do
            board[i] = board[i+10]
          end
          for i = 391, 400 do
            board[i] = 0
          end
        end
        full_lines = {}
        is_cleared = false
        line_drop_ticks = 0
        beep(50,0.1)
        spawn_ticks = spawn_delay - line_spawn_delay
      end
      return
    end
    spawn_ticks = spawn_ticks + dt
    if spawn_ticks >= spawn_delay then
      is_held = false
      spawnPiece(table.remove(bag, 1))
      beep(700 + (texture_ID * 50),0.1)
    end
    return
  end
  if keyboard.isKeyDown(input_table[4]) then
    gravity_tiles = gravity_tiles + (getGravity() * sdf) * dt
  end
  gravity_tiles = gravity_tiles + getGravity() * dt
  while gravity_tiles > 1 do
    gravity_tiles = gravity_tiles - 1
    if movePiece(0, -1) then
      if keyboard.isKeyDown(input_table[4]) then beep(100,0.05) end
    else
      gravity_tiles = 0
    end
  end
  is_ground = not checkPieceCollision(0, -1)
  if is_ground then
    lock_ticks = lock_ticks + dt
  end
  if lock_ticks >= lock_delay and is_spawned then
    lockPiece()
  end
  prev_inputs["up"] = keyboard.isKeyDown(input_table[9])
  prev_inputs["cw"] = keyboard.isKeyDown(input_table[2])
  prev_inputs["ccw"] = keyboard.isKeyDown(input_table[5])
  prev_inputs["cw2"] = keyboard.isKeyDown(input_table[6])
  prev_inputs["ccw2"] = keyboard.isKeyDown(input_table[8])
  prev_inputs["hold"] = keyboard.isKeyDown(input_table[7])
end

function startGame()
  gpu.fill(1,1,w,h," ")
  initBoard()
  gpu.set(w/2-12, h/2+8, "Player: "..({event.pull("key_up")})[5])
  gpu.set(w/2-12, h/2+9, "TGM3 Shirase?")
  hold_ID = 0
  bag = {}
  prev_das = das
  prev_arr = arr
  putNewPiecesIntoBag()
  --spawnPiece(table.remove(bag, 1))
  rotation_index = 0
  piece_pos = {x = 5, y = 21}
  spawn_delay = getSpawnDelay()
  spawn_ticks = spawn_delay - 60
  line_spawn_delay = 6
  line_drop_ticks = 0
  line_drop_delay = 24
  lock_delay = 30
  lock_ticks = 0
  gravity = 0.1
  gravity_tiles = 0
  is_ground = false
  is_spawned = false
  is_cleared = false
  das_l, das_r = 0, 0
  pieces = 0
  line_count = 0
  level = 1
  time_frame = -60
  piece_latencies = {}
  last_piece_time = 0
  block_design = "██"
end

local menu_button_names =
{
  [0] =
  {
    "Play!",
    "Settings",
    "Quit",
  },
  {
    "Inputs",
    "DAS:",
    "ARR:",
    "SDF:",
    "Back",
  },
  {
    "CW:",
    "CCW:",
    "CW2:",
    "CCW2:",
    "Hold:",
    "Left:",
    "Up:",
    "Right:",
    "Down:",
    "Back",
  }
}
local input_indents = {3, 4, 4, 5, 5, 5, 3, 6, 5}
local input_pointers = {6, 1, 8, 9, 2, 3, 5, 4, 7}

function changeMenu(type, bool)
  local leftmost = w/2-10
  gpu.fill(leftmost, h/2-5, 19, #menu_button_names[menu_slice], " ")
  menu_slice = type
  menu_select = 1
  for i = 1, #menu_button_names[type] do
    gpu.set(leftmost+1, h/2-6 + i, menu_button_names[type][i])
  end
  gpu.set(leftmost, h/2-5, ">")
  gpu.set(leftmost, h/2+6, "Space: Select")
  gpu.set(leftmost, h/2+7, "LShift: Back")
  if bool then beep(550, 0.2) end
end
function rebindKey(id)
  gpu.set(w/2-10, h/2-8, "Press a key")
  input_table[id] = ({event.pull("key_down")})[4]
  gpu.fill(w/2-10, h/2-8, 11, 1, " ")
  changeMenu(2)
  drawAllInputKeys()
end
function loadData()
  ser=require"serialization"
  local file=io.open("save_data.oct","r")
  local text=file:read("*all")
  file:close()
  local tables={}
  while true do
    local a=text:find(";")
    if a then 
      tables[#tables+1]=ser.unserialize(text:sub(1,a-1))
      text=text:sub(a+1)
    else 
      break
    end
  end
  return tables
end
function saveData(input_table, tuning_table)
  ser=require"serialization"
  local f=io.open("save_data.oct","w")
  f:write(ser.serialize(input_table)..";"..ser.serialize(tuning_table)..";")
  f:close()
end
function drawAllInputKeys()
  for i = 1, 9 do
    drawInputKey(i, input_indents[input_pointers[i]])
  end
end
function drawInputKey(id, indent)
  gpu.set(w/2-8+indent, h/2-6+input_pointers[id], keyboard.keys[input_table[id]])
end
--Interactions here are likely hard-coded.
function menuUpdate()
  if keyboard.isKeyDown(menu_inputs[5]) and not prev_inputs.ccw then
    if menu_slice == 0 then
      if menu_select == 1 then
        in_menu = false
        startGame()
      elseif menu_select == 2 then
        changeMenu(1, true)
        gpu.set(w/2-3, h/2-4, das.."")
        gpu.set(w/2-3, h/2-3, arr.."")
        gpu.set(w/2-3, h/2-2, sdf.."")
      elseif menu_select == 3 then
        running = false
        saveData(input_table, {das, arr, sdf})
        require("tty").clear()
      end
    elseif menu_slice == 1 then
      if menu_select == 1 then
        changeMenu(2, true)
        drawAllInputKeys()
      else
      changeMenu(0, true) end
    else
      if menu_select == 1 then rebindKey(2) end
      if menu_select == 2 then rebindKey(5) end
      if menu_select == 3 then rebindKey(6) end
      if menu_select == 4 then rebindKey(8) end
      if menu_select == 5 then rebindKey(7) end
      if menu_select == 6 then rebindKey(1) end
      if menu_select == 7 then rebindKey(9) end
      if menu_select == 8 then rebindKey(3) end
      if menu_select == 9 then rebindKey(4) end
      if menu_select == 10 then
        changeMenu(1, true)
        gpu.set(w/2-3, h/2-4, das.."")
        gpu.set(w/2-3, h/2-3, arr.."")
        gpu.set(w/2-3, h/2-2, sdf.."")
      end
    end
  end
  if keyboard.isKeyDown(menu_inputs[2]) and not prev_inputs.up then
    beep(440,0.1)
    gpu.set(w/2-10, h/2-6 + menu_select, " ")
    menu_select = menu_select - 1
    if menu_select < 1 then menu_select = #menu_button_names[menu_slice] end
    gpu.set(w/2-10, h/2-6 + menu_select, ">")
  end
  if keyboard.isKeyDown(menu_inputs[4]) and not prev_inputs.down then
    beep(440,0.1)
    gpu.set(w/2-10, h/2-6 + menu_select, " ")
    menu_select = menu_select + 1
    if menu_select > #menu_button_names[menu_slice] then menu_select = 1 end
    gpu.set(w/2-10, h/2-6 + menu_select, ">")
  end
  if menu_slice == 1 then
    if keyboard.isKeyDown(menu_inputs[1]) and not prev_inputs.left then
      if menu_select == 2 then das = das - 1 gpu.set(w/2-3, h/2-4, das.." ")
      elseif menu_select == 3 then arr = arr - 1 gpu.set(w/2-3, h/2-3, arr.." ")
      elseif menu_select == 4 then sdf = sdf - 1 gpu.set(w/2-3, h/2-2, sdf.." ")
      end
    elseif keyboard.isKeyDown(menu_inputs[3]) and not prev_inputs.right then
      if menu_select == 2 then das = das + 1 gpu.set(w/2-3, h/2-4, das.." ")
      elseif menu_select == 3 then arr = arr + 1 gpu.set(w/2-3, h/2-3, arr.." ")
      elseif menu_select == 4 then sdf = sdf + 1 gpu.set(w/2-3, h/2-2, sdf.." ")
      end
    end
  end
  prev_inputs.cw2 = keyboard.isKeyDown(menu_inputs[6])
  prev_inputs.ccw = keyboard.isKeyDown(menu_inputs[5])
  prev_inputs.left = keyboard.isKeyDown(menu_inputs[1])
  prev_inputs.up = keyboard.isKeyDown(menu_inputs[2]) or keyboard.isKeyDown(menu_inputs[6])
  prev_inputs.right = keyboard.isKeyDown(menu_inputs[3])
  prev_inputs.down = keyboard.isKeyDown(menu_inputs[4])
end

--Preinit menu
changeMenu(0)
local tables = loadData()
if tables then
  if tables[1] then input_table = tables[1] end
  if tables[2] then das, arr, sdf = tables[2][1], tables[2][2], tables[2][3] end
end

function processGame(deltatime)
  if not deltatime then deltatime = 1 end
  time_frame = time_frame + deltatime
  update(deltatime)
  draw()
  os.sleep(0)
end
--Game loop
while running do
  if in_menu then
    --You might be wondering why is there no draw method for the menu? It's because elements DO NOT clear once they have been drawn.
    menuUpdate()
    os.sleep(0)
  else
    local prev_time = os.clock()
    processGame(dt)
    dt = (os.clock() - prev_time) * 400
  end
end