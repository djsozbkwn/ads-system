local SUPABASE_URL = "https://kwlcycmqncfoxeurymlo.supabase.co"
local SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt3bGN5Y21xbmNmb3hldXJ5bWxvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3NjYzOTAsImV4cCI6MjA5MzM0MjM5MH0.d23vzj-OzLUqLVhLdC1pe-AMmBRpqPzczWFFObzc_74"
local POLL_INTERVAL = 2
local MAX_MESSAGES = 60
local DEFAULT_CHANNEL = "global"
local CHANNELS = { "global", "trade", "help" }
local W, H = 560, 310

local HttpService  = game:GetService("HttpService")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local localPlayer  = Players.LocalPlayer

local channelCache    = {}
local lastMessageTime = {}
local pollConn        = nil
local currentChannel  = DEFAULT_CHANNEL
local msgElements     = {}
local isMinimized     = false
local isDragging      = false
local dragStart, startPos
local appendMessage, appendSystem
local tabButtons = {}

local httpRequest = (syn and syn.request)
    or (http and http.request)
    or (request)
    or function(opts)
        local ok, res = pcall(function()
            return HttpService:RequestAsync({
                Url     = opts.Url,
                Method  = opts.Method,
                Headers = opts.Headers,
                Body    = opts.Body,
            })
        end)
        if ok then return res end
        return nil
    end

local function req(method, path, body)
    local opts = {
        Url     = SUPABASE_URL .. path,
        Method  = method,
        Headers = {
            ["Content-Type"]  = "application/json",
            ["apikey"]        = SUPABASE_KEY,
            ["Authorization"] = "Bearer " .. SUPABASE_KEY,
            ["Prefer"]        = "return=minimal",
        },
    }
    if body then
        opts.Body = HttpService:JSONEncode(body)
    end
    local ok, res = pcall(httpRequest, opts)
    if not ok or not res then return nil end
    if type(res) == "table" and res.Body and #res.Body > 0 then
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if ok2 then return data end
    end
    return true
end

local function getOrCreateChannel(name)
    if channelCache[name] then return channelCache[name] end
    local found = req("GET", "/rest/v1/channels?name=eq." .. name .. "&select=id")
    if type(found) == "table" and #found > 0 then
        channelCache[name] = found[1].id
        return found[1].id
    end
    req("POST", "/rest/v1/channels", { name = name })
    task.wait(0.3)
    local again = req("GET", "/rest/v1/channels?name=eq." .. name .. "&select=id")
    if type(again) == "table" and #again > 0 then
        channelCache[name] = again[1].id
        return again[1].id
    end
    return nil
end

local function sendMessage(chName, content)
    local id = getOrCreateChannel(chName)
    if not id then return end
    req("POST", "/rest/v1/messages", {
        channel_id  = id,
        player_name = localPlayer.Name,
        player_id   = tostring(localPlayer.UserId),
        content     = content,
    })
end

local function fetchNew(chId, chName)
    local path = "/rest/v1/messages?channel_id=eq." .. chId
        .. "&select=player_name,player_id,content,created_at"
        .. "&order=created_at.asc&limit=" .. MAX_MESSAGES
    if lastMessageTime[chName] then
        path = path .. "&created_at=gt." .. lastMessageTime[chName]
    end
    local msgs = req("GET", path)
    if type(msgs) ~= "table" or #msgs == 0 then return end
    lastMessageTime[chName] = msgs[#msgs].created_at
    for _, msg in ipairs(msgs) do
        if chName == currentChannel and appendMessage then
            local ts    = (msg.created_at or ""):sub(12, 19)
            local isSelf = tostring(msg.player_id) == tostring(localPlayer.UserId)
            appendMessage(msg.player_name, msg.content, ts, isSelf)
        end
    end
end

local function startPolling(chName)
    if pollConn then pollConn:Disconnect(); pollConn = nil end
    currentChannel = chName
    local chId = getOrCreateChannel(chName)
    if not chId then
        if appendSystem then appendSystem("ERR: channel '" .. chName .. "' not found") end
        return
    end
    if not lastMessageTime[chName] then
        lastMessageTime[chName] = os.date("!%Y-%m-%dT%H:%M:%SZ")
    end
    local elapsed = 0
    pollConn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if elapsed < POLL_INTERVAL then return end
        elapsed = 0
        task.spawn(fetchNew, chId, chName)
    end)
    if appendSystem then appendSystem("Switched to #" .. chName) end
