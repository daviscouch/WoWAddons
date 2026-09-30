-- Tiny assertion helper shared by the addon tests
local T = { pass = 0, fail = 0 }
function T.ok(title, cond, detail)
  if cond then
    T.pass = T.pass + 1
    io.write("PASS " .. title .. "\n")
  else
    T.fail = T.fail + 1
    io.write("FAIL " .. title .. (detail and ("\n     -> " .. tostring(detail):gsub("\n", "\n        ")) or "") .. "\n")
  end
end
function T.done()
  io.write(string.format("\n%d passed, %d failed\n", T.pass, T.fail))
  os.exit(T.fail == 0 and 0 or 1)
end
return T
