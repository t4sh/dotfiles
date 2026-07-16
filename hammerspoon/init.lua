-- Window management shortcuts migrated from Rectangle.

local almostMaximizeRatio = 0.9
local resizeStep = 30
local minimumWindowSize = 100
local titleBarHeight = 40
local dragThreshold = 8
local topEdgeThreshold = 8
local frameTolerance = 2

local windowStates = {}

local function copyFrame(frame)
  return {x = frame.x, y = frame.y, w = frame.w, h = frame.h}
end

local function framesMatch(left, right)
  if not left or not right then return false end

  return math.abs(left.x - right.x) <= frameTolerance
    and math.abs(left.y - right.y) <= frameTolerance
    and math.abs(left.w - right.w) <= frameTolerance
    and math.abs(left.h - right.h) <= frameTolerance
end

local function rounded(value)
  return math.floor(value + 0.5)
end

local function centeredFrame(screenFrame, width, height)
  width = math.min(width, screenFrame.w)
  height = math.min(height, screenFrame.h)

  return {
    x = rounded(screenFrame.x + ((screenFrame.w - width) / 2)),
    y = rounded(screenFrame.y + ((screenFrame.h - height) / 2)),
    w = width,
    h = height,
  }
end

local function almostMaximizeFrame(screen)
  local frame = screen:frame()
  return centeredFrame(
    frame,
    rounded(frame.w * almostMaximizeRatio),
    rounded(frame.h * almostMaximizeRatio)
  )
end

local function constrainedFrame(frame, screenFrame)
  local width = math.min(frame.w, screenFrame.w)
  local height = math.min(frame.h, screenFrame.h)
  local maxX = screenFrame.x + screenFrame.w - width
  local maxY = screenFrame.y + screenFrame.h - height

  return {
    x = math.max(screenFrame.x, math.min(frame.x, maxX)),
    y = math.max(screenFrame.y, math.min(frame.y, maxY)),
    w = width,
    h = height,
  }
end

local function stateForAction(win, restoreFrame)
  local id = win:id()
  if not id then return nil end

  local state = windowStates[id] or {}
  local currentFrame = win:frame()

  if restoreFrame then
    state.restoreFrame = copyFrame(restoreFrame)
  elseif not state.managedFrame or not framesMatch(currentFrame, state.managedFrame) then
    -- The window was moved or resized outside these shortcuts. Treat its
    -- current frame as the new Restore destination, matching Rectangle.
    state.restoreFrame = copyFrame(currentFrame)
  end

  windowStates[id] = state
  return state
end

local function applyFrame(win, frame, action, restoreFrame)
  if not win then return end

  local state = stateForAction(win, restoreFrame)
  win:setFrame(frame, 0)

  if state then
    -- Read the frame back because some apps enforce their own size increments.
    state.managedFrame = copyFrame(win:frame())
    state.action = action
  end
end

local function focusedWindow()
  return hs.window.focusedWindow()
end

local function almostMaximize(win, screen, restoreFrame)
  win = win or focusedWindow()
  if not win then return end

  screen = screen or win:screen()
  applyFrame(win, almostMaximizeFrame(screen), "almostMaximize", restoreFrame)
end

local function maximizeFocusedWindow()
  local win = focusedWindow()
  if not win then return end

  applyFrame(win, copyFrame(win:screen():frame()), "maximize")
end

local function centerFocusedWindowAtCurrentSize()
  local win = focusedWindow()
  if not win then return end

  local frame = win:frame()
  applyFrame(
    win,
    centeredFrame(win:screen():frame(), frame.w, frame.h),
    "center"
  )
end

local function resizeFocusedWindow(delta)
  local win = focusedWindow()
  if not win then return end

  local current = win:frame()
  local screenFrame = win:screen():frame()
  local width = math.max(minimumWindowSize, math.min(current.w + delta, screenFrame.w))
  local height = math.max(minimumWindowSize, math.min(current.h + delta, screenFrame.h))
  local resized = {
    x = current.x - ((width - current.w) / 2),
    y = current.y - ((height - current.h) / 2),
    w = width,
    h = height,
  }

  applyFrame(
    win,
    constrainedFrame(resized, screenFrame),
    delta > 0 and "larger" or "smaller"
  )
end

local function restoreFocusedWindow()
  local win = focusedWindow()
  if not win then return end

  local id = win:id()
  local state = id and windowStates[id] or nil
  if not state or not state.restoreFrame then return end

  win:setFrame(state.restoreFrame, 0)
  state.managedFrame = nil
  state.action = nil
end

local function moveFocusedWindowToDisplay(direction)
  local win = focusedWindow()
  if not win then return end

  local destination = direction == "next"
    and win:screen():next()
    or win:screen():previous()
  if not destination or destination == win:screen() then return end

  local state = stateForAction(win)
  local destinationFrame = destination:frame()
  local targetFrame
  local action = direction .. "Display"

  if state and state.action == "maximize" then
    targetFrame = copyFrame(destinationFrame)
    action = "maximize"
  else
    local current = win:frame()
    targetFrame = centeredFrame(destinationFrame, current.w, current.h)
  end

  applyFrame(win, targetFrame, action)
end

