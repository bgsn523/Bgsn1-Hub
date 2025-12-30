if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 플레이어가 로드될 때까지 대기
repeat
    task.wait()
until LocalPlayer


-- [[ 서비스 및 기본 변수 정의 ]] [cite: 167]
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- [[ 오토팜 설정 테이블 ]]
local AutoFarmConfig = {
    Enabled = false,
    Distance = 0,
    HeightOffset = 5,
    TargetMob = nil,
    CurrentTarget = nil,
    AutoSkillEnabled = false,
    AutoClickEnabled = true, 
    Skills = {E = false, R = false, T = false}
}

-- [[ 캐릭터 설정 테이블 ]]
local CharacterSettings = {
    WalkSpeed = 16,        -- 이동 속도
    JumpPower = 50,        -- 점프력
    AntiAFKEnabled = true, -- 잠수(AFK) 방지 여부
    LoopEnabled = true,    -- 속도/점프력 유지 여부
    NoClipEnabled = false  -- 벽 통과 여부
}
-- [[ 기타 필수 변수들 (이게 없으면 오류가 납니다) ]]
local AttackDirection = "Front"
local DirectionAngles = {Front = 0, Back = 180, Up = -90, Down = 90}
local Mobs = Workspace:WaitForChild("Mobs")
local MobList, MobMap = {}, {}
local AutoFarmConnection = nil
local lastAttackTime = 0
local lastSkillTime = 0
local NoClipConnection = nil
local MobDropdownObject = nil

-- [[ 텔레포트 위치 좌표 (2세계 전용) ]]
local TeleportLocations = {
    ["1세계 포탈"] = CFrame.new(-1222.33264, 12.7694845, -274.283813, 0.945803106, 0, 0.324740738, 0, 1, 0, -0.324740738, 0, 0.945803106),
}

-- [[ AFK 방지 로직 ]]
-- 사용자가 20분 이상 입력이 없으면 튕기는 것을 방지하기 위해 가상 클릭 발생
if CharacterSettings.AntiAFKEnabled then
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- 캐릭터 객체 가져오기 (없으면 대기)
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() -- [cite: 169]
end

-- [[ 텔레포트 함수 ]]
-- HumanoidRootPart의 CFrame을 변경하여 순간이동
local function teleportTo(positionName)
    local character = getCharacter()
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and TeleportLocations[positionName] then
        hrp.CFrame = TeleportLocations[positionName]
        print("텔레포트 완료:", positionName)
    else
        print("텔레포트 실패:", positionName)
    end
end

-- [[ 스킬 사용 함수 ]]
-- 서버의 RemoteEvent를 호출하여 스킬 발동
local function fireSkill(skillKey)
    pcall(function()
        local remote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Skill")
        remote:FireServer(skillKey)
    end)
end

-- [[ 몹 리스트 갱신 함수 ]] [cite: 170]
-- Workspace의 Mobs 폴더를 스캔하여 이름과 체력을 가져와 목록화
local function getMobList()
    local mobsFolder = Mobs
    local processedMobs = {}
    local mobDisplayList = {}
    local mobNameMap = {}

    for _, mob in ipairs(mobsFolder:GetChildren()) do
        if not processedMobs[mob.Name] then
            -- 몹의 머리 위에 있는 UI(HpText)를 찾아 실제 체력 정보를 포함한 이름을 생성
            local mobHead = mob:FindFirstChild("Head")
            if mobHead and mobHead:FindFirstChild("MobHead")
               and mobHead.MobHead:FindFirstChild("Frame")
               and mobHead.MobHead.Frame:FindFirstChild("HpText") then -- [cite: 171]
                local hpText = mobHead.MobHead.Frame.HpText.Text or "?"
                local displayName = mob.Name .. " [" .. hpText .. "]" -- [cite: 172]
                table.insert(mobDisplayList, displayName)
                mobNameMap[displayName] = mob.Name
                processedMobs[mob.Name] = true
            end
        end
    end

    table.sort(mobDisplayList)
    return mobDisplayList, mobNameMap
end

-- 초기 몹 리스트 로드
MobList, MobMap = getMobList() -- [cite: 173]

-- [[ 몹 사망 여부 확인 함수 ]]
-- 몹이 Workspace에서 사라지거나 투명해지면 죽은 것으로 간주
local function isMobDead(mob)
    if not (mob and mob.Parent) then return true end
    if mob:FindFirstChild("HumanoidRootPart") then return false end
    for _, child in pairs(mob:GetChildren()) do
        if child:IsA("BasePart") and child.Transparency >= 0.01 then
            return true
        end
    end
    return false
end

-- [[ 타겟 몹 찾기 함수 ]] [cite: 174]
-- 설정된 TargetMob 이름과 일치하고 살아있는 몹을 검색
local function findTargetMob()
    if not AutoFarmConfig.TargetMob then return nil end
    for _, mob in pairs(Mobs:GetChildren()) do
        if mob.Name == AutoFarmConfig.TargetMob and not isMobDead(mob) then
            return mob
        end
    end
    return nil
end

-- [[ 공격 함수 ]]
-- 가상 마우스 클릭으로 공격
local function attack()
    VirtualUser:Button1Down(Vector2.new(500, 500))
    task.wait(0.03)
    VirtualUser:Button1Up(Vector2.new(500, 500))
end

-- [[ 오토팜 위치 계산 함수 (CFrame) ]]
-- 타겟 몹의 위치를 기준으로 오프셋(거리, 높이) 및 바라보는 방향 계산
local function calculatePerfectCFrame(targetPos, distanceOffset, attackDirection)
    local targetRootPart = AutoFarmConfig.CurrentTarget:FindFirstChild("HumanoidRootPart") or AutoFarmConfig.CurrentTarget:FindFirstChild("HRP")
    if not targetRootPart then return CFrame.new(targetPos) end

    local npcLookDirection = targetRootPart.CFrame.LookVector
    local offsetPosition = targetRootPart.Position + (npcLookDirection * distanceOffset)
    offsetPosition = Vector3.new(offsetPosition.X, targetPos.Y, offsetPosition.Z) -- [cite: 175]

    -- 위/아래 공격 모드일 경우 각도 조절, 아니면 몹을 바라보게 설정
    if attackDirection == "Up" or attackDirection == "Down" then
        local angle = DirectionAngles[attackDirection] or 0
        return CFrame.new(offsetPosition) * CFrame.Angles(math.rad(angle), 0, 0)
    else
        return CFrame.lookAt(offsetPosition, targetRootPart.Position)
    end
end

-- [[ 노클립(NoClip) 함수 ]] [cite: 176]
-- 플레이어 캐릭터의 모든 파트의 충돌(CanCollide)을 비활성화하여 벽을 뚫게 함
local function toggleNoClip(enabled)
    if NoClipConnection then NoClipConnection:Disconnect() end
    if enabled then
        NoClipConnection = RunService.Stepped:Connect(function()
            local character = LocalPlayer.Character
            if character then
                for _, part in pairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end -- [cite: 177]
                end
            end
        end)
    end
end