end

local C = {
    BG      = Color3.fromRGB(11, 11, 17),
    PANEL   = Color3.fromRGB(17, 17, 27),
    HEADER  = Color3.fromRGB(20, 20, 33),
    ACCENT  = Color3.fromRGB(99, 179, 237),
    ACCENT2 = Color3.fromRGB(252, 129, 74),
    TEXT    = Color3.fromRGB(220, 220, 235),
    SUB     = Color3.fromRGB(110, 110, 145),
    INBG    = Color3.fromRGB(23, 23, 38),
    TBON    = Color3.fromRGB(28, 28, 48),
    TBOFF   = Color3.fromRGB(14, 14, 22),
    BORDER  = Color3.fromRGB(38, 38, 62),
    SYS     = Color3.fromRGB(252, 129, 74),
}

local function corner(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = f
end

local function newFrame(parent, props)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do f[k] = v end
    f.Parent = parent
    return f
end

local function newText(cls, parent, props)
    local t = Instance.new(cls)
    t.BorderSizePixel = 0
    t.BackgroundTransparency = 1
    for k, v in pairs(props or {}) do t[k] = v end
    t.Parent = parent
    return t
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name          = "UniversalChat"
screenGui.ResetOnSpawn  = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent        = localPlayer:WaitForChild("PlayerGui")

local main = newFrame(screenGui, {
    Size            = UDim2.new(0, W, 0, H),
    Position        = UDim2.new(0.5, -W/2, 1, -H - 60),
    BackgroundColor3 = C.BG,
})
corner(main, 10)
do
    local s = Instance.new("UIStroke")
    s.Color = C.BORDER; s.Thickness = 1; s.Parent = main
end

local header = newFrame(main, {
    Size            = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = C.HEADER,
    ZIndex          = 3,
})
corner(header, 10)
newFrame(header, {
    Size            = UDim2.new(1, 0, 0, 10),
    Position        = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = C.HEADER,
    ZIndex          = 3,
})

local function dot(x, col)
    local d = newFrame(header, {
        Size            = UDim2.new(0, 10, 0, 10),
        Position        = UDim2.new(0, x, 0.5, -5),
        BackgroundColor3 = col,
        ZIndex          = 4,
    })
    corner(d, 5)
end
dot(12, Color3.fromRGB(255, 95, 87))
dot(28, Color3.fromRGB(255, 189, 46))
dot(44, Color3.fromRGB(40, 200, 64))

local headerLbl = newText("TextLabel", header, {
    Size             = UDim2.new(1, 0, 1, 0),
    Text             = "â—ˆ  UNIVERSAL CHAT  Â·  #" .. DEFAULT_CHANNEL:upper(),
    TextColor3       = C.ACCENT,
    TextSize         = 12,
    Font             = Enum.Font.GothamBold,
    TextXAlignment   = Enum.TextXAlignment.Center,
    ZIndex           = 4,
})

local minBtn = newText("TextButton", header, {
    Size            = UDim2.new(0, 26, 0, 22),
    Position        = UDim2.new(1, -30, 0.5, -11),
    BackgroundColor3 = C.TBON,
    BackgroundTransparency = 0,
    Text            = "â€”",
    TextColor3      = C.SUB,
    TextSize        = 11,
    Font            = Enum.Font.GothamBold,
    ZIndex          = 5,
})
corner(minBtn, 4)

local tabBar = newFrame(main, {
    Size            = UDim2.new(1, 0, 0, 30),
    Position        = UDim2.new(0, 0, 0, 36),
    BackgroundColor3 = C.PANEL,
})
do
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, 4)
    l.Parent = tabBar
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, 6)
    p.PaddingTop = UDim.new(0, 5)
    p.PaddingBottom = UDim.new(0, 5)
    p.Parent = tabBar
end

