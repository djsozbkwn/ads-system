local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SUPABASE_URL = "https://kwlcycmqncfoxeurymlo.supabase.co"
local SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt3bGN5Y21xbmNmb3hldXJ5bWxvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3NjYzOTAsImV4cCI6MjA5MzM0MjM5MH0.d23vzj-OzLUqLVhLdC1pe-AMmBRpqPzczWFFObzc_74"

local POLL_INTERVAL = 2
local MAX_MESSAGES = 60
local DEFAULT_CHANNEL = "global"
local CHANNELS = {"global", "trade", "help"}

local W, H = 560, 310

local localPlayer = Players.LocalPlayer
local channelCache = {}
local lastMessageTime = {}
local pollConnection = nil
local currentChannel = DEFAULT_CHANNEL
local messageElements = {}
local isMinimized = false
local isDragging = false
local dragStart, startPos

local C = {
	BG       = Color3.fromRGB(11, 11, 17),
	PANEL    = Color3.fromRGB(17, 17, 27),
	HEADER   = Color3.fromRGB(20, 20, 33),
	ACCENT   = Color3.fromRGB(99, 179, 237),
	ACCENT2  = Color3.fromRGB(252, 129, 74),
	TEXT     = Color3.fromRGB(220, 220, 235),
	SUBTEXT  = Color3.fromRGB(110, 110, 145),
	INPUT_BG = Color3.fromRGB(23, 23, 38),
	TAB_ON   = Color3.fromRGB(28, 28, 48),
	TAB_OFF  = Color3.fromRGB(14, 14, 22),
	BORDER   = Color3.fromRGB(38, 38, 62),
	SYS      = Color3.fromRGB(252, 129, 74),
}

local function buildHeaders()
	return {
		["Content-Type"] = "application/json",
		["apikey"] = SUPABASE_KEY,
		["Authorization"] = "Bearer " .. SUPABASE_KEY,
		["Prefer"] = "return=minimal",
	}
end

local function request(method, path, body)
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = SUPABASE_URL .. path,
		Method = method,
		Headers = buildHeaders(),
		Body = body and HttpService:JSONEncode(body) or nil,
	})
	if not ok or not res or not res.Success then return nil end
	if res.Body and #res.Body > 0 then
		local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
		if ok2 then return data end
	end
	return true
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = inst
end

local function stroke(inst, col, thick)
	local s = Instance.new("UIStroke")
	s.Color = col or C.BORDER
	s.Thickness = thick or 1
	s.Parent = inst
end

local function getOrCreateChannel(name)
	if channelCache[name] then return channelCache[name] end
	local found = request("GET", "/rest/v1/channels?name=eq." .. name .. "&select=id")
	if found and #found > 0 then channelCache[name] = found[1].id; return found[1].id end
	request("POST", "/rest/v1/channels", { name = name })
	local refetch = request("GET", "/rest/v1/channels?name=eq." .. name .. "&select=id")
	if refetch and #refetch > 0 then channelCache[name] = refetch[1].id; return refetch[1].id end
	return nil
end

local sendMessage
local appendMessage, appendSystem

local screenGui, mainFrame, chatScroll, inputBox, headerLabel, minimizeBtn
local tabButtons = {}