-- [[ 오토팜 시작 함수 (수정됨: 물리 고정 해제 + 오토클릭) ]]
local function startAutoFarm()
    if AutoFarmConnection then AutoFarmConnection:Disconnect() end

    AutoFarmConnection = RunService.Heartbeat:Connect(function()
        local character = LocalPlayer.Character
        if not character then return end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not hrp then return end

        if humanoid.Health <= 0 then
            AutoFarmConfig.CurrentTarget = nil
            return
        end

        if not AutoFarmConfig.Enabled then
            humanoid.PlatformStand = false
            return
        end

        if AutoFarmConfig.CurrentTarget and isMobDead(AutoFarmConfig.CurrentTarget) then
            AutoFarmConfig.CurrentTarget = nil
        end
        if not AutoFarmConfig.CurrentTarget then
            AutoFarmConfig.CurrentTarget = findTargetMob()
        end

        local currentTarget = AutoFarmConfig.CurrentTarget
        if not currentTarget then return end

        local targetRootPart = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget:FindChild("HRP")
        if not targetRootPart then
            AutoFarmConfig.CurrentTarget = nil
            return
        end

        -- 위치 계산 및 이동
        local targetPos = Vector3.new(
            targetRootPart.Position.X,
            targetRootPart.Position.Y + AutoFarmConfig.HeightOffset,
            targetRootPart.Position.Z
        )

        local finalCFrame = calculatePerfectCFrame(targetPos, AutoFarmConfig.Distance, AttackDirection)
        hrp.CFrame = finalCFrame

        pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)

        -- [수정] 물리 고정(PlatformStand) 제거됨 -> 자연스러운 움직임
        
        -- 자동 클릭 (토글 확인)
        local currentTime = tick()
        if currentTime - lastAttackTime >= 0.08 then
            if AutoFarmConfig.AutoClickEnabled then
                attack()
            end
            lastAttackTime = currentTime
        end

        -- 오토 스킬
        if AutoFarmConfig.AutoSkillEnabled then
            if currentTime - lastSkillTime >= 2 then
                if AutoFarmConfig.Skills.E then fireSkill("E") end
                if AutoFarmConfig.Skills.R then fireSkill("R") end
                if AutoFarmConfig.Skills.T then fireSkill("T") end
                lastSkillTime = currentTime
             end
        end
    end)
end

-- [[ 매크로 방지 우회 함수 (Anti-Macro) ]]
-- 화면에 뜨는 "다음 숫자를 입력해주세요" GUI를 찾아 자동으로 입력하여 우회
local function antiMacro()
    spawn(function()
        while true do
            pcall(function()
                local gui = game.Players.LocalPlayer.PlayerGui:FindFirstChild("MacroGui")
                if not gui then return end

                local frame1 = gui:FindFirstChild("Frame") -- [cite: 185]
                if not frame1 then return end

                local frame2 = frame1:FindFirstChild("Frame")
                if not frame2 then return end

                local input = frame2:FindFirstChild("Input")
                local textBox = frame2:FindFirstChild("TextBox") -- [cite: 186]
                if not (input and textBox and input:IsA("TextLabel") and textBox:IsA("TextBox")) then
                    return
                end

                -- 질문 텍스트에서 숫자만 추출하여 입력창에 대입
                local text = input.Text or ""
                local cleanText = string.gsub(text, "다음 숫자를 입력해주세요: ", "") -- [cite: 187]
                textBox.Text = cleanText
            end)
            wait(5)
        end
    end)
end

-- [[ ESP 관련 변수 및 함수 ]]
local MobESPEnabled = false
local PlayerESPEnabled = false
local MobHighlights = {}
local PlayerHighlights = {}
local MobChildConn = nil
local PlayerChildConn = nil

-- Highlight 객체를 생성하여 타겟을 밝게 표시
local function createHighlight(model, storeTable, color)
    if storeTable[model] then return end
    
    local highlight = Instance.new("Highlight") -- [cite: 188]
    highlight.FillColor = color
    highlight.FillTransparency = 0.6
    highlight.OutlineTransparency = 0
    highlight.OutlineColor = Color3.new(1, 1, 1)
    highlight.Adornee = model
    highlight.Parent = model
    storeTable[model] = highlight
end

-- 생성된 Highlight 제거
local function clearHighlights(storeTable)
    for m, h in pairs(storeTable) do
        if h and h.Parent then
            h:Destroy()
        end
        storeTable[m] = nil -- [cite: 189]
    end
end

-- [[ 몹 ESP 설정 ]]
local function setMobESP(enabled)
    MobESPEnabled = enabled
    if enabled then
        -- 기존 몹 표시
        for _, mob in pairs(Mobs:GetChildren()) do
            createHighlight(mob, MobHighlights, Color3.fromRGB(255, 0, 0))
        end
        -- 새로 스폰되는 몹 감지 및 표시
        if MobChildConn then MobChildConn:Disconnect() end
        MobChildConn = Mobs.ChildAdded:Connect(function(mob)
            task.wait(0.3)
            if MobESPEnabled and mob and mob.Parent == Mobs then -- [cite: 190]
                createHighlight(mob, MobHighlights, Color3.fromRGB(255, 0, 0))
            end
        end)
    else
        -- 끄면 연결 해제 및 하이라이트 삭제
        if MobChildConn then
            MobChildConn:Disconnect()
            MobChildConn = nil
        end
        clearHighlights(MobHighlights) -- [cite: 191]
    end
end

-- [[ 플레이어 ESP 설정 ]]
local function setPlayerESP(enabled)
    PlayerESPEnabled = enabled
    if enabled then
        -- 기존 플레이어 표시
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                createHighlight(plr.Character, PlayerHighlights, Color3.fromRGB(0, 255, 0))
            end
        end
        -- 새로 들어오는 플레이어 감지
        if PlayerChildConn then PlayerChildConn:Disconnect() end -- [cite: 192]
        PlayerChildConn = Players.PlayerAdded:Connect(function(plr)
            plr.CharacterAdded:Connect(function(char)
                task.wait(0.3)
                if PlayerESPEnabled then
                    createHighlight(char, PlayerHighlights, Color3.fromRGB(0, 255, 0))
                end -- [cite: 193]
            end)
        end)
        -- 캐릭터가 리스폰될 때 다시 표시
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                plr.CharacterAdded:Connect(function(char)
                    task.wait(0.3)
                    if PlayerESPEnabled then -- [cite: 194]
                        createHighlight(char, PlayerHighlights, Color3.fromRGB(0, 255, 0))
                    end
                end)
            end
        end
    else
        if PlayerChildConn then -- [cite: 195]
            PlayerChildConn:Disconnect()
            PlayerChildConn = nil
        end
        clearHighlights(PlayerHighlights)
    end
end

-- [[ UI 라이브러리(LinoriaLib) 로드 ]]
local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