local chatArea = newFrame(main, {
    Size             = UDim2.new(1, 0, 1, -112),
    Position         = UDim2.new(0, 0, 0, 66),
    BackgroundColor3  = C.BG,
    ClipsDescendants = true,
})

local scroll = Instance.new("ScrollingFrame")
scroll.Size                = UDim2.new(1, -6, 1, -6)
scroll.Position            = UDim2.new(0, 3, 0, 3)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness  = 3
scroll.ScrollBarImageColor3 = C.ACCENT
scroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollingDirection  = Enum.ScrollingDirection.Y
scroll.Parent              = chatArea
do
    local l = Instance.new("UIListLayout")
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, 1)
    l.Parent = scroll
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8)
    p.PaddingTop = UDim.new(0, 4);  p.PaddingBottom = UDim.new(0, 4)
    p.Parent = scroll
end

newFrame(main, {
    Size            = UDim2.new(1, 0, 0, 1),
    Position        = UDim2.new(0, 0, 1, -46),
    BackgroundColor3 = C.BORDER,
})

local inputArea = newFrame(main, {
    Size            = UDim2.new(1, 0, 0, 46),
    Position        = UDim2.new(0, 0, 1, -46),
    BackgroundColor3 = C.PANEL,
})
corner(inputArea, 10)
newFrame(inputArea, {
    Size            = UDim2.new(1, 0, 0, 10),
    BackgroundColor3 = C.PANEL,
})

local inputFrame = newFrame(inputArea, {
    Size            = UDim2.new(1, -14, 0, 30),
    Position        = UDim2.new(0, 7, 0, 8),
    BackgroundColor3 = C.INBG,
})
corner(inputFrame, 5)
do
    local s = Instance.new("UIStroke")
    s.Color = C.BORDER; s.Thickness = 1; s.Parent = inputFrame
end

local inputBox = newText("TextBox", inputFrame, {
    Size              = UDim2.new(1, -76, 1, 0),
    Position          = UDim2.new(0, 10, 0, 0),
    Text              = "",
    PlaceholderText   = "Message #" .. DEFAULT_CHANNEL .. "...",
    TextColor3        = C.TEXT,
    PlaceholderColor3 = C.SUB,
    TextSize          = 12,
    Font              = Enum.Font.Gotham,
    TextXAlignment    = Enum.TextXAlignment.Left,
    ClearTextOnFocus  = false,
    BackgroundTransparency = 0,
    BackgroundColor3  = C.INBG,
})

local sendBtn = newText("TextButton", inputFrame, {
    Size            = UDim2.new(0, 58, 0, 22),
    Position        = UDim2.new(1, -64, 0.5, -11),
    BackgroundColor3 = C.ACCENT,
    BackgroundTransparency = 0,
    Text            = "SEND",
    TextColor3      = Color3.fromRGB(8, 8, 18),
    TextSize        = 11,
    Font            = Enum.Font.GothamBold,
})
corner(sendBtn, 4)

local function setActiveTab(ch)
    currentChannel = ch
    headerLbl.Text = "â—ˆ  UNIVERSAL CHAT  Â·  #" .. ch:upper()
    inputBox.PlaceholderText = "Message #" .. ch .. "..."
    for name, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = name == ch and C.TBON or C.TBOFF
        btn.TextColor3       = name == ch and C.ACCENT or C.SUB
    end
    task.spawn(startPolling, ch)
end

local function addTab(ch, order)
    local btn = newText("TextButton", tabBar, {
        Size            = UDim2.new(0, 72, 1, 0),
        BackgroundColor3 = ch == DEFAULT_CHANNEL and C.TBON or C.TBOFF,
        BackgroundTransparency = 0,
        Text            = "#" .. ch,
        TextColor3      = ch == DEFAULT_CHANNEL and C.ACCENT or C.SUB,
        TextSize        = 11,
        Font            = Enum.Font.GothamBold,
        LayoutOrder     = order,
    })
    corner(btn, 4)
    tabButtons[ch] = btn
    btn.MouseButton1Click:Connect(function() setActiveTab(ch) end)
end

for i, ch in ipairs(CHANNELS) do addTab(ch, i) end