local function buildGUI()
	if screenGui then screenGui:Destroy() end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UniversalChat"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = localPlayer.PlayerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(0, W, 0, H)
	mainFrame.Position = UDim2.new(0.5, -W/2, 1, -H - 60)
	mainFrame.BackgroundColor3 = C.BG
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	corner(mainFrame, 10)
	stroke(mainFrame, C.BORDER, 1)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = C.HEADER
	header.BorderSizePixel = 0
	header.ZIndex = 3
	header.Parent = mainFrame
	corner(header, 10)

	local headerSquare = Instance.new("Frame")
	headerSquare.Size = UDim2.new(1, 0, 0, 10)
	headerSquare.Position = UDim2.new(0, 0, 1, -10)
	headerSquare.BackgroundColor3 = C.HEADER
	headerSquare.BorderSizePixel = 0
	headerSquare.ZIndex = 3
	headerSquare.Parent = header

	local function macDot(xOff, col)
		local d = Instance.new("Frame")
		d.Size = UDim2.new(0, 10, 0, 10)
		d.Position = UDim2.new(0, xOff, 0.5, -5)
		d.BackgroundColor3 = col
		d.BorderSizePixel = 0
		d.ZIndex = 4
		d.Parent = header
		corner(d, 5)
	end
	macDot(12, Color3.fromRGB(255, 95, 87))
	macDot(28, Color3.fromRGB(255, 189, 46))
	macDot(44, Color3.fromRGB(40, 200, 64))

	headerLabel = Instance.new("TextLabel")
	headerLabel.Size = UDim2.new(1, 0, 1, 0)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = "◈ UNIVERSAL CHAT  ·  #" .. DEFAULT_CHANNEL:upper()
	headerLabel.TextColor3 = C.ACCENT
	headerLabel.TextSize = 12
	headerLabel.Font = Enum.Font.GothamBold
	headerLabel.TextXAlignment = Enum.TextXAlignment.Center
	headerLabel.ZIndex = 4
	headerLabel.Parent = header

	minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Size = UDim2.new(0, 26, 0, 22)
	minimizeBtn.Position = UDim2.new(1, -30, 0.5, -11)
	minimizeBtn.BackgroundColor3 = C.TAB_ON
	minimizeBtn.Text = "—"
	minimizeBtn.TextColor3 = C.SUBTEXT
	minimizeBtn.TextSize = 11
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.BorderSizePixel = 0
	minimizeBtn.ZIndex = 5
	minimizeBtn.Parent = header
	corner(minimizeBtn, 4)

	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, 30)
	tabBar.Position = UDim2.new(0, 0, 0, 36)
	tabBar.BackgroundColor3 = C.PANEL
	tabBar.BorderSizePixel = 0
	tabBar.Name = "tabBar"
	tabBar.Parent = mainFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabBar

	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingLeft = UDim.new(0, 6)
	tabPad.PaddingTop = UDim.new(0, 5)
	tabPad.PaddingBottom = UDim.new(0, 5)
	tabPad.Parent = tabBar

	local function setActiveTab(ch)
		currentChannel = ch
		headerLabel.Text = "◈ UNIVERSAL CHAT  ·  #" .. ch:upper()
		inputBox.PlaceholderText = "Message #" .. ch .. "..."
		for name, btn in pairs(tabButtons) do
			btn.BackgroundColor3 = name == ch and C.TAB_ON or C.TAB_OFF
			btn.TextColor3 = name == ch and C.ACCENT or C.SUBTEXT
		end
		task.spawn(function()
			local id = getOrCreateChannel(ch)
			if id then startPolling(ch) end
		end)
	end

	local function addTab(ch, order)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 72, 1, 0)
		btn.BackgroundColor3 = ch == DEFAULT_CHANNEL and C.TAB_ON or C.TAB_OFF
		btn.Text = "#" .. ch
		btn.TextColor3 = ch == DEFAULT_CHANNEL and C.ACCENT or C.SUBTEXT
		btn.TextSize = 11
		btn.Font = Enum.Font.GothamBold
		btn.BorderSizePixel = 0
		btn.LayoutOrder = order or #CHANNELS
		btn.Parent = tabBar
		corner(btn, 4)
		tabButtons[ch] = btn
		btn.MouseButton1Click:Connect(function() setActiveTab(ch) end)
		return btn
	end

	for i, ch in ipairs(CHANNELS) do addTab(ch, i) end

	local addBtn = Instance.new("TextButton")
	addBtn.Size = UDim2.new(0, 24, 1, 0)
	addBtn.BackgroundColor3 = C.TAB_OFF
	addBtn.Text = "+"
	addBtn.TextColor3 = C.SUBTEXT
	addBtn.TextSize = 15
	addBtn.Font = Enum.Font.GothamBold
	addBtn.BorderSizePixel = 0
	addBtn.LayoutOrder = 99
	addBtn.Parent = tabBar
	corner(addBtn, 4)

	local chatArea = Instance.new("Frame")
	chatArea.Size = UDim2.new(1, 0, 1, -112)
	chatArea.Position = UDim2.new(0, 0, 0, 66)
	chatArea.BackgroundColor3 = C.BG
	chatArea.BorderSizePixel = 0
	chatArea.ClipsDescendants = true
	chatArea.Name = "chatArea"
	chatArea.Parent = mainFrame

	chatScroll = Instance.new("ScrollingFrame")
	chatScroll.Size = UDim2.new(1, -6, 1, -6)
	chatScroll.Position = UDim2.new(0, 3, 0, 3)
	chatScroll.BackgroundTransparency = 1
	chatScroll.ScrollBarThickness = 3
	chatScroll.ScrollBarImageColor3 = C.ACCENT
	chatScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	chatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	chatScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	chatScroll.Parent = chatArea

	local msgLayout = Instance.new("UIListLayout")
	msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout.Padding = UDim.new(0, 1)
	msgLayout.Parent = chatScroll

	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingLeft = UDim.new(0, 8)
	msgPad.PaddingRight = UDim.new(0, 8)
	msgPad.PaddingTop = UDim.new(0, 4)
	msgPad.PaddingBottom = UDim.new(0, 4)
	msgPad.Parent = chatScroll

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.new(0, 0, 1, -46)
	divider.BackgroundColor3 = C.BORDER
	divider.BorderSizePixel = 0
	divider.Name = "divider"
	divider.Parent = mainFrame

	local inputArea = Instance.new("Frame")
	inputArea.Size = UDim2.new(1, 0, 0, 46)
	inputArea.Position = UDim2.new(0, 0, 1, -46)
	inputArea.BackgroundColor3 = C.PANEL
	inputArea.BorderSizePixel = 0
	inputArea.Name = "inputArea"
	inputArea.Parent = mainFrame
	corner(inputArea, 10)

	local inputFix = Instance.new("Frame")
	inputFix.Size = UDim2.new(1, 0, 0, 10)
	inputFix.BackgroundColor3 = C.PANEL
	inputFix.BorderSizePixel = 0
	inputFix.Parent = inputArea

	local inputFrame = Instance.new("Frame")
	inputFrame.Size = UDim2.new(1, -14, 0, 30)
	inputFrame.Position = UDim2.new(0, 7, 0, 8)
	inputFrame.BackgroundColor3 = C.INPUT_BG
	inputFrame.BorderSizePixel = 0
	inputFrame.Parent = inputArea
	corner(inputFrame, 5)
	stroke(inputFrame, C.BORDER, 1)

	inputBox = Instance.new("TextBox")
	inputBox.Size = UDim2.new(1, -76, 1, 0)
	inputBox.Position = UDim2.new(0, 10, 0, 0)
	inputBox.BackgroundTransparency = 1
	inputBox.Text = ""
	inputBox.PlaceholderText = "Message #" .. DEFAULT_CHANNEL .. "..."
	inputBox.TextColor3 = C.TEXT
	inputBox.PlaceholderColor3 = C.SUBTEXT
	inputBox.TextSize = 12
	inputBox.Font = Enum.Font.Gotham
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = inputFrame

	local sendBtn = Instance.new("TextButton")
	sendBtn.Size = UDim2.new(0, 58, 0, 22)
	sendBtn.Position = UDim2.new(1, -64, 0.5, -11)
	sendBtn.BackgroundColor3 = C.ACCENT
	sendBtn.Text = "SEND"
	sendBtn.TextColor3 = Color3.fromRGB(8, 8, 18)
	sendBtn.TextSize = 11
	sendBtn.Font = Enum.Font.GothamBold
	sendBtn.BorderSizePixel = 0
	sendBtn.Parent = inputFrame
	corner(sendBtn, 4)

	appendMessage = function(playerName, content, channel, timestamp, isSelf)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundTransparency = 1
		row.LayoutOrder = #messageElements + 1
		row.Parent = chatScroll

		local timeL = Instance.new("TextLabel")
		timeL.Size = UDim2.new(0, 42, 0, 16)
		timeL.Position = UDim2.new(0, 0, 0, 1)
		timeL.BackgroundTransparency = 1
		timeL.Text = timestamp
		timeL.TextColor3 = C.SUBTEXT
		timeL.TextSize = 10
		timeL.Font = Enum.Font.Gotham
		timeL.TextXAlignment = Enum.TextXAlignment.Left
		timeL.Parent = row

		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(0, 110, 0, 16)
		nameL.Position = UDim2.new(0, 46, 0, 1)
		nameL.BackgroundTransparency = 1
		nameL.Text = playerName
		nameL.TextColor3 = isSelf and C.ACCENT or C.ACCENT2
		nameL.TextSize = 11
		nameL.Font = Enum.Font.GothamBold
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.TextTruncate = Enum.TextTruncate.AtEnd
		nameL.Parent = row

		local msgL = Instance.new("TextLabel")
		msgL.Size = UDim2.new(1, -8, 0, 0)
		msgL.Position = UDim2.new(0, 4, 0, 17)
		msgL.AutomaticSize = Enum.AutomaticSize.Y
		msgL.BackgroundTransparency = 1
		msgL.Text = content
		msgL.TextColor3 = isSelf and Color3.fromRGB(180, 215, 240) or C.TEXT
		msgL.TextSize = 12
		msgL.Font = Enum.Font.Gotham
		msgL.TextXAlignment = Enum.TextXAlignment.Left
		msgL.TextWrapped = true
		msgL.Parent = row

		table.insert(messageElements, row)
		if #messageElements > MAX_MESSAGES then
			table.remove(messageElements, 1):Destroy()
		end
		task.defer(function()
			chatScroll.CanvasPosition = Vector2.new(0, chatScroll.AbsoluteCanvasSize.Y)
		end)
	end

	appendSystem = function(msg)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 18)
		row.BackgroundTransparency = 1
		row.LayoutOrder = #messageElements + 1
		row.Parent = chatScroll

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "◆ " .. msg
		lbl.TextColor3 = C.SYS
		lbl.TextSize = 10
		lbl.Font = Enum.Font.GothamBold
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		table.insert(messageElements, row)
		task.defer(function()
			chatScroll.CanvasPosition = Vector2.new(0, chatScroll.AbsoluteCanvasSize.Y)
		end)
	end

	local function doSend()
		local txt = inputBox.Text
		if not txt or txt:gsub("%s", "") == "" then return end
		inputBox.Text = ""
		local ch, msg2 = txt:match("^/(%a+)%s+(.+)$")
		if ch and msg2 then
			task.spawn(sendMessage, ch:lower(), msg2)
		else
			task.spawn(sendMessage, currentChannel, txt)
		end
	end

	sendBtn.MouseButton1Click:Connect(doSend)
	inputBox.FocusLost:Connect(function(enter) if enter then doSend() end end)

	addBtn.MouseButton1Click:Connect(function()
		inputBox:CaptureFocus()
		inputBox.PlaceholderText = "New channel name, press Enter..."
		local conn
		conn = inputBox.FocusLost:Connect(function(enter)
			conn:Disconnect()
			local newCh = inputBox.Text:lower():gsub("%s", "")
			inputBox.Text = ""
			inputBox.PlaceholderText = "Message #" .. currentChannel .. "..."
			if enter and newCh ~= "" and not tabButtons[newCh] then
				table.insert(CHANNELS, newCh)
				addTab(newCh, #CHANNELS)
				setActiveTab(newCh)
				appendSystem("Joined #" .. newCh)
			end
		end)
	end)

	minimizeBtn.MouseButton1Click:Connect(function()
		isMinimized = not isMinimized
		local chatArea2 = mainFrame:FindFirstChild("chatArea")
		local div = mainFrame:FindFirstChild("divider")
		local inp = mainFrame:FindFirstChild("inputArea")
		local tb = mainFrame:FindFirstChild("tabBar")
		if chatArea2 then chatArea2.Visible = not isMinimized end
		if div then div.Visible = not isMinimized end
		if inp then inp.Visible = not isMinimized end
		if tb then tb.Visible = not isMinimized end
		TweenService:Create(mainFrame, TweenInfo.new(0.18), {
			Size = isMinimized and UDim2.new(0, W, 0, 36) or UDim2.new(0, W, 0, H)
		}):Play()
		minimizeBtn.Text = isMinimized and "□" or "—"
	end)

	header.InputBegan:Connect(function(inp2)
		if inp2.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = true
			dragStart = inp2.Position
			startPos = mainFrame.Position
		end
	end)
	header.InputEnded:Connect(function(inp2)
		if inp2.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(inp2)
		if isDragging and inp2.UserInputType == Enum.UserInputType.MouseMovement then
			local d = inp2.Position - dragStart
			mainFrame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end)

	appendSystem("Universal Chat ready")
	appendSystem("Type to send  |  /channel msg  |  + new channel")

	return setActiveTab
end

function sendMessage(channelName, content)
	local channelId = getOrCreateChannel(channelName)
	if not channelId then return end
	request("POST", "/rest/v1/messages", {
		channel_id = channelId,
		player_name = localPlayer.Name,
		player_id = tostring(localPlayer.UserId),
		content = content,
	})
end

local function fetchNew(channelId, channelName)
	local path = "/rest/v1/messages?channel_id=eq." .. channelId
		.. "&select=player_name,player_id,content,created_at"
		.. "&order=created_at.asc"
		.. "&limit=" .. MAX_MESSAGES
	if lastMessageTime[channelName] then
		path = path .. "&created_at=gt." .. lastMessageTime[channelName]
	end
	local msgs = request("GET", path)
	if msgs and #msgs > 0 then
		lastMessageTime[channelName] = msgs[#msgs].created_at
		for _, msg in ipairs(msgs) do
			if channelName == currentChannel and appendMessage then
				local ts = msg.created_at and msg.created_at:sub(12, 19) or "??"
				local isSelf = tostring(msg.player_id) == tostring(localPlayer.UserId)
				appendMessage(msg.player_name, msg.content, channelName, ts, isSelf)
			end
		end
	end
end

function startPolling(channelName)
	if pollConnection then pollConnection:Disconnect(); pollConnection = nil end
	currentChannel = channelName
	local channelId = getOrCreateChannel(channelName)
	if not channelId then return end
	if not lastMessageTime[channelName] then
		lastMessageTime[channelName] = os.date("!%Y-%m-%dT%H:%M:%SZ")
	end
	local elapsed = 0
	pollConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		if elapsed < POLL_INTERVAL then return end
		elapsed = 0
		task.spawn(fetchNew, channelId, channelName)
	end)
end

buildGUI()
task.spawn(startPolling, DEFAULT_CHANNEL)