-- [[ 메인 윈도우 생성 ]]
local Window = Library:CreateWindow({
    Title = 'Bgsn1 Hub | 제작자:nuguseyo_12', -- [cite: 196]
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

-- [[ 탭 생성 ]]
local Tabs = {
    Main = Window:AddTab('메인'),
    Character = Window:AddTab('캐릭터'),
    Teleport = Window:AddTab('텔레포트'),
    Misc = Window:AddTab('기타'),
    Settings = Window:AddTab('설정')
}

-- [[ 오토팜 그룹박스 설정 (Main 탭) ]]
local AutoFarmGroup = Tabs.Main:AddLeftGroupbox('오토팜')

-- [[ 오토팜 토글 (기존 코드) ]]
AutoFarmGroup:AddToggle('AutoFarmToggle', {
    Text = '오토팜',
    Default = false,
    Tooltip = '몬스터 자동사냥',
    Callback = function(Value)
        AutoFarmConfig.Enabled = Value
        AutoFarmConfig.CurrentTarget = nil
        if Value then
            startAutoFarm()
        else
            -- 끄면 연결 해제 및 물리 상태 복구
            if AutoFarmConnection then
                AutoFarmConnection:Disconnect()
                AutoFarmConnection = nil
            end
            local character = getCharacter()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then 
                humanoid.PlatformStand = false
                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function() hrp:SetNetworkOwner(nil) end)
                end
            end
        end
    end
})

-- [[ 자동 클릭 토글 (여기에 정상적으로 추가됨) ]]
AutoFarmGroup:AddToggle('AutoClickToggle', {
    Text = '자동 클릭 (물리 공격)',
    Default = true,
    Tooltip = '오토팜 중 마우스 자동 클릭 여부',
    Callback = function(Value)
        AutoFarmConfig.AutoClickEnabled = Value
    end
})

-- 몹 목록 새로고침 버튼
AutoFarmGroup:AddButton({
    Text = '몹 목록 새로고침',
    Func = function()
        local newMobList, newMobMap = getMobList()
        MobList = newMobList
        MobMap = newMobMap -- [cite: 200]
        if MobDropdownObject and MobDropdownObject.SetValues then
            local newValues = (#MobList > 0 and MobList) or {"몹 없음"}
            MobDropdownObject:SetValues(newValues)
        end
    end
})

-- 몹 선택 드롭다운
MobDropdownObject = AutoFarmGroup:AddDropdown('MobDropdown', {
    Values = (#MobList > 0 and MobList) or {"몹 없음"},
    Default = 1,
    Multi = false,
    Text = '적 선택',
    Tooltip = '공격할 몹을 선택하세요', -- [cite: 201]
    Callback = function(Value)
        if MobMap[Value] then
            AutoFarmConfig.TargetMob = MobMap[Value]
            AutoFarmConfig.CurrentTarget = nil
        end
    end
})

-- 스킬 사용 토글
AutoFarmGroup:AddToggle('AutoSkillToggle', {
    Text = '오토스킬 (오토팜 연동)',
    Default = false,
    Tooltip = '오토팜 켜져있을 때만 E/R/T 스킬 자동 발사 (2초 쿨다운)',
    Callback = function(Value)
        AutoFarmConfig.AutoSkillEnabled = Value -- [cite: 202]
    end
})

-- 개별 스킬 사용 여부 설정
AutoFarmGroup:AddToggle('SkillEToggle', {
    Text = 'E 스킬',
    Default = false,
    Callback = function(Value)
        AutoFarmConfig.Skills.E = Value
    end
})

AutoFarmGroup:AddToggle('SkillRToggle', {
    Text = 'R 스킬',
    Default = false,
    Callback = function(Value)
        AutoFarmConfig.Skills.R = Value
    end
})

AutoFarmGroup:AddToggle('SkillTToggle', {
    Text = 'T 스킬',
    Default = false,
    Callback = function(Value)
        AutoFarmConfig.Skills.T = Value -- [cite: 203]
    end
})

-- 거리 및 높이 슬라이더
AutoFarmGroup:AddSlider('DistanceSlider', {
    Text = 'NPC 앞/뒤 거리',
    Default = 0,
    Min = -20,
    Max = 20,
    Rounding = 1,
    Tooltip = '양수=NPC앞쪽, 음수=NPC뒤쪽',
    Callback = function(Value)
        AutoFarmConfig.Distance = Value
    end
})

AutoFarmGroup:AddSlider('HeightOffsetSlider', {
    Text = '수직 오프셋 (Y축)',
    Default = 5,
    Min = -20,
    Max = 20,
    Rounding = 1, -- [cite: 204]
    Callback = function(Value)
        AutoFarmConfig.HeightOffset = Value
    end
})

-- 공격 방향 선택
AutoFarmGroup:AddDropdown('AttackDirectionDropdown', {
    Values = {'Front', 'Back', 'Up', 'Down'},
    Default = 1,
    Multi = false,
    Text = '공격 방향',
    Callback = function(Value)
        AttackDirection = Value
    end
})

-- [[ 타이머 그룹박스 (Main 탭 우측) ]]
local SpawnerMobGroup = Tabs.Main:AddRightGroupbox('타이머')

-- 고정된 보스/몹 리스트 (2세계 전용 목록) [cite: 205]
local FixedSpawnerMobs = {
    "갈색옷 주민",
    "기사 주민",
    "다크 기사단장",
    "더 할루시네이션",
    "마나 정원",
    "마나 장석",
    "서리 늑대",
    "순수한 마나 광석",
    "아르카나",
    "언데드 영혼체",
    "얼어죽은 핏빛",
    "용력석",
    "크람푸스",
    "파라다이스 무사",
    "파라다이스 수장",
    "파란옷 주민",
    "페어리",
    "포저링"
}

local SpawnerMobMap = {}
for _, name in ipairs(FixedSpawnerMobs) do
    SpawnerMobMap[name] = name
end

local TimerLabel = SpawnerMobGroup:AddLabel('쿨타임: 몹을 선택하세요')
local CurrentSelectedMobName = nil
local TimerUIs = {}
local UpdateConnections = {}

local EXTRA_TIME = 2 -- 추가 여유 시간

-- [[ 타이머 UI 생성 함수 ]]
-- 화면에 드래그 가능한 쿨타임 표시 창을 생성
local function createTimerUI(mobName)
    local timerUI = Instance.new("ScreenGui") -- [cite: 206]
    timerUI.Name = "MobTimerUI_" .. tick()
    timerUI.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    timerUI.ResetOnSpawn = false
    
    -- 메인 프레임 설정
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Parent = timerUI
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Position = UDim2.new(math.random(10,70)/100, 0, math.random(20,60)/100, 0)
    mainFrame.Size = UDim2.new(0, 280, 0, 140)
    mainFrame.Active = true
    mainFrame.Draggable = true
    
    -- UI 디자인 요소 (모서리 둥글게, 테두리 등)
    local corner = Instance.new("UICorner") -- [cite: 207]
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 70, 75)
    stroke.Thickness = 1
    stroke.Parent = mainFrame
    
    local mobNameLabel = Instance.new("TextLabel")
    mobNameLabel.Name = "MobName"
    mobNameLabel.Parent = mainFrame
    mobNameLabel.BackgroundTransparency = 1
    mobNameLabel.Position = UDim2.new(0, 15, 0, 10)
    mobNameLabel.Size = UDim2.new(1, -50, 0, 30)
    mobNameLabel.Font = Enum.Font.GothamBold -- [cite: 208]
    mobNameLabel.Text = mobName
    mobNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobNameLabel.TextScaled = true
    mobNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    -- 진행 바(Progress Bar) 배경 및 바
    local progressBg = Instance.new("Frame")
    progressBg.Name = "ProgressBg"
    progressBg.Parent = mainFrame
    progressBg.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    progressBg.Position = UDim2.new(0, 15, 0, 50)
    progressBg.Size = UDim2.new(1, -30, 0, 22)
    
    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, 8)
    progressCorner.Parent = progressBg -- [cite: 209]
    
    local progressBar = Instance.new("Frame")
    progressBar.Name = "ProgressBar"
    progressBar.Parent = progressBg
    progressBar.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
    progressBar.Position = UDim2.new(0, 0, 0, 0)
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BorderSizePixel = 0
    
    local progressCorner2 = Instance.new("UICorner")
    progressCorner2.CornerRadius = UDim.new(0, 8)
    progressCorner2.Parent = progressBar
    
    -- 남은 시간 텍스트
    local timeLabel = Instance.new("TextLabel")
    timeLabel.Name = "TimeLabel"
    timeLabel.Parent = mainFrame -- [cite: 210]
    timeLabel.BackgroundTransparency = 1
    timeLabel.Position = UDim2.new(0, 15, 0, 80)
    timeLabel.Size = UDim2.new(1, -30, 0, 25)
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.Text = "스폰 대기 중..."
    timeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    timeLabel.TextScaled = true
    
    -- 닫기 버튼
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Parent = mainFrame
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    closeBtn.Position = UDim2.new(1, -25, 0, 5)
    closeBtn.Size = UDim2.new(0, 20, 0, 20) -- [cite: 211]
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "×"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextScaled = true
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 5)
    closeCorner.Parent = closeBtn
    
    -- 타이머 업데이트 함수 (매 프레임 실행)
    local function updateThisTimer()
        if not timerUI.Parent then return end
        
        local spawner = Workspace:FindFirstChild("Spawner")
        if not spawner then -- [cite: 212]
            timeLabel.Text = "Spawner 없음"
            progressBar.Size = UDim2.new(0, 0, 1, 0)
            return
        end
        
        local mobFolder = spawner:FindFirstChild(mobName)
        local coolObj = mobFolder and mobFolder:FindFirstChild("Cool")
        local coolTimeObj = mobFolder and mobFolder:FindFirstChild("CoolTime") -- [cite: 213]
        
        if not mobFolder or not coolObj or not coolTimeObj then
            timeLabel.Text = "스폰 대기 중..."
            progressBar.Size = UDim2.new(0, 0, 1, 0)
            progressBar.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
            return
        end -- [cite: 214]
        
        -- 쿨타임 계산
        local currentCool = coolObj.Value or 0
        local baseCoolTime = coolTimeObj.Value or 30
        local displayedCoolTime = baseCoolTime + EXTRA_TIME
        local remaining = displayedCoolTime - currentCool
        local progress = math.max(0, math.min(1, currentCool / displayedCoolTime))
        
        if remaining <= 0 then
            timeLabel.Text = "스폰 가능!" -- [cite: 215]
            progressBar.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
        else
            timeLabel.Text = string.format("남은 시간: %.1f / %d초", remaining, displayedCoolTime)
            progressBar.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
        end
        
        progressBar.Size = UDim2.new(progress, 0, 1, 0)
    end
    
    local updateConnection = game:GetService("RunService").Heartbeat:Connect(updateThisTimer) -- [cite: 216]
    
    closeBtn.MouseButton1Click:Connect(function()
        updateConnection:Disconnect()
        timerUI:Destroy()
    end)
    
    table.insert(TimerUIs, timerUI)
    table.insert(UpdateConnections, updateConnection)