-- Keep hotkey objects alive for the lifetime of the Hammerspoon config.
windowHotkeys = {
  hs.hotkey.bind({"ctrl", "alt"}, "return", almostMaximize),
  hs.hotkey.bind({"ctrl", "alt", "shift"}, "return", maximizeFocusedWindow),
  hs.hotkey.bind({"ctrl", "alt"}, "delete", restoreFocusedWindow),
  hs.hotkey.bind({"ctrl", "alt"}, "c", centerFocusedWindowAtCurrentSize),
  hs.hotkey.bind({"ctrl", "alt"}, "-", function() resizeFocusedWindow(-resizeStep) end),
  hs.hotkey.bind({"ctrl", "alt"}, "=", function() resizeFocusedWindow(resizeStep) end),
  hs.hotkey.bind({"ctrl", "alt", "cmd"}, "right", function()
    moveFocusedWindowToDisplay("next")
  end),
  hs.hotkey.bind({"ctrl", "alt", "cmd"}, "left", function()
    moveFocusedWindowToDisplay("previous")
  end),
}

-- Existing Hyper + C helper: center at 1440x900 on the current monitor.
local function centerFocusedWindowAtTargetSize()
  local win = focusedWindow()
  if not win then return end

  applyFrame(win, centeredFrame(win:screen():frame(), 1440, 900), "center1440x900")
end

table.insert(windowHotkeys, hs.hotkey.bind(
  {"cmd", "alt", "ctrl", "shift"},
  "c",
  centerFocusedWindowAtTargetSize
))

local dragState = nil

-- Preview the exact Almost Maximize result while a title-bar drag is inside
-- the top-edge snap zone. Canvas elements do not consume mouse events unless
-- explicit mouse tracking is enabled, so the underlying drag remains native.
snapPreviewCanvas = hs.canvas.new({x = 0, y = 0, w = 1, h = 1})
  :level(hs.canvas.windowLevels.overlay)
  :behavior({
    hs.canvas.windowBehaviors.canJoinAllSpaces,
    hs.canvas.windowBehaviors.fullScreenAuxiliary,
    hs.canvas.windowBehaviors.transient,
  })

snapPreviewCanvas:appendElements(
  {
    type = "rectangle",
    action = "fill",
    fillColor = {red = 0.24, green = 0.58, blue = 0.95, alpha = 0.18},
    roundedRectRadii = {xRadius = 12, yRadius = 12},
  },
  {
    type = "rectangle",
    action = "stroke",
    strokeColor = {red = 0.35, green = 0.68, blue = 1.0, alpha = 0.7},
    strokeWidth = 2,
    roundedRectRadii = {xRadius = 12, yRadius = 12},
  }
)

local function hideSnapPreview()
  snapPreviewCanvas:hide()
end

local function showSnapPreview(screen)
  snapPreviewCanvas:frame(almostMaximizeFrame(screen)):show()
end

local function windowInTitleBarAt(point)
  for _, win in ipairs(hs.window.orderedWindows()) do
    local frame = win:frame()
    if win:isStandard()
      and point.x >= frame.x
      and point.x <= frame.x + frame.w
      and point.y >= frame.y
      and point.y <= frame.y + math.min(titleBarHeight, frame.h) then
      return win
    end
  end

  return nil
end

local function pointDistance(left, right)
  local dx = left.x - right.x
  local dy = left.y - right.y
  return math.sqrt((dx * dx) + (dy * dy))
end

local function isAtTopEdge(point, screen)
  if not screen then return false end

  local frame = screen:fullFrame()
  return point.x >= frame.x
    and point.x <= frame.x + frame.w
    and point.y <= frame.y + topEdgeThreshold
end

-- Rectangle replacement requested for mouse snapping: dragging a title bar to
-- the physical top edge of any display applies Almost Maximize. Other edges
-- and corners intentionally have no snap actions.
topEdgeSnapWatcher = hs.eventtap.new({
  hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.leftMouseDragged,
  hs.eventtap.event.types.leftMouseUp,
}, function(event)
  local eventType = event:getType()
  local point = event:location()

  if eventType == hs.eventtap.event.types.leftMouseDown then
    hideSnapPreview()
    local win = windowInTitleBarAt(point)
    dragState = win and {
      window = win,
      startPoint = point,
      startFrame = copyFrame(win:frame()),
      moved = false,
    } or nil
  elseif eventType == hs.eventtap.event.types.leftMouseDragged then
    if dragState and not dragState.moved then
      dragState.moved = pointDistance(point, dragState.startPoint) >= dragThreshold
    end

    if dragState and dragState.moved then
      local screen = hs.mouse.getCurrentScreen()
      if isAtTopEdge(point, screen) then
        showSnapPreview(screen)
      else
        hideSnapPreview()
      end
    end
  elseif eventType == hs.eventtap.event.types.leftMouseUp then
    local completedDrag = dragState
    dragState = nil
    hideSnapPreview()

    if completedDrag and completedDrag.moved then
      local screen = hs.mouse.getCurrentScreen()
      if isAtTopEdge(point, screen) then
        -- Let macOS finish its drag before replacing the final frame.
        hs.timer.doAfter(0.05, function()
          almostMaximize(completedDrag.window, screen, completedDrag.startFrame)
        end)
      end
    end
  end

  return false
end):start()

local function reloadConfig(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end

-- Hammerspoon stops watchers when their Lua objects are garbage-collected.
configFileWatcher = hs.pathwatcher.new(
  os.getenv("HOME") .. "/.hammerspoon/",
  reloadConfig
):start()

if hs.ipc then
  hs.ipc.cliInstall()
end
