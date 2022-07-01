--robot autobuild
local component = require("component")
local robot = component.robot
local os = require("os")
local args = require("shell").parse(...)
-- local direction. e.g. move(direction), suck(direction, amount)
-- 0 is down, 1 is up, 2 is back, 3 is forward

-- rotation
-- false is counterclockwise, true is clockwise
local function counting(time)
  local l = 0
  while l < time do
    io.write("\n"..tostring(time-l))
    l = l + 1
    local freq = 200*(5-(time-l))
    if freq < 100 then
      freq = 100
    end
    component.computer.beep(freq, 0.5)
    os.sleep(0.5)
  end
end

if #args < 1 then return nil end 

local i = 0
local j = tonumber(args[1])

while i<j do
io.write("\nIteration: "..i)
robot.drop(3,1)
robot.select(1)
robot.move(3)
robot.turn(false)
robot.move(3)
robot.turn(false)
robot.suck(3,1)
robot.turn(false)
robot.move(3)
robot.move(3)
robot.turn(true)
robot.suck(3,1)
robot.suck(3,1)
robot.suck(3,1)
robot.turn(true)
robot.turn(true)
robot.place(3)
robot.select(2)
robot.move(1)
robot.place(3)
robot.move(0)
robot.turn(false)
robot.move(3)
robot.turn(true)
robot.move(2)
robot.drop(3,1)

i = i + 1
if #args > 1 then counting(tonumber(args[2]))
elseif i<j then counting(5) end

end
robot.select(1)