end

-- 몹 선택 드롭다운 (타이머 및 오토팜 연동)
SpawnerMobGroup:AddDropdown('FixedSpawnerMobDropdown', {
    Values = FixedSpawnerMobs,
    Default = 1,
    Multi = false,
    Text = '몹 선택',
    Tooltip = '선택 시 오토팜 대상 설정',
    Callback = function(Value)
        if SpawnerMobMap[Value] then
            AutoFarmConfig.TargetMob = SpawnerMobMap[Value] -- [cite: 217]
            AutoFarmConfig.CurrentTarget = nil
            CurrentSelectedMobName = SpawnerMobMap[Value]
        end
    end
})

-- 타이머 생성 버튼
SpawnerMobGroup:AddButton({
    Text = '타이머 UI 추가',
    Func = function()
        if not CurrentSelectedMobName then
            game.StarterGui:SetCore("SendNotification", {
                Title = "알림"; -- [cite: 218]
                Text = "먼저 몹을 선택해주세요!";
                Duration = 3;
            }) -- [cite: 219]
            return
        end
        createTimerUI(CurrentSelectedMobName)
    end,
    Tooltip = '무제한 타이머 UI 추가 (드래그 가능)'
})

-- 모든 타이머 삭제 버튼
SpawnerMobGroup:AddButton({
    Text = '모든 타이머 닫기',
    Func = function()
        for _, connection in ipairs(UpdateConnections) do
            if connection then connection:Disconnect() end
        end
        for _, ui in ipairs(TimerUIs) do -- [cite: 220]
            if ui then ui:Destroy() end
        end
        TimerUIs = {}
        UpdateConnections = {}
    end,
    Tooltip = '화면의 모든 타이머 UI 제거'
})

-- [[ 캐릭터 스킨 변경 그룹 (Main 탭) ]]
local SkinChangerGroup = Tabs.Main:AddRightGroupbox('캐릭터 체인저')
local SkinUserIdBox = nil

SkinChangerGroup:AddInput('SkinUserIdInput', {
    Default = "",
    Numeric = true,
    Text = 'UserId 입력',
    Tooltip = '변장할 계정의 UserId 입력', -- [cite: 221]
    Placeholder = '계정 id 입력',
    Callback = function(Value)
        SkinUserIdBox = Value
    end
})

-- [[ 스킨 변경 함수 ]]
-- 입력받은 UserId의 외형 데이터를 불러와 내 캐릭터에 적용
local function applyDisguiseByUserId(userId, notifyName)
    local userIdNum = tonumber(userId)
    if not userIdNum then
        game.StarterGui:SetCore("SendNotification", {
            Title = "Disguise",
            Text = "UserId를 숫자로 입력하세요!",
            Duration = 4
        }) -- [cite: 222]
        return
    end

    local LocalPlayer = game.Players.LocalPlayer
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

    local ok, appearanceModel = pcall(function()
        return game.Players:GetCharacterAppearanceAsync(userIdNum)
    end)

    if not ok or not appearanceModel then
        game.StarterGui:SetCore("SendNotification", {
            Title = "Disguise",
            Text = "외형 로드 실패: " .. tostring(userIdNum), -- [cite: 223]
            Duration = 4
        })
        return
    end

    -- 기존 의상 및 악세서리 제거
    for _, inst in ipairs(character:GetChildren()) do
        if inst:IsA("Accessory")
        or inst:IsA("Shirt")
        or inst:IsA("Pants")
        or inst:IsA("CharacterMesh")
        or inst:IsA("BodyColors")
        or inst:IsA("ShirtGraphic") then -- [cite: 224]
            inst:Destroy()
        end
    end

    -- 머리 메시 제거
    local head = character:FindFirstChild("Head")
    if head then
        for _, inst in ipairs(head:GetChildren()) do
            if inst:IsA("SpecialMesh") and inst:GetAttribute("FromMorph") == true then
                inst:Destroy()
            end -- [cite: 225]
        end
        local face = head:FindFirstChild("face")
        if face then face:Destroy() end
    end

    -- 새 외형 적용
    for _, inst in ipairs(appearanceModel:GetChildren()) do
        if inst:IsA("Shirt")
        or inst:IsA("Pants")
        or inst:IsA("BodyColors")
        or inst:IsA("ShirtGraphic") then
            inst.Parent = character

        elseif inst:IsA("Accessory") then -- [cite: 226]
            inst.Name = "#ACCESSORY_" .. inst.Name
            inst.Parent = character

        elseif inst:IsA("SpecialMesh") and head then
            inst:SetAttribute("FromMorph", true)
            inst.Parent = head

        elseif inst.Name == "R6" and character:FindFirstChildOfClass("Humanoid").RigType == Enum.HumanoidRigType.R6 then
            local cm = inst:FindFirstChildOfClass("CharacterMesh") -- [cite: 227]
            if cm then cm.Parent = character end

        elseif inst.Name == "R15" and character:FindFirstChildOfClass("Humanoid").RigType == Enum.HumanoidRigType.R15 then
            local cm = inst:FindFirstChildOfClass("CharacterMesh")
            if cm then cm.Parent = character end
        end
    end

    -- 얼굴 적용
    if head then
        local faceInModel = appearanceModel:FindFirstChild("face") -- [cite: 228]
        if faceInModel then
            faceInModel.Parent = head
        else
            local decal = Instance.new("Decal")
            decal.Face = Enum.NormalId.Front
            decal.Name = "face"
            decal.Texture = "rbxasset://textures/face.png"
            decal.Parent = head -- [cite: 229]
        end

        -- 캐릭터 새로고침 (Parent를 뺐다 껴서 렌더링 업데이트)
        local parent = character.Parent
        character.Parent = nil
        character.Parent = parent
    end

    game.StarterGui:SetCore("SendNotification", {
        Title = "Disguise",
        Text = (notifyName or tostring(userIdNum)) .. " 외형으로 변경됨!",
        Duration = 5
    })
end

