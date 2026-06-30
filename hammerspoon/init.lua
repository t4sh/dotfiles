-- Minimal Hammerspoon helper: center the focused window at 1440x900.
-- Rectangle handles general window management; keep Hammerspoon narrow.

local targetWidth = 1440
local targetHeight = 900

local function centerFocusedWindowAtTargetSize()
  local win = hs.window.focusedWindow()
  if not win then return end

  local frame = win:screen():visibleFrame()
  local width = math.min(targetWidth, frame.w)
  local height = math.min(targetHeight, frame.h)
  local x = frame.x + ((frame.w - width) / 2)
  local y = frame.y + ((frame.h - height) / 2)

  win:setFrame(hs.geometry.rect(x, y, width, height), 0)
end

-- Hyper + C: center focused window at 1440x900 on the current monitor.
hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "c", centerFocusedWindowAtTargetSize)

local function reloadConfig(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end

hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

if hs.ipc then
  hs.ipc.cliInstall()
end