local addChBtn = newText("TextButton", tabBar, {
    Size            = UDim2.new(0, 24, 1, 0),
    BackgroundColor3 = C.TBOFF,
    BackgroundTransparency = 0,
    Text            = "+",
    TextColor3      = C.SUB,
    TextSize        = 15,
    Font            = Enum.Font.GothamBold,
    LayoutOrder     = 99,
})
corner(addChBtn, 4)

appendMessage = function(name, content, ts, isSelf)
    local row = newFrame(scroll, {
        Size            = UDim2.new(1, 0, 0, 0),
        AutomaticSize   = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.BG,
        BackgroundTransparency = 1,
        LayoutOrder     = #msgElements + 1,
    })
    newText("TextLabel", row, {
        Size           = UDim2.new(0, 42, 0, 16),
        Position       = UDim2.new(0, 0, 0, 1),
        Text           = ts,
        TextColor3     = C.SUB,
        TextSize       = 10,
        Font           = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    newText("TextLabel", row, {
        Size           = UDim2.new(0, 120, 0, 16),
        Position       = UDim2.new(0, 46, 0, 1),
        Text           = name,
        TextColor3     = isSelf and C.ACCENT or C.ACCENT2,
        TextSize       = 11,
        Font           = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate   = Enum.TextTruncate.AtEnd,
    })
    newText("TextLabel", row, {
        Size           = UDim2.new(1, -8, 0, 0),
        Position       = UDim2.new(0, 4, 0, 17),
        AutomaticSize  = Enum.AutomaticSize.Y,
        Text           = content,
        TextColor3     = isSelf and Color3.fromRGB(170, 210, 240) or C.TEXT,
        TextSize       = 12,
        Font           = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped    = true,
    })
    table.insert(msgElements, row)
    if #msgElements > MAX_MESSAGES then
        table.remove(msgElements, 1):Destroy()
    end
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

appendSystem = function(msg)
    local row = newFrame(scroll, {
        Size          = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder   = #msgElements + 1,
    })
    newText("TextLabel", row, {
        Size           = UDim2.new(1, 0, 1, 0),
        Text           = "â—† " .. msg,
        TextColor3     = C.SYS,
        TextSize       = 10,
        Font           = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    table.insert(msgElements, row)
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

local function doSend()
    local txt = inputBox.Text
    if not txt or txt:gsub("%s+", "") == "" then return end
    inputBox.Text = ""
    local ch, body = txt:match("^/(%a+)%s+(.+)$")
    if ch and body then
        task.spawn(sendMessage, ch:lower(), body)
    else
        task.spawn(sendMessage, currentChannel, txt)
    end
end

sendBtn.MouseButton1Click:Connect(doSend)
inputBox.FocusLost:Connect(function(enter) if enter then doSend() end end)

addChBtn.MouseButton1Click:Connect(function()
    inputBox:CaptureFocus()
    inputBox.PlaceholderText = "New channel name, press Enter..."
    local conn
    conn = inputBox.FocusLost:Connect(function(enter)
        conn:Disconnect()
        local newCh = inputBox.Text:lower():gsub("%s+", "")
        inputBox.Text = ""
        inputBox.PlaceholderText = "Message #" .. currentChannel .. "..."
        if enter and newCh ~= "" and not tabButtons[newCh] then
            table.insert(CHANNELS, newCh)
            addTab(newCh, #CHANNELS)
            setActiveTab(newCh)
        end
    end)
end)

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    chatArea.Visible  = not isMinimized
    tabBar.Visible    = not isMinimized
    inputArea.Visible = not isMinimized
    TweenService:Create(main, TweenInfo.new(0.18), {
        Size = isMinimized and UDim2.new(0, W, 0, 36) or UDim2.new(0, W, 0, H)
    }):Play()
    minBtn.Text = isMinimized and "â–¡" or "â€”"
end)

header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        isDragging = true
        dragStart  = i.Position
        startPos   = main.Position
    end
end)
header.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        isDragging = false
    end
end)
UIS.InputChanged:Connect(function(i)
    if isDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

appendSystem("Universal Chat loaded")
appendSystem("SEND or Enter to chat  |  /channel msg for other channels")

task.spawn(startPolling, DEFAULT_CHANNEL)