SkinChangerGroup:AddButton({
    Text = '캐릭터 체인지', -- [cite: 230]
    Func = function()
        applyDisguiseByUserId(SkinUserIdBox)
    end
})

-- [[ 저장된 변장 목록 관리 ]]
local SavedDisguises = {}
local SavedDisguiseFileName = "Bgsn1Hub_RPG_SavedDisguises.json"

-- 파일 저장 함수
local function saveDisguisesToFile()
    if not writefile then return end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(SavedDisguises)
    end)
    if ok then
        writefile(SavedDisguiseFileName, encoded)
    end
end

-- 파일 로드 함수
local function loadSavedDisguises()
    if not isfile or not readfile then return end
    if not isfile(SavedDisguiseFileName) then return end
    local ok, decoded = pcall(function() -- [cite: 231]
        local content = readfile(SavedDisguiseFileName)
        return HttpService:JSONDecode(content)
    end)
    if ok and type(decoded) == "table" then
        SavedDisguises = decoded
    end
end

-- 저장된 변장 버튼 갱신
local function refreshDisguiseButtons()
    if not SkinChangerGroup.__SavedButtons then
        SkinChangerGroup.__SavedButtons = {}
    end
    local createdFlags = SkinChangerGroup.__SavedButtons

    for name, userId in pairs(SavedDisguises) do
        if not createdFlags[name] then -- [cite: 232]
            createdFlags[name] = true
            SkinChangerGroup:AddButton({
                Text = "저장 불러오기: " .. name .. " (" .. userId .. ")",
                Func = function()
                    applyDisguiseByUserId(userId, name)
                end -- [cite: 233]
            })
        end
    end
end

-- 현재 입력된 UserId 저장 버튼
SkinChangerGroup:AddButton({
    Text = '현재 입력 UserId 저장',
    Func = function()
        local userIdNum = tonumber(SkinUserIdBox)
        if not userIdNum then
            game.StarterGui:SetCore("SendNotification", {
                Title = "Disguise 저장 실패", -- [cite: 234]
                Text = "UserId를 숫자로 입력하세요!",
                Duration = 4
            })
            return
        end

        local ok, name = pcall(function()
            return game.Players:GetNameFromUserIdAsync(userIdNum) -- [cite: 235]
        end)
        if not ok or not name then
            name = "User_" .. tostring(userIdNum)
        end

        SavedDisguises[name] = userIdNum
        saveDisguisesToFile()
        refreshDisguiseButtons()

        game.StarterGui:SetCore("SendNotification", {
            Title = "Disguise 저장됨", -- [cite: 236]
            Text = name .. "(" .. userIdNum .. ") 저장 완료!",
            Duration = 5
        })
    end
})

loadSavedDisguises()
refreshDisguiseButtons()

-- [[ 텔레포트 그룹 (Teleport 탭 - 2세계 전용 위치들) ]]
local LunaVillageGroup = Tabs.Teleport:AddRightGroupbox('스폰포인트')

