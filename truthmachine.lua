local shell = require("shell")
local io = require("io")

local input = shell.parse(...)

if input == 0 then io.write("0")
else while true do io.write("1") end end