-- 루나성 스폰 이동
LunaVillageGroup:AddButton({
    Text = '루나성 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame -- [cite: 237]

        local targetCFrame = CFrame.new(-122.006393, 10.1799183, 645.170105, 1, 0, 0, 0, 1, 0, 0, 0, 1)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["루나성"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

        if prompt then
            local backup = prompt.HoldDuration -- [cite: 238]
            prompt.HoldDuration = 0
            task.wait(0.05)
            fireproximityprompt(prompt)
            prompt.HoldDuration = backup
        end

        root.CFrame = originalCFrame
    end
})

-- 미궁 스폰 이동
LunaVillageGroup:AddButton({
    Text = '미궁 스폰',
    Func = function() -- [cite: 239]
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(-1645.18201, 4.39310074, 2685.46118, 0, 0, -1, 0, 1, 0, 1, 0, 0)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function() -- [cite: 240]
            prompt = workspace.SpawnPoint["미궁"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

        if prompt then
            local backup = prompt.HoldDuration
            prompt.HoldDuration = 0
            task.wait(0.05)
            fireproximityprompt(prompt)
            prompt.HoldDuration = backup -- [cite: 241]
        end

        root.CFrame = originalCFrame
    end
})

-- 파라다이스 스폰 이동
LunaVillageGroup:AddButton({
    Text = '파라다이스 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(1024.01343, 83.0640182, 2942.72339, 0, 0, -1, 0, 1, 0, 1, 0, 0) -- [cite: 242]

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["파라다이스"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

        if prompt then
            local backup = prompt.HoldDuration
            prompt.HoldDuration = 0 -- [cite: 243]
            task.wait(0.05)
            fireproximityprompt(prompt)
            prompt.HoldDuration = backup
        end

        root.CFrame = originalCFrame
    end
})

-- 프로스티아 스폰 이동
LunaVillageGroup:AddButton({
    Text = '프로스티아 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart") -- [cite: 244]

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(-248.735428, 24.4078789, 3271.08813, 0.990015864, -0, -0.140955985, 0, 1, -0, 0.140955985, 0, 0.990015864)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["프로스티아"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end) -- [cite: 245]

        if prompt then
            local backup = prompt.HoldDuration
            prompt.HoldDuration = 0
            task.wait(0.05)
            fireproximityprompt(prompt)
            prompt.HoldDuration = backup
        end

        root.CFrame = originalCFrame
    end
})

-- 프로스티아2 스폰 이동
LunaVillageGroup:AddButton({
    Text = '프로스티아2 스폰', -- [cite: 246]
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(2.69876909, 38.4310799, 4847.83936, 0.951553285, -1.34350366e-05, 0.307483971, -1.34350366e-05, 1, 8.52700978e-05, -0.307483971, -8.52700978e-05, 0.951553226)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt -- [cite: 247]
        pcall(function()
            prompt = workspace.SpawnPoint["프로스티아2"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

        if prompt then
            local backup = prompt.HoldDuration
            prompt.HoldDuration = 0
            task.wait(0.05)
            fireproximityprompt(prompt) -- [cite: 248]
            prompt.HoldDuration = backup
        end

        root.CFrame = originalCFrame
    end
})

-- 1세계로 돌아가는 텔레포트 버튼
LunaVillageGroup:AddButton({
    Text = '1세계 텔레포트',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local targetCFrame = CFrame.new(
            -1222.33264, 12.7694845, -274.283813, -- [cite: 249]
            0.945803106, 0, 0.324740738,
            0, 1, 0,
            -0.324740738, 0, 0.945803106
        )

        root.CFrame = targetCFrame
        task.wait(0.5)

        local map = workspace:FindFirstChild("Map")
        local chowan = map and map:FindFirstChild("초원") -- [cite: 250]
        local worldFolder = chowan and chowan:FindFirstChild("World")

        local prompt = worldFolder and worldFolder:FindFirstChildOfClass("ProximityPrompt")

        if prompt then
            local backup = prompt.HoldDuration
            prompt.HoldDuration = 0
            task.wait(0.05)
            fireproximityprompt(prompt)
            prompt.HoldDuration = backup -- [cite: 251]
        end
    end
})


-- [[ 텔레포트 버튼 (미리 정의된 좌표) ]]
local TeleportGroup = Tabs.Teleport:AddLeftGroupbox('텔레포트 위치')
TeleportGroup:AddButton({ Text = '1세계 포탈', Func = function() teleportTo("1세계 포탈") end })

-- [[ 기타 기능 (Misc 탭) ]]
local MacroGroup = Tabs.Misc:AddLeftGroupbox('매크로 방지 우회')
MacroGroup:AddButton({
    Text = '매크로 방지 우회',
    Func = antiMacro
})

local ScriptGroup = Tabs.Misc:AddRightGroupbox('스크립트')
-- Infinite Yield 실행 (유명한 관리자 명령어 스크립트)
ScriptGroup:AddButton({
    Text = '인피니티 야드',
    Func = function()
        loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source', true))()
    end
})

-- [[ 커스텀 무기 획득 스크립트 ]]
-- 특정 검을 소지하고 있을 때, 개발자용 무기([DEV] 미드나이트 천화의낫)로 외형과 기능을 변경
ScriptGroup:AddButton({
    Text = '[DEV] 미드나이트 천화의낫',
    Func = function()
        local player = game.Players.LocalPlayer -- [cite: 252]
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local char = workspace:WaitForChild(player.Name)
        local humanoid = char:WaitForChild("Humanoid")

        -- 변경 가능한 원본 검 목록
        local validSwords = {
            "나무 검", "돌 검", "철 검", "왕의 검", "강철 대검",
            "데저트의 전설", "샌드 단검", "미라 학살자", "고블린의 분노",
            "맹세의 검", "카타나", "마그마 대검", "골렘 파괴자", -- [cite: 253]
            "선혈도", "프로스트론", "툰드라의 기회", "냉기의 검",
            "일렉트릭 아이서", "여명의 손길", "저주받은 눈",
            "겨울성의 재보", "[DEV] 산나비 사슬팔", "다크 파이어",
            "저주혈검", "천멸추", "벚꽃도", "급사의 파훼", "용화도"
        }

        local swordTool = nil
        -- 인벤토리에 해당 검이 있는지 확인
        for _, tool in pairs(char:GetChildren()) do -- [cite: 254]
            if tool:IsA("Tool") then
                for _, name in pairs(validSwords) do
                    if tool.Name == name then
                        swordTool = tool
                        break -- [cite: 255]
                    end
                end
            end
            if swordTool then break end
        end

        if not swordTool then
            warn("지정된 검을 찾을 수 없습니다!") -- [cite: 256]
            return
        end

        -- 기존 검의 위치 데이터 저장
        local oldHandle = swordTool:WaitForChild("Handle")
        local oldGrip = swordTool:FindFirstChild("RightGrip", true)
        local gripC0
        if oldGrip and oldGrip:IsA("Motor6D") then
            gripC0 = oldGrip.C0
        end -- [cite: 257]

        -- 개발자용 무기 복제 및 지급
        local srcTool = ReplicatedStorage:WaitForChild("Tool"):WaitForChild("[DEV] 미드나이트 천화의낫")
        local newTool = srcTool:Clone()
        newTool.Name = "[DEV] 미드나이트 천화의낫"
        newTool.Parent = char

        local newHandle = newTool:WaitForChild("Handle")
        newHandle.Anchored = false

        -- 오른손에 무기 장착 (Motor6D 연결)
        local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
        local oldRightGrip = rightHand:FindFirstChild("RightGrip")
        if oldRightGrip then oldRightGrip:Destroy() end -- [cite: 258]

        local rightGrip = Instance.new("Motor6D")
        rightGrip.Name = "RightGrip"
        rightGrip.Part0 = rightHand
        rightGrip.Part1 = newHandle
        rightGrip.Parent = rightHand
        if gripC0 then
            rightGrip.C0 = gripC0
        else
            rightGrip.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 180, 0) -- [cite: 259]
        end

        swordTool:Destroy()

        task.wait(0.5)

        -- 공격 애니메이션 및 클릭 이벤트 연결
        local UserInputService = game:GetService("UserInputService")
        local Players = game:GetService("Players")

        local player = Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local animator = humanoid:WaitForChild("Animator") -- [cite: 260]

        local toolModel = workspace:WaitForChild(player.Name):WaitForChild("[DEV] 미드나이트 천화의낫")
        local attackAni1 = toolModel:WaitForChild("AttackAni1")
        local attackAni2 = toolModel:WaitForChild("AttackAni2")

        local clickCount = 0
        local canAttack = true
        local currentTrack = nil

        local function stopCurrentAnimation()
            if currentTrack then
                currentTrack:Stop() -- [cite: 261]
                currentTrack = nil
            end
        end

        -- 클릭 시 애니메이션 재생 (콤보 시스템)
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not canAttack then return end -- [cite: 262]

            canAttack = false
            clickCount += 1

            stopCurrentAnimation()
            if clickCount % 2 == 1 then
                currentTrack = animator:LoadAnimation(attackAni1)
            else
                currentTrack = animator:LoadAnimation(attackAni2) -- [cite: 263]
            end

            currentTrack:Play()

            task.delay(0.8, function()
                canAttack = true
            end)
        end)
    end
})

-- [[ 스카이박스 변경 기능 ]]
local SkyGroup = Tabs.Misc:AddLeftGroupbox('스카이 설정')

local OriginalSkyProperties = nil
local HasOriginalSky = false -- [cite: 264]

-- 원래 스카이박스 저장
local function SaveOriginalSky()
    if HasOriginalSky then return end
    local Lighting = game:GetService("Lighting")
    local Sky = Lighting:FindFirstChildOfClass("Sky")
    
    if Sky then
        OriginalSkyProperties = {}
        for _, prop in pairs({"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}) do
            OriginalSkyProperties[prop] = Sky[prop]
        end
        HasOriginalSky = true
    else
        HasOriginalSky = false -- [cite: 265]
    end
end

-- 스카이박스 적용 함수 (외부 스크립트에서 ID 로드)
local function ApplySkybox(Value)
    local Lighting = game:GetService("Lighting")
    local Sky = Lighting:FindFirstChildOfClass("Sky")
    if not Sky then
        Sky = Instance.new("Sky")
        Sky.Parent = Lighting
    end

    if Value == "None" then
        -- 기본 스카이박스로 복원
        if HasOriginalSky and OriginalSkyProperties then
            for prop, assetId in pairs(OriginalSkyProperties) do
                Sky[prop] = assetId -- [cite: 266]
            end
            Lighting.GlobalShadows = true
        else
            for _, prop in pairs({"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}) do
                Sky[prop] = ""
            end -- [cite: 267]
            Lighting.GlobalShadows = true
        end
        
        game.StarterGui:SetCore("SendNotification", {
            Title = "Skybox",
            Text = "기본 스카이박스로 복원됨",
            Duration = 3
        })
    else
        -- 외부 소스에서 스카이박스 데이터 로드
        local success, SkyboxLoader = pcall(function() -- [cite: 268]
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Forexium/eclipse/main/Skyboxes.lua", true))()
        end)

        if success and SkyboxLoader and SkyboxLoader[Value] then
            local skyboxData = SkyboxLoader[Value]
            for i, prop in ipairs({"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}) do
                Sky[prop] = "rbxassetid://" .. skyboxData[i] -- [cite: 269]
            end
            Lighting.GlobalShadows = false

            game.StarterGui:SetCore("SendNotification", {
                Title = "Skybox",
                Text = Value .. " 스카이박스 적용됨!",
                Duration = 3 -- [cite: 270]
            })
        else
            game.StarterGui:SetCore("SendNotification", {
                Title = "Skybox 오류",
                Text = "로드 실패: " .. Value,
                Duration = 5 -- [cite: 271]
            })
        end
    end
end

SaveOriginalSky()

SkyGroup:AddDropdown('SkyBoxDropdown', {
    Values = {"None", "Space Wave", "Space Wave2", "Turquoise Wave", "Dark Night", "Bright Pink", "White Galaxy"},
    Default = "None",
    Multi = false,
    Text = '스카이박스 선택',
    Tooltip = '선택하는 순간 바로 하늘이 바뀝니다',
    Callback = function(Value)
        ApplySkybox(Value)
    end
})

-- [[ 눈 내리기 효과 ]]
local SnowEnabled = false
local SnowConnection = nil
local snowflakeModel = game:GetObjects("rbxassetid://3251705941")[1]

ScriptGroup:AddToggle('SnowToggle', {
    Text = '눈 내리기',
    Default = false, -- [cite: 272]
    Tooltip = '플레이어 주위로 눈이 계속 내림',
    Callback = function(Value)
        SnowEnabled = Value
        
        if Value then
            SnowConnection = game:GetService("RunService").Heartbeat:Connect(function()
                local player = game.Players.LocalPlayer
                local char = player.Character
                if not char or not char:FindFirstChild("HumanoidRootPart") then return end -- [cite: 273]
                
                local playerPos = char.HumanoidRootPart.Position
                
                -- 확률적으로 눈송이 생성
                if math.random(1, 8) == 1 then
                    task.spawn(function() -- [cite: 274]
                        local snowflake = snowflakeModel:Clone()
                        snowflake.Size = snowflake.Size * 0.3
                        snowflake.Anchored = true
                        snowflake.CanCollide = false -- [cite: 275]
                        snowflake.CanTouch = false
                        snowflake.CanQuery = false
                        snowflake.Massless = true -- [cite: 276]
                        
                        -- 플레이어 주변 랜덤 위치에 스폰
                        local angle = math.random() * math.pi * 2
                        local distance = math.random() * 500
                        local spawnPos = playerPos + Vector3.new( -- [cite: 277]
                            math.cos(angle) * distance,
                            200,
                            math.sin(angle) * distance -- [cite: 278]
                        )
                        
                        snowflake.Position = spawnPos
                        snowflake.Parent = game.Workspace -- [cite: 279]
                        
                        local rotation = 0
                        local startTime = tick()
                        
                        -- 눈송이 하강 및 회전 애니메이션
                        while tick() - startTime < 8 and snowflake.Parent do -- [cite: 280]
                            local currentPos = snowflake.Position
                            snowflake.CFrame = CFrame.new(currentPos.X, currentPos.Y - 1, currentPos.Z) -- [cite: 281]
                                * CFrame.Angles(0, math.rad(rotation), 0)
                            rotation += 2
                            task.wait(0.03)
                        end -- [cite: 282]
                        
                        snowflake:Destroy()
                    end)
                end -- [cite: 283]
            end)
            print("눈 내리기 활성화")
        else
            if SnowConnection then
                SnowConnection:Disconnect()
                SnowConnection = nil
            end
            print("눈 내리기 비활성화") -- [cite: 284]
        end
    end
})

-- [[ FPS 최적화 기능 ]]
local OptimizerGroup = Tabs.Misc:AddRightGroupbox('FPS 최적화')

local FPSUnlocked = false
local AntiLagEnabled = false
local FPSBoosterEnabled = false

-- FPS 제한 해제
OptimizerGroup:AddToggle('FPSUnlockToggle', {
    Text = 'FPS Unlocker',
    Default = false,
    Tooltip = 'FPS 캡 해제 (켜면 9999, 끄면 240으로 복구)',
    Callback = function(Value)
        FPSUnlocked = Value
        if Value then
            setfpscap(9999) -- [cite: 285]
            game.StarterGui:SetCore("SendNotification", {Title = "Optimizer", Text = "FPS Unlocker 활성화 (최대 9999)", Duration = 3})
        else
            setfpscap(240)
            game.StarterGui:SetCore("SendNotification", {Title = "Optimizer", Text = "FPS Unlocker 비활성화 (240 캡)", Duration = 3})
        end
    end
})

-- 렉 방지 (그래픽 품질 강제 저하)
OptimizerGroup:AddButton({
    Text = 'Anti LAG',
    Func = function()
        AntiLagEnabled = not AntiLagEnabled -- [cite: 286]
        
        if AntiLagEnabled then
            -- 물리, 렌더링, 그림자, 조명 효과 제거 및 품질 저하
            settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Always
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9000000000
            Lighting.Brightness = 2
             
            for _, effect in pairs(Lighting:GetChildren()) do -- [cite: 287]
                if effect:IsA("PostEffect") or effect:IsA("BloomEffect") or effect:IsA("BlurEffect") or 
                   effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") then
                    effect.Enabled = false
                end -- [cite: 288]
            end
            
            pcall(function()
                sethiddenproperty(Workspace.Terrain, "Decoration", false)
            end)
            
            -- 모든 파트의 재질을 단순화하고 텍스처 투명화
            for _, obj in pairs(game:GetDescendants()) do -- [cite: 289]
                if obj:IsA("BasePart") and not obj:IsA("MeshPart") then
                    obj.Material = Enum.Material.SmoothPlastic
                elseif obj:IsA("Texture") or obj:IsA("Decal") then
                    obj.Transparency = 1
                end -- [cite: 290]
            end
            
            game.StarterGui:SetCore("SendNotification", {
                Title = "Optimizer",
                Text = "Anti LAG 활성화됨 (그래픽 강제 저하 + 효과 off)",
                Duration = 4 -- [cite: 291]
            })
        else
            -- 복구 (완벽하지 않을 수 있음)
            Lighting.GlobalShadows = true
            pcall(function()
                sethiddenproperty(Workspace.Terrain, "Decoration", true)
            end)
            
            game.StarterGui:SetCore("SendNotification", { -- [cite: 292]
                Title = "Optimizer",
                Text = "Anti LAG 비활성화됨 (일부는 복구 안 될 수 있음)",
                Duration = 4
            })
        end
    end
})

-- FPS 부스터 (파티클/이펙트 제거)
OptimizerGroup:AddButton({
    Text = 'FPS Booster',
    Func = function() -- [cite: 293]
        FPSBoosterEnabled = not FPSBoosterEnabled
        
        if FPSBoosterEnabled then
            for _, obj in pairs(game:GetDescendants()) do
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Explosion") then
                    obj.Enabled = false
                end -- [cite: 294]
            end
            
            game.StarterGui:SetCore("SendNotification", {
                Title = "Optimizer",
                Text = "FPS Booster 활성화 (파티클/트레일/폭발 off)",
                Duration = 4 -- [cite: 295]
            })
        else
            game.StarterGui:SetCore("SendNotification", {
                Title = "Optimizer",
                Text = "FPS Booster 비활성화 (기존 파티클 복구 안 됨)",
                Duration = 4
            }) -- [cite: 296]
        end
    end
})

-- [[ 캐릭터 탭 설정 ]]
local CharLeftGroup = Tabs.Character:AddLeftGroupbox('캐릭터')
local NoClipRightGroup = Tabs.Character:AddRightGroupbox('노클립')
local EspGroup = Tabs.Character:AddRightGroupbox('ESP')

-- 이동 속도 슬라이더
CharLeftGroup:AddSlider('WalkSpeedSlider', {
    Text = '이동 속도', Default = 30, Min = 10, Max = 200, Rounding = 1,
    Callback = function(Value) CharacterSettings.WalkSpeed = Value end
})
CharacterSettings.WalkSpeed = 30

-- 점프력 슬라이더
CharLeftGroup:AddSlider('JumpPowerSlider', {
    Text = '점프력', Default = 50, Min = 20, Max = 300, Rounding = 1,
    Callback = function(Value) CharacterSettings.JumpPower = Value end
})

-- AFK 방지 토글
CharLeftGroup:AddToggle('AntiAFKToggle', {
    Text = 'AFK 방지', Default = true, -- [cite: 297]
    Callback = function(Value)
        CharacterSettings.AntiAFKEnabled = Value
        if Value then
            LocalPlayer.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end
})

-- [[ 핵심 수정 부분: 속도 강제 적용 로직 추가 ]] --
CharLeftGroup:AddToggle('LoopToggle', {
    Text = '속도 강제 적용', 
    Default = true,
    Tooltip = '체크 시 설정한 속도와 점프력을 계속 유지합니다.',
    Callback = function(Value)
        CharacterSettings.LoopEnabled = Value
    end
})

-- 매 프레임마다 속도를 강제로 적용하는 루프 (이게 없어서 작동 안 했던 것임)
game:GetService("RunService").Heartbeat:Connect(function()
    -- '속도 강제 적용'이 켜져있고, 캐릭터가 존재할 때만 실행
    if CharacterSettings.LoopEnabled and LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            -- 현재 설정된 값으로 강제 변경
            humanoid.WalkSpeed = CharacterSettings.WalkSpeed
            humanoid.JumpPower = CharacterSettings.JumpPower
            
            -- 오토팜 사용 시 엉키는 것을 방지하기 위해 사용
            if humanoid.UseJumpPower == false then
                humanoid.UseJumpPower = true
            end
        end
    end
end)

-- 노클립 토글
NoClipRightGroup:AddToggle('NoClipToggle', {
    Text = '노클립', Default = false, Tooltip = '벽 뚫기 및 충돌 무시',
    Callback = function(Value)
        CharacterSettings.NoClipEnabled = Value
        toggleNoClip(Value)
    end
})

-- ESP 토글 버튼들
EspGroup:AddToggle('MobESP_Toggle', {
    Text = '몬스터 ESP',
    Default = false,
    Tooltip = '맵의 몬스터를 하이라이트',
    Callback = function(Value)
        setMobESP(Value)
    end
})

EspGroup:AddToggle('PlayerESP_Toggle', {
    Text = '플레이어 ESP',
    Default = false, -- [cite: 299]
    Tooltip = '다른 플레이어를 하이라이트',
    Callback = function(Value)
        setPlayerESP(Value)
    end
})


-- [[ 애니메이션 관련 함수 ]]
local function getAnimFolder()
    local char = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
    local folder = char:FindFirstChild("애니메이션")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "애니메이션"
        folder.Parent = char
    end -- [cite: 301]
    return folder
end

local CurrentAnimTrack = nil

-- 애니메이션 재생 함수
local function playSelectedAnimation(animName)
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")

    local aniFolder = ReplicatedStorage:WaitForChild("Ani")
    local animObj = aniFolder:FindFirstChild(animName)

    if not animObj then
        warn("Ani 폴더에서 애니메이션을 찾을 수 없음: " .. tostring(animName))
        return
    end

    local animFolder = getAnimFolder() -- [cite: 302]
    if not animFolder:FindFirstChild(animName) then
        animObj:Clone().Parent = animFolder
    end

    if CurrentAnimTrack then
        CurrentAnimTrack:Stop()
        CurrentAnimTrack = nil
    end

    local track = animator:LoadAnimation(animObj)
    track:Play()
    CurrentAnimTrack = track
end

local function stopCurrentAnimation()
    if CurrentAnimTrack then
        CurrentAnimTrack:Stop()
        CurrentAnimTrack = nil
    else
        print("정지할 애니메이션이 없습니다.") -- [cite: 303]
    end
end

-- 애니메이션 목록
local AnimationNames = {
    "ADash","BigEle","Bite","Blast","BloodSlash","Cube","DDash","Down",
    "FastFlower","FastSlash","Flower","FlowerZen","Gas","GolemSlash",
    "GrandStamp","IceQuick","Light","Mana","OnePoint","SDash","Shock",
    "Slash","SlowSlash","Snow","Swipe","WDash","Zen","ZenZem"
}

local AnimGroup = Tabs.Character:AddRightGroupbox("애니메이션")

local SelectedAnim = AnimationNames[1]

AnimGroup:AddDropdown("AnimDropdown", {
    Values = AnimationNames,
    Default = 1,
    Multi = false,
    Text = "애니메이션 선택",
    Tooltip = "재생할 애니메이션 선택",
    Callback = function(value)
        SelectedAnim = value
    end
})

AnimGroup:AddButton({
    Text = "애니메이션 재생",
    Func = function() -- [cite: 304]
        if SelectedAnim then
            playSelectedAnimation(SelectedAnim)
        end
    end
})

AnimGroup:AddButton({
    Text = "애니메이션 정지",
    Func = function()
        stopCurrentAnimation()
    end
})

-- [[ 메뉴 키바인드 설정 (추가됨) ]]
local MenuGroup = Tabs.Settings:AddLeftGroupbox('Menu')
MenuGroup:AddButton('Unload', function() Library:Unload() end)


-- [중요] 메뉴 토글 키 설정 (기본값: End 키)
-- 마우스 버튼이 아닌 '키보드 입력'으로만 토글하려면 KeyPicker를 사용해야 합니다.
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', {
    Default = 'RightShift', 
    NoUI = true, 
    Text = 'Menu keybind' 
})

-- 라이브러리의 토글 기능을 방금 만든 키바인드와 연결
Library.ToggleKeybind = Options.MenuKeybind


-- [[ 설정 저장 및 테마 적용 ]]
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({'MenuKeybind'})
ThemeManager:SetFolder('Bgsn1-Hub')
SaveManager:SetFolder('Bgsn1-Hub/RPG')

SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- [[ 🛑 마우스 커서 수동 복구 시스템 (F4로 실행) 🛑 ]]
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local fixRunning = false -- 중복 실행 방지 변수

-- 마우스 복구 기능을 켜는 함수
local function ActivateMouseFix()
    if fixRunning then 
        -- 이미 켜져있다면 알림만 띄우고 종료
        game.StarterGui:SetCore("SendNotification", {
            Title = "Bgns1-Hub",
            Text = "이미 마우스 복구 모드가 켜져있습니다.",
            Duration = 2
        })
        return 
    end
    
    fixRunning = true
    
    -- 1. 기존에 충돌날 수 있는 GUI 정리
    for _, gui in pairs(Players.LocalPlayer.PlayerGui:GetChildren()) do
        if gui.Name == "SimpleMouseFix" or gui.Name:find("Cursor") then
            gui:Destroy()
        end
    end

    -- 2. 마우스 잠금 해제용 'Modal' 버튼 생성
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SimpleMouseFix"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 10000
    screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

    local modalBtn = Instance.new("TextButton")
    modalBtn.Name = "Unlocker"
    modalBtn.Parent = screenGui
    modalBtn.BackgroundTransparency = 1 -- 투명
    modalBtn.Text = ""
    modalBtn.Size = UDim2.new(0, 0, 0, 0)
    modalBtn.Modal = true -- 마우스 잠금 해제 핵심 속성
    modalBtn.Visible = false

    -- 3. 매 프레임마다 메뉴 상태 확인 및 마우스 제어
    RunService.RenderStepped:Connect(function()
        -- 메뉴가 열려있는지 확인
        local isMenuOpen = false
        if Library and Library.Toggled then
            isMenuOpen = true
        elseif Window and Window.Holder and Window.Holder.Visible then
            isMenuOpen = true
        end

        if isMenuOpen then
            -- 메뉴 열림: 마우스 강제 표시 및 잠금 해제
            modalBtn.Visible = true
            modalBtn.Modal = true
            UserInputService.MouseIconEnabled = true
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        else
            -- 메뉴 닫힘: 기능 끄기
            modalBtn.Visible = false
            modalBtn.Modal = false
        end
    end)
    
    -- 실행 즉시 피드백
    print("마우스 복구 시스템 가동됨!")
    game.StarterGui:SetCore("SendNotification", {
        Title = "Bgsn1-Hub",
        Text = "마우스 커서 복구됨!",
        Duration = 3
    })
end

-- 4. 키보드 입력 감지 (F4 누르면 실행)
UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == Enum.KeyCode.F4 then
        ActivateMouseFix()
    end
end)

print("Bgns1 Hub | 실행 성공")

game.StarterGui:SetCore("SendNotification", {
        Title = "Bgns1-Hub",
        Text = "Gui에서 마우스 커서가 보이지 않는다면 F4를 누르세요!",
        Duration = 5
    })
