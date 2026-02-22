-- 이 스크립트 개발에 큰 도움을 주신 누크 (nuguseyo_12)님께 감사를 드립니다
if game.Players.LocalPlayer.Character then
    game.Players.LocalPlayer.Character.Humanoid.PlatformStand = false -- 굳음 해제
end

-- [[ 게임 로딩 대기: 게임이 완전히 로드될 때까지 기다립니다 ]]
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 플레이어가 로드될 때까지 대기
repeat
    task.wait()
until LocalPlayer


-- [[ 서비스 및 기본 변수 정의 ]]
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- [[ 오토팜 설정 테이블 (수정됨) ]]
local AutoFarmConfig = {
    Enabled = false,       -- 오토팜 활성화 여부
    Distance = 0,          -- 몹과의 거리 조절
    HeightOffset = 5,      -- 몹 위에서의 높이 조절
    TargetMob = nil,       -- 공격 대상 몹 이름
    CurrentTarget = nil,   -- 현재 타겟팅 중인 몹 객체
    AutoSkillEnabled = false, -- 스킬 자동 사용 여부
    AutoClickEnabled = true,  -- [추가] 자동 클릭(물리 공격) 활성화 여부
    Skills = {E = false, R = false, T = false} -- 사용할 스킬 목록
}

-- [[ 캐릭터 설정 테이블 ]]
local CharacterSettings = {
    WalkSpeed = 16,        -- 이동 속도
    JumpPower = 50,        -- 점프력
    AntiAFKEnabled = true, -- 잠수(AFK) 방지 여부
    LoopEnabled = true,    -- 속도/점프력 유지 여부
    NoClipEnabled = false  -- 벽 통과 여부
}

local AttackDirection = "Front" -- 공격 방향 (앞, 뒤, 위, 아래)
local DirectionAngles = {Front = 0, Back = 180, Up = -90, Down = 90} -- 방향별 각도
local Mobs = Workspace:WaitForChild("Mobs") -- 몹들이 있는 폴더
local MobList, MobMap = {}, {} -- 몹 리스트 및 매핑 테이블
local AutoFarmConnection = nil -- 오토팜 루프 연결 변수
local lastAttackTime = 0 -- 마지막 공격 시간
local lastSkillTime = 0 -- 마지막 스킬 사용 시간
local LastSpawnTime = 0 -- 마지막 리스폰 시간 기록용 변수
local NoClipConnection = nil -- 노클립 루프 연결 변수
local MobDropdownObject = nil -- UI 드롭다운 객체

-- [[ 텔레포트 위치 좌표 (CFrame) ]]
local TeleportLocations = {
    ["스폰"] = CFrame.new(-152.783508, 139.910004, 1791.16602, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    ["이름 몰?루"] = CFrame.new(-5.18880367, 140.157761, 2492.52466, -0.91892904, 0.0095216129, -0.394307911, -0.0174374916, 0.997750401, 0.0647310913, 0.394037217, 0.0663590208, -0.916695774),
    ["피라미드"] = CFrame.new(-294.798401, 245, 4799.24561, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    ["무사관"] = CFrame.new(-1433.65576, 192.344635, 3796.99072, 0.712066472, 0.0192845948, 0.701847136, 3.82279977e-05, 0.99962163, -0.0275053065, -0.702112019, 0.0196124371, 0.711796343),
    ["메이플 월드"] = CFrame.new(-682.302002, 150.36142, 3476.62207, -0.758712471, 0.0163987316, 0.651219189, 4.14453643e-05, 0.999684334, -0.0251253452, -0.65142566, -0.0190359224, -0.758473635),
    ["고대사막"] = CFrame.new(-295.476227, 129.719971, 3825.25537, -0.705779552, -4.20836095e-08, -0.708431542, -2.02547241e-08, 1, -3.92250215e-08, 0.708431542, -1.33351339e-08, -0.705779552)
}

-- [[ AFK 방지 로직 ]]
-- 사용자가 20분 이상 입력이 없으면 튕기는 것을 방지하기 위해 가상 클릭 발생
if CharacterSettings.AntiAFKEnabled then
    task.spawn(function()
        while task.wait(600) do
            if CharacterSettings.AntiAFKEnabled then  -- 토글 off면 멈춤
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                    task.wait(0.15)
                    VirtualUser:ClickButton2(Vector2.new())
                    task.wait(0.15)
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            else
                break  -- off면 루프 종료
            end
        end
    end)
end

-- [추가] 캐릭터가 새로 생길 때마다 시간 기록
Players.LocalPlayer.CharacterAdded:Connect(function()
    LastSpawnTime = tick()
end)

-- 캐릭터 객체 가져오기 (없으면 대기)
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
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

-- [[ 스킬 사용 함수 (기본형으로 복구) ]]
local function fireSkill(skillKey)
    pcall(function()
        local remote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Skill")
        -- 마우스 위치 정보 없이 키값만 보냅니다 (충돌 방지)
        remote:FireServer(skillKey)
    end)
end

-- [[ 노클립(NoClip) 함수 ]]
local function toggleNoClip(enabled)
    if NoClipConnection then NoClipConnection:Disconnect() end
    if enabled then
        NoClipConnection = RunService.Stepped:Connect(function()
            local character = LocalPlayer.Character
            if character then
                for _, part in pairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    end
end

-- [[ 수정된 몹 리스트 갱신 함수 (단순화 버전) ]]
-- 까다로운 체력바 UI 검사를 제거하고, 살아있는지만 확인합니다.
local function getMobList()
    local mobsFolder = Workspace:FindFirstChild("Mobs")
    if not mobsFolder then return {}, {} end

    local processedMobs = {}
    local mobDisplayList = {}
    local mobNameMap = {}

    for _, mob in ipairs(mobsFolder:GetChildren()) do
        -- 1. 이름이 있고, 휴머노이드(체력)가 있고, 루트파트(위치)가 있는 경우만 수집
        if mob.Name and mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") then
            
            -- 이미 목록에 넣은 몹 이름은 건너뜀 (중복 방지)
            if not processedMobs[mob.Name] then
                -- 복잡한 체력 표시(["[100/100]"])를 제거하고 깔끔하게 이름만 표시
                local displayName = mob.Name 
                
                table.insert(mobDisplayList, displayName)
                mobNameMap[displayName] = mob.Name -- 표시 이름과 실제 이름을 매칭
                processedMobs[mob.Name] = true
            end
        end
    end

    table.sort(mobDisplayList)
    return mobDisplayList, mobNameMap
end

-- 초기 몹 리스트 로드
MobList, MobMap = getMobList()

-- [[ 몹 사망 여부 확인 ]]
local function isMobDead(mob)
    if not (mob and mob.Parent) then return true end
    
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    local rootPart = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("HRP")

    if not rootPart then return true end 
    if humanoid and humanoid.Health <= 0 then return true end 

    return false
end

-- [[ 타겟 몹 찾기 함수 ]]
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

-- [[ 공격 함수 (물리 클릭) ]]
local function attack()
    VirtualUser:Button1Down(Vector2.new(500, 500))
    task.wait(0.03)
    VirtualUser:Button1Up(Vector2.new(500, 500))
end

-- [[ 오토팜 위치 계산 함수 (CFrame) ]]
local function calculatePerfectCFrame(targetPos, distanceOffset, attackDirection)
    local targetRootPart = AutoFarmConfig.CurrentTarget:FindFirstChild("HumanoidRootPart") or AutoFarmConfig.CurrentTarget:FindFirstChild("HRP")
    if not targetRootPart then return CFrame.new(targetPos) end

    local npcLookDirection = targetRootPart.CFrame.LookVector
    local offsetPosition = targetRootPart.Position + (npcLookDirection * distanceOffset)
    offsetPosition = Vector3.new(offsetPosition.X, targetPos.Y, offsetPosition.Z)

    -- 위/아래 공격 모드일 경우 각도 조절, 아니면 몹을 바라보게 설정
    if attackDirection == "Up" or attackDirection == "Down" then
        local angle = DirectionAngles[attackDirection] or 0
        return CFrame.new(offsetPosition) * CFrame.Angles(math.rad(angle), 0, 0)
    else
        return CFrame.lookAt(offsetPosition, targetRootPart.Position)
    end
end


-- [[ 오토팜 시작 함수 (수정됨: 리스폰 충돌 방지 적용) ]]
local function startAutoFarm()
    -- 기존 연결 해제
    if AutoFarmConnection then 
        AutoFarmConnection:Disconnect()
        AutoFarmConnection = nil
    end

    local waitCFrame = nil -- 대기 위치 저장 변수

    AutoFarmConnection = RunService.Heartbeat:Connect(function()
        -- [[ 🛑 핵심 수정 1: 리스폰 직후 3초간 오토팜 로직 일시 정지 ]]
        -- (자동 복귀 기능이 먼저 작동할 시간을 벌어줍니다)
        if tick() - LastSpawnTime < 3 then 
            waitCFrame = nil -- 대기 위치 초기화
            return 
        end

        local character = LocalPlayer.Character
        if not character then return end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not hrp then return end

        -- 체력 없으면 타겟 및 대기위치 초기화
        if humanoid.Health <= 0 then
            AutoFarmConfig.CurrentTarget = nil
            waitCFrame = nil 
            return
        end

        -- 오토팜 꺼지면 종료
        if not AutoFarmConfig.Enabled then
            humanoid.PlatformStand = false
            waitCFrame = nil
            return
        end

        -- 타겟 몹 상태 확인
        if AutoFarmConfig.CurrentTarget and isMobDead(AutoFarmConfig.CurrentTarget) then
            AutoFarmConfig.CurrentTarget = nil
        end
        
        if not AutoFarmConfig.CurrentTarget then
            AutoFarmConfig.CurrentTarget = findTargetMob()
        end

        local currentTarget = AutoFarmConfig.CurrentTarget

        -- [[ 타겟이 없을 때 대기 로직 (좌표 오류 방지 안전장치 추가) ]] 
        if not currentTarget then
            hrp.Velocity = Vector3.new(0, 0, 0)
            
            -- [안전장치 1] 현재 내 위치가 비정상(나락/우주)이면 대기 위치로 설정하지 않음
            -- Y좌표가 -500보다 낮거나 10,000보다 높으면 오류로 판단
            if hrp.Position.Y < -500 or hrp.Position.Y > 10000 then
                waitCFrame = nil -- 잘못된 위치 저장 방지
                return -- 아무것도 하지 않고 다음 프레임까지 대기 (낙사해서 리스폰되길 기다림)
            end

            if not waitCFrame then
                -- 대기 위치가 없으면 현재 위치 위로 설정
                waitCFrame = hrp.CFrame * CFrame.new(0, 10, 0)
            
            -- [안전장치 2] 이미 저장된 대기 위치가 오류 좌표라면 즉시 폐기
            elseif waitCFrame.Position.Y < -500 or waitCFrame.Position.Y > 10000 then
                waitCFrame = nil
                return

            -- [텔레포트 감지] 사용자가 50스터드 이상 이동했으면 대기 위치 갱신
            elseif (hrp.Position - waitCFrame.Position).Magnitude > 50 then
                waitCFrame = hrp.CFrame * CFrame.new(0, 10, 0)
            end
            
            -- 위치 고정 (안전할 때만 실행됨)
            if waitCFrame then
                hrp.CFrame = waitCFrame 
            end
            return
        else
            -- 타겟을 찾으면 대기 위치 초기화
            waitCFrame = nil
        end

        -- 타겟이 있을 때 이동 로직
        local targetRootPart = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget:FindChild("HRP")
        if not targetRootPart then
            AutoFarmConfig.CurrentTarget = nil
            return
        end

        local targetPos = Vector3.new(
            targetRootPart.Position.X,
            targetRootPart.Position.Y + AutoFarmConfig.HeightOffset,
            targetRootPart.Position.Z
        )

        local finalCFrame = calculatePerfectCFrame(targetPos, AutoFarmConfig.Distance, AttackDirection)
        hrp.CFrame = finalCFrame

        pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)

        -- 공격 로직
        local currentTime = tick()
        if currentTime - lastAttackTime >= 0.08 then
            if AutoFarmConfig.AutoClickEnabled then
                attack()
            end
            lastAttackTime = currentTime
        end

        -- 스킬 로직
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
    
    local highlight = Instance.new("Highlight")
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
        storeTable[m] = nil
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
             if MobESPEnabled and mob and mob.Parent == Mobs then
                createHighlight(mob, MobHighlights, Color3.fromRGB(255, 0, 0))
            end
        end)
    else
        -- 끄면 연결 해제 및 하이라이트 삭제
        if MobChildConn then
            MobChildConn:Disconnect()
            MobChildConn = nil
        end
         clearHighlights(MobHighlights)
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
        if PlayerChildConn then PlayerChildConn:Disconnect() end
        PlayerChildConn = Players.PlayerAdded:Connect(function(plr)
            plr.CharacterAdded:Connect(function(char)
                task.wait(0.3)
                if PlayerESPEnabled then
                    createHighlight(char, PlayerHighlights, Color3.fromRGB(0, 255, 0))
                 end
            end)
        end)
        -- 캐릭터가 리스폰될 때 다시 표시
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                plr.CharacterAdded:Connect(function(char)
                    task.wait(0.3)
                     if PlayerESPEnabled then
                        createHighlight(char, PlayerHighlights, Color3.fromRGB(0, 255, 0))
                    end
                end)
            end
        end
    else
        -- 끄면 연결 해제 및 하이라이트 삭제
        if PlayerChildConn then
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
    Title = 'Bgsn1 Hub | guns.lol/bgns1',
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

-- [수정된 오토팜 토글]
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
            -- 1. 오토팜 연결 해제
            if AutoFarmConnection then
                AutoFarmConnection:Disconnect()
                AutoFarmConnection = nil
            end
            
            -- 2. 캐릭터 권한 복구 (스킬 사용 가능하게 함)
            local character = getCharacter()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local hrp = character:FindFirstChild("HumanoidRootPart")
            
            if humanoid then 
                humanoid.PlatformStand = false -- 물리 고정 해제
            end
            
            if hrp then
                hrp.Velocity = Vector3.new(0,0,0) -- 미끄러짐 방지
                pcall(function() 
                    hrp:SetNetworkOwner(LocalPlayer) -- [핵심] 캐릭터 조종 권한을 나에게 가져옴
                end)
            end
        end
    end
})

-- [[ 자동 클릭 토글 추가 ]]
AutoFarmGroup:AddToggle('AutoClickToggle', {
    Text = '자동 클릭 (물리 공격)',
    Default = true, -- 기본값 켜짐
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
        MobMap = newMobMap
        if MobDropdownObject and MobDropdownObject.SetValues then
            local newValues = (#MobList > 0 and MobList) or {"몹 없음"}
            MobDropdownObject:SetValues(newValues)
        end
    end
})

-- [[ 수정된 몹 선택 드롭다운 ]]
MobDropdownObject = AutoFarmGroup:AddDropdown('MobDropdown', {
    Values = (#MobList > 0 and MobList) or {"몹 없음"},
    Default = 1,
    Multi = false,
    Text = '적 선택',
    Tooltip = '공격할 몹을 선택하세요',
    Callback = function(Value)
        -- 1. 맵핑된 이름이 있으면 그것을 사용 (일반적인 경우)
        if MobMap[Value] then
            AutoFarmConfig.TargetMob = MobMap[Value]
        else
            -- 2. 맵핑이 안 되어 있다면 선택한 값 자체를 이름으로 사용 (비상 대책)
            AutoFarmConfig.TargetMob = Value
        end
        
        -- 타겟을 바꿨으니 현재 잡고 있던 타겟 초기화
        AutoFarmConfig.CurrentTarget = nil
        
        -- 디버깅용 출력 (F9 콘솔에서 확인 가능)
        print("타겟 설정됨: " .. tostring(AutoFarmConfig.TargetMob))
    end
})



-- 스킬 사용 토글
AutoFarmGroup:AddToggle('AutoSkillToggle', {
    Text = '오토스킬 (오토팜 연동)',
    Default = false,
    Tooltip = '오토팜 켜져있을 때만 E/R/T 스킬 자동 발사 (2초 쿨다운)',
    Callback = function(Value)
        AutoFarmConfig.AutoSkillEnabled = Value
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
         AutoFarmConfig.Skills.T = Value
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
    Rounding = 1,
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

-- [[ 💊 아이템 자동 사용 (퀵바 1~3번) ]] --
local ItemGroup = Tabs.Main:AddLeftGroupbox('아이템 자동 사용')
local VirtualInputManager = game:GetService("VirtualInputManager")

-- 아이템 설정 저장 변수
local AutoItemConfig = {
    Slot1 = { Enabled = false, Delay = 1 },
    Slot2 = { Enabled = false, Delay = 1 },
    Slot3 = { Enabled = false, Delay = 1 }
}

-- [함수] 키보드 누름 시뮬레이션
local function simulateKeyPress(keyCode)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.05) -- 살짝 눌렀다 떼는 느낌
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)
end

-- ==============================
-- [1번 퀵바 설정]
-- ==============================
ItemGroup:AddToggle('AutoItem1_Toggle', {
    Text = '1번 퀵바 자동 사용',
    Default = false,
    Tooltip = '키보드 숫자 1번을 자동으로 누릅니다.',
    Callback = function(Value)
        AutoItemConfig.Slot1.Enabled = Value
    end
})

ItemGroup:AddSlider('AutoItem1_Delay', {
    Text = '1번 사용 딜레이 (초)',
    Default = 5,
    Min = 0,
    Max = 30,
    Rounding = 1, -- 0.1 단위 조절
    Callback = function(Value)
        AutoItemConfig.Slot1.Delay = Value
    end
})

-- 1번 슬롯 작동 루프
task.spawn(function()
    while true do
        if AutoItemConfig.Slot1.Enabled then
            simulateKeyPress(Enum.KeyCode.One) -- 숫자 1 입력
            -- 딜레이만큼 대기 (최소 0.1초 안전장치)
            local waitTime = math.max(0.1, AutoItemConfig.Slot1.Delay)
            task.wait(waitTime)
        else
            task.wait(1) -- 꺼져있을 땐 1초 대기
        end
    end
end)


-- ==============================
-- [2번 퀵바 설정]
-- ==============================
ItemGroup:AddToggle('AutoItem2_Toggle', {
    Text = '2번 퀵바 자동 사용',
    Default = false,
    Tooltip = '키보드 숫자 2번을 자동으로 누릅니다.',
    Callback = function(Value)
        AutoItemConfig.Slot2.Enabled = Value
    end
})

ItemGroup:AddSlider('AutoItem2_Delay', {
    Text = '2번 사용 딜레이 (초)',
    Default = 5,
    Min = 0,
    Max = 30,
    Rounding = 1,
    Callback = function(Value)
        AutoItemConfig.Slot2.Delay = Value
    end
})

-- 2번 슬롯 작동 루프
task.spawn(function()
    while true do
        if AutoItemConfig.Slot2.Enabled then
            simulateKeyPress(Enum.KeyCode.Two) -- 숫자 2 입력
            local waitTime = math.max(0.1, AutoItemConfig.Slot2.Delay)
            task.wait(waitTime)
        else
            task.wait(1)
        end
    end
end)


-- ==============================
-- [3번 퀵바 설정]
-- ==============================
ItemGroup:AddToggle('AutoItem3_Toggle', {
    Text = '3번 퀵바 자동 사용',
    Default = false,
    Tooltip = '키보드 숫자 3번을 자동으로 누릅니다.',
    Callback = function(Value)
        AutoItemConfig.Slot3.Enabled = Value
    end
})

ItemGroup:AddSlider('AutoItem3_Delay', {
    Text = '3번 사용 딜레이 (초)',
    Default = 5,
    Min = 0,
    Max = 30,
    Rounding = 1,
    Callback = function(Value)
        AutoItemConfig.Slot3.Delay = Value
    end
})

-- 3번 슬롯 작동 루프
task.spawn(function()
    while true do
        if AutoItemConfig.Slot3.Enabled then
            simulateKeyPress(Enum.KeyCode.Three) -- 숫자 3 입력
            local waitTime = math.max(0.1, AutoItemConfig.Slot3.Delay)
            task.wait(waitTime)
        else
            task.wait(1)
        end
    end
end)

-- [[ 타이머 그룹박스 (Main 탭 우측) ]]
local SpawnerMobGroup = Tabs.Main:AddRightGroupbox('타이머')

-- 고정된 보스/몹 리스트
local FixedSpawnerMobs = {
    "갑옷 고블린",
    "겨울성의 수호신",
    "고블린",
    "나락화 박쥐",
    "나락화 수호자",
    "눈사람",
    "동굴 골렘",
    "마그마 블래스터",
    "무사",
    "미라",
    "샌드 슬라임",
    "선혈의 사무라이",
    "슬라임",
    "예티",
    "용암 골렘",
    "타이탄 아머로드",
    "파괴의 광선, 인큐네이션",
    "피라미드 수호자",
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
    local timerUI = Instance.new("ScreenGui")
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
    local corner = Instance.new("UICorner")
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
    mobNameLabel.Font = Enum.Font.GothamBold
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
    progressCorner.Parent = progressBg
    
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
    timeLabel.Parent = mainFrame
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
    closeBtn.Size = UDim2.new(0, 20, 0, 20)
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
         if not spawner then
            timeLabel.Text = "Spawner 없음"
            progressBar.Size = UDim2.new(0, 0, 1, 0)
            return
        end
        
        local mobFolder = spawner:FindFirstChild(mobName)
        local coolObj = mobFolder and mobFolder:FindFirstChild("Cool")
        local coolTimeObj = mobFolder and mobFolder:FindFirstChild("CoolTime")
        
        if not mobFolder or not coolObj or not coolTimeObj then
            timeLabel.Text = "스폰 대기 중..."
            progressBar.Size = UDim2.new(0, 0, 1, 0)
            progressBar.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
            return
        end
        
        -- 쿨타임 계산
        local currentCool = coolObj.Value or 0
        local baseCoolTime = coolTimeObj.Value or 30
        local displayedCoolTime = baseCoolTime + EXTRA_TIME
        local remaining = displayedCoolTime - currentCool
        local progress = math.max(0, math.min(1, currentCool / displayedCoolTime))
        
        if remaining <= 0 then
             timeLabel.Text = "스폰 가능!"
            progressBar.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
        else
            timeLabel.Text = string.format("남은 시간: %.1f / %d초", remaining, displayedCoolTime)
            progressBar.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
        end
        
        progressBar.Size = UDim2.new(progress, 0, 1, 0)
    end
    
    local updateConnection = game:GetService("RunService").Heartbeat:Connect(updateThisTimer)
    
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
             AutoFarmConfig.TargetMob = SpawnerMobMap[Value]
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
                 Title = "알림";
                Text = "먼저 몹을 선택해주세요!";
                Duration = 3;
            })
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
         for _, ui in ipairs(TimerUIs) do
            if ui then ui:Destroy() end
        end
        TimerUIs = {}
        UpdateConnections = {}
    end,
    Tooltip = '화면의 모든 타이머 UI 제거'
})

-- [[ 매크로 방지 우회 (V11: 랜덤 키패드 완벽 대응 - Text로 버튼 탐색) ]]
local MacroGroup = Tabs.Main:AddRightGroupbox('매크로 방지 우회')
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local AntiMacroEnabled = false

-- [[ 3초 ~ 4초 랜덤 딜레이 함수 ]] --
local function randomActionWait()
    local delay = math.random(300, 400) / 100 -- 3.00 ~ 4.00초 사이 난수 생성
    task.wait(delay)
end

MacroGroup:AddToggle('AntiMacroToggle', {
    Text = '매크로 방지 자동 우회',
    Default = false,
    Tooltip = '마우스 움직임으로 매크로 방지 우회 (느림)',
    Callback = function(Value)
        AntiMacroEnabled = Value
    end
})

-- GUI 요소 클릭 함수 (Topbar 동적 보정)
local function clickGuiObject(obj)
    if not obj or not obj.Visible or not obj.Active then return end
    
    local pos = obj.AbsolutePosition
    local size = obj.AbsoluteSize
    local topbarInset = GuiService:GetGuiInset().Y
    
    local x = pos.X + (size.X / 2)
    local y = pos.Y + (size.Y / 2) + topbarInset

    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait(0.05) -- 클릭 자체의 지속 시간은 짧게 유지 (드래그 판정 방지)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
end

-- 특정 숫자 버튼 찾기 (Text로 검색)
local function findDigitButton(keyFrame, digit)
    for _, btn in ipairs(keyFrame:GetChildren()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Text == digit then
            return btn
        end
    end
    return nil
end

task.spawn(function()
    while true do
        task.wait(1)
        
        if AntiMacroEnabled then
            pcall(function()
                local player = game.Players.LocalPlayer
                local gui = player.PlayerGui:FindFirstChild("MacroGui")
                
                if gui and gui.Enabled then
                    local rootFrame = gui:FindFirstChild("Frame") or gui:FindFirstChild("MacroClient") or gui
                    if not rootFrame then return end
                    
                    local displayFrame = rootFrame:FindFirstChild("Frame")
                    local keyFrame = rootFrame:FindFirstChild("KeyInputFrame")
                    local resetFrame = rootFrame:FindFirstChild("KeyReset")
                    
                    if displayFrame and keyFrame then
                        local inputLabel = displayFrame:FindFirstChild("Input") or displayFrame:FindFirstChildWhichIsA("TextLabel")
                        local outputBox = displayFrame:FindFirstChild("TextBox")
                        
                        if inputLabel and outputBox then
                            local targetNum = inputLabel.Text:match("%d%d%d%d")
                            
                            if targetNum and outputBox.Text ~= targetNum then
                                Library:Notify("매크로 감지! 목표: " .. targetNum)
                                
                                -- 1단계: TextBox 클릭해서 키패드 열기 + 포커스
                                if not keyFrame.Visible then
                                    randomActionWait() -- [행동 전 딜레이]
                                    clickGuiObject(outputBox)
                                end
                                
                                -- 2단계: 리셋으로 입력창 비우기
                                local resetBtn = resetFrame and resetFrame:FindFirstChild("TextButton")
                                if resetBtn then
                                    for i = 1, 5 do
                                        if outputBox.Text == "" then break end
                                        randomActionWait() -- [행동 전 딜레이]
                                        clickGuiObject(resetBtn)
                                    end
                                end
                                
                                -- 3단계: 숫자 입력 (Text로 버튼 찾아 클릭)
                                if outputBox.Text == "" then
                                    for i = 1, #targetNum do
                                        local digit = string.sub(targetNum, i, i)
                                        local btn = findDigitButton(keyFrame, digit)
                                        
                                        if btn then
                                            randomActionWait() -- [행동 전 딜레이] 버튼 누르기 전에 대기
                                            clickGuiObject(btn)
                                        else
                                            warn("숫자 버튼 못 찾음: " .. digit)
                                        end
                                    end
                                    print("입력 완료: " .. targetNum)
                                end
                                
                                task.wait(2.5) -- 모든 입력이 끝나고 매크로 창이 닫힐 때까지 대기
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- [[ ⚡ 매크로 방지 우회 V12 (신호 강제형) ]] --
-- 좌표 계산 없이 스크립트 신호를 직접 실행합니다. (getconnections 지원 필수)

local AntiMacroSignalEnabled = false

-- 1. 토글 생성
MacroGroup:AddToggle('AntiMacroSignalToggle', {
    Text = '매크로 방지 V12 (신호 강제)',
    Default = false,
    Tooltip = 'v11보다 더 좋은.',
    Callback = function(Value)
        AntiMacroSignalEnabled = Value
        if Value then
            Library:Notify("V12 모드 활성화: 신호 강제 방식 (행동 전 딜레이)")
        end
    end
})

-- 2. 핵심 함수: 버튼 강제 실행
local function fireButtonSignal(btn)
    if not btn or not btn.Active or not btn.Visible then return end
    
    if getconnections then
        local events = {
            btn.MouseButton1Click,
            btn.MouseButton1Down,
            btn.Activated
        }
        
        for _, event in ipairs(events) do
            for _, connection in ipairs(getconnections(event)) do
                connection:Fire()
            end
        end
    end
end

-- 버튼 찾기 헬퍼
local function findDigitButtonV12(keyFrame, digit)
    for _, btn in ipairs(keyFrame:GetChildren()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Name == digit then
            return btn
        end
    end
    return nil
end

-- 3. 감지 및 우회 루프
task.spawn(function()
    while true do
        task.wait(1)
        
        if AntiMacroSignalEnabled then
            pcall(function()
                local player = game:GetService("Players").LocalPlayer
                if not player then return end

                local gui = player.PlayerGui:FindFirstChild("MacroGui")
                if gui and gui.Enabled then
                    
                    local rootFrame = gui:FindFirstChild("Frame")
                    if not rootFrame then return end
                    
                    local displayFrame = rootFrame:FindFirstChild("Frame")
                    local keyFrame = rootFrame:FindFirstChild("KeyInputFrame")
                    local resetFrame = rootFrame:FindFirstChild("KeyReset")
                    
                    if displayFrame and keyFrame then
                        local inputLabel = displayFrame:FindFirstChild("Input")
                        local outputBox = displayFrame:FindFirstChild("TextBox")
                        
                        if inputLabel and outputBox then
                            -- 4자리 숫자 패턴 추출
                            local targetNum = inputLabel.Text:match("%d%d%d%d")
                            
                            -- 입력해야 할 상황이면
                            if targetNum and outputBox.Text ~= targetNum then
                                
                                Library:Notify("매크로 감지 (V12): " .. targetNum)
                                print("V12 신호 강제 입력 시도: " .. targetNum)

                                -- 1. 키패드 열기 (TextBox 강제 신호 발송)
                                if not keyFrame.Visible then
                                    randomActionWait() -- [행동 전 딜레이]
                                    fireButtonSignal(outputBox)
                                end

                                -- 2. 초기화 (Reset)
                                local resetBtn = resetFrame and resetFrame:FindFirstChild("TextButton")
                                if resetBtn then
                                    for i = 1, 5 do
                                        if outputBox.Text == "" then break end
                                        randomActionWait() -- [행동 전 딜레이]
                                        fireButtonSignal(resetBtn)
                                    end
                                end

                                -- 3. 숫자 입력 (Signal Fire)
                                if outputBox.Text == "" then
                                    for i = 1, #targetNum do
                                        local digit = string.sub(targetNum, i, i)
                                        local btn = findDigitButtonV12(keyFrame, digit)
                                        
                                        if btn then
                                            randomActionWait() -- [행동 전 딜레이] 신호를 보내기 전에 대기
                                            fireButtonSignal(btn) -- 좌표 없이 즉시 실행
                                        end
                                    end
                                    print("V12 입력 완료: " .. targetNum)
                                end
                                
                                task.wait(2.5) -- 완료 후 안정화 대기
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- [[ 💾 위치 저장 및 자동 복귀 (양방향 동기화 버전) ]]
local SavePosGroup = Tabs.Main:AddRightGroupbox('위치 저장')

local SavedPosition = nil -- 저장된 CFrame
local AutoTpOnDeath = false
local PosInputObject = nil -- 텍스트 박스 객체를 담을 변수

-- 1. [입력창] 좌표 직접 수정 & 표시
-- (버튼보다 먼저 정의하거나, 변수에 담아둬야 버튼에서 제어 가능)
PosInputObject = SavePosGroup:AddInput('ManualPosInput', {
    Default = '',
    Text = '저장된 좌표',
    Placeholder = '예: 100, 50, -200',
    Callback = function(Value)
        -- 사용자가 키보드로 입력했을 때 작동
        local x, y, z = Value:match("([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)")
        if x and y and z then
            SavedPosition = CFrame.new(tonumber(x), tonumber(y), tonumber(z))
            -- (선택사항) 입력 후 알림이 너무 자주 뜨면 귀찮으니 로그만 남김
            print("좌표 수동 업데이트됨:", x, y, z)
        end
    end
})

-- 2. [버튼] 현재 위치 저장 (누르면 위의 입력창 값이 바뀜)
SavePosGroup:AddButton({
    Text = '현재 위치 가져오기',
    Func = function()
        local p = game.Players.LocalPlayer
        if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            -- 1. 현재 위치 저장
            SavedPosition = p.Character.HumanoidRootPart.CFrame
            local pos = SavedPosition.Position
            
            -- 2. 좌표를 보기 좋게 문자열로 변환 (소수점 1자리까지)
            local posString = string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
            
            -- 3. [핵심] 텍스트 박스의 값을 강제로 변경!
            if PosInputObject then
                PosInputObject:SetValue(posString)
            end
            
            Library:Notify("현재 위치를 가져왔습니다.")
        else
            Library:Notify("캐릭터를 찾을 수 없습니다.")
        end
    end,
    Tooltip = '현재 내 위치를 가져와서 입력칸에 채워넣습니다.'
})

-- 3. [토글] 죽으면 자동 복귀
SavePosGroup:AddToggle('AutoTpToggle', {
    Text = '죽으면 자동 복귀',
    Default = false,
    Tooltip = '켜두면 리스폰 시 위 좌표로 이동합니다.',
    Callback = function(Value)
        AutoTpOnDeath = Value
    end
})

-- 4. 자동 복귀 로직
game.Players.LocalPlayer.CharacterAdded:Connect(function(newChar)
    if AutoTpOnDeath and SavedPosition then
        task.wait(1.2) -- 로딩 대기
        local hrp = newChar:WaitForChild("HumanoidRootPart", 10)
        if hrp then
            hrp.CFrame = SavedPosition
        end
    end
end)


--===================================================
-- 회피
--===================================================

--[[
    [자동 회피 스크립트]
    기능 1: 몹의 공격 모션(평타)을 감지하여 순간적으로 회피
    기능 2: 바닥의 위험 구역(빨간 장판)을 감지하여 회피
    회피 방식: 캐릭터의 히트박스를 순간적으로 지하로 내렸다가 올리는 방식 (화면상으로는 변화가 없어 보임)
]]

-- 상태 변수 및 설정값 초기화
local HitAnimToggle = false       -- 평타 회피 켜기/끄기
local RedPartToggle = false       -- 장판(스킬) 회피 켜기/끄기
local noclipActive = false        -- 현재 회피 동작(노클립/무적) 수행 중인지 여부
local InvisibleState = false      -- 캐릭터 반투명 상태 여부
local attackingMobs = {}          -- 현재 나를 공격 중인 몹 목록
local insideRedPart = false       -- 현재 빨간 장판 위에 있는지 여부
local RedReleaseDelay = 1.0       -- 장판에서 벗어난 후에도 회피를 유지할 시간 (초)
local connections = {}            -- 기능 해제 시 연결을 끊기 위해 이벤트들을 저장하는 테이블

-- 기본 서비스 및 플레이어 참조
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer
local MOBS = Workspace:WaitForChild("Mobs") -- 몹들이 들어있는 폴더

local character, humanoid, root, bodyParts = nil, nil, nil, {}

-- 감지할 몹 리스트 (이 이름들에 해당하는 몹만 평타 회피 작동)
local VALID_MOBS = {
    ["갑옷 고블린"] = true,
    ["겨울성의 수호신"] = true,
    ["고블린"] = true,
    ["나락화 박쥐"] = true,
    ["나락화 수호자"] = true,
    ["눈사람"] = true,
    ["동굴 골렘"] = true,
    ["마그마 블래스터"] = true,
    ["무사"] = true,
    ["미라"] = true,
    ["샌드 슬라임"] = true,
    ["선혈의 사무라이"] = true,
    ["슬라임"] = true,
    ["예티"] = true,
    ["용암 골렘"] = true,
    ["타이탄 아머로드"] = true,
    ["파괴의 광선, 인큐네이션"] = true,
    ["피라미드 수호자"] = true,
}

-- 캐릭터의 HumanoidRootPart(중심점) 가져오기
local function getHRP()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- 캐릭터가 다시 태어날 때마다 변수 및 신체 부위 재설정
local function setupCharacter()
    character = lp.Character or lp.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    
    bodyParts = {}
    -- 회피 시 반투명하게 만들 신체 부위들을 수집 (RootPart 제외)
    for _, v in pairs(character:GetDescendants()) do
        if v:IsA("BasePart") and v ~= root then
            table.insert(bodyParts, v)
        end
    end
end

-- 회피 중일 때 캐릭터를 반투명하게 설정하는 함수 (시각적 효과)
local function setInvisible(on)
    if on == InvisibleState then return end
    InvisibleState = on
    
    for _, p in pairs(bodyParts) do
        pcall(function() p.Transparency = on and 0.5 or 0 end)
    end
end

-- 초기 캐릭터 셋업 및 리스폰 감지
setupCharacter()
table.insert(connections, lp.CharacterAdded:Connect(function()
    task.wait(1)
    setupCharacter()
end))

-- 기능(토글)을 껐을 때 모든 이벤트 연결 해제 및 상태 초기화
local function cleanupAll()
    for i = #connections, 1, -1 do
        local conn = connections[i]
        pcall(function() conn:Disconnect() end)
        table.remove(connections, i)
    end
    
    attackingMobs = {}
    insideRedPart = false
    noclipActive = false
    InvisibleState = false
    
    -- 캐릭터 투명도 원상복구
    for _, p in pairs(bodyParts) do 
        pcall(function() p.Transparency = 0 end)
    end
end

-- UI 그룹 생성 (UI 라이브러리에 따라 다를 수 있음)
local EvadeGroup = Tabs.Main:AddRightGroupbox('자동 회피')

-- -----------------------------------------------------------
-- [1] 평타 회피 기능 (Mob Hit Animation Detection)
-- -----------------------------------------------------------
EvadeGroup:AddToggle('HitAnimToggle', {
    Text = '평타 회피',
    Default = false,
    Tooltip = 'Hit 애니메이션 감지',
    Callback = function(Value)
        HitAnimToggle = Value
        
        if Value then
            local HIT_ANIM_IDS = {}
            
            -- 몹들의 "Hit" 애니메이션 ID를 수집하는 함수
            local function updateHitAnimIds()
                HIT_ANIM_IDS = {}
                for _, mob in ipairs(MOBS:GetChildren()) do
                    if VALID_MOBS[mob.Name] then
                        local hitAnim = mob:FindFirstChild("Hit", true)
                        if hitAnim and hitAnim:IsA("Animation") then
                            HIT_ANIM_IDS[hitAnim.AnimationId] = true
                        end
                    end
                end
            end
            updateHitAnimIds()

            local hooked = {} -- 중복 연결 방지용 테이블

            -- 각 몹의 휴머노이드에 애니메이션 감지 이벤트를 연결하는 함수
            local function hookAnimator(humanoid, mobRoot)
                if hooked[humanoid] then return end
                hooked[humanoid] = true

                local animator = humanoid:FindFirstChildOfClass("Animator")
                if not animator then return end

                -- 몹이 죽으면 공격 목록에서 제거
                table.insert(connections, humanoid.Died:Connect(function()
                    attackingMobs[mobRoot] = nil
                end))

                -- 몹이 사라지면(Despawn) 공격 목록에서 제거
                table.insert(connections, mobRoot.AncestryChanged:Connect(function(_, parent)
                    if not parent then
                        attackingMobs[mobRoot] = nil
                    end
                end))

                -- 핵심: 몹이 애니메이션을 재생할 때 감지
                table.insert(connections, animator.AnimationPlayed:Connect(function(track)
                    local anim = track.Animation
                    -- 재생된 애니메이션이 "공격(Hit)" 애니메이션인지 확인
                    if not anim or not HIT_ANIM_IDS[anim.AnimationId] then return end

                    local hrp = getHRP()
                    if not hrp then return end

                    -- 내 캐릭터와 몹 사이의 거리가 25스터드 이내일 때만 회피 발동
                    if (hrp.Position - mobRoot.Position).Magnitude <= 25 then
                        attackingMobs[mobRoot] = true
                        setInvisible(true) -- 시각적 알림
                        noclipActive = true -- 회피 시작

                        -- 애니메이션이 끝나면 회피 종료
                        track.Stopped:Once(function()
                            attackingMobs[mobRoot] = nil
                        end)
                    end
                end))
            end

            -- 전체 몹 스캔 및 이벤트 연결
            local function scanMobs()
                for _, mob in ipairs(MOBS:GetChildren()) do
                    if VALID_MOBS[mob.Name] then
                        local hum = mob:FindFirstChildOfClass("Humanoid")
                        local rootPart = mob:FindFirstChild("HumanoidRootPart")
                        if hum and rootPart then
                            hookAnimator(hum, rootPart)
                        end
                    end
                end
            end

            scanMobs()
            -- 새로운 몹이 스폰될 때마다 감지 목록 갱신
            table.insert(connections, MOBS.ChildAdded:Connect(function()
                task.wait()
                updateHitAnimIds()
                scanMobs()
            end))
        else
            -- 토글 끄면 정리
            cleanupAll()
        end
    end
})

-- -----------------------------------------------------------
-- [2] 스킬 회피 기능 (Red Part Detection)
-- -----------------------------------------------------------
EvadeGroup:AddToggle('RedPartToggle', {
    Text = '스킬 회피',
    Default = false,
    Tooltip = '빨간 파트 감지',
    Callback = function(Value)
        RedPartToggle = Value
        
        if Value then
            local redAttackParts = {}
            
            -- 해당 파트가 "공격용 빨간 장판"인지 판별하는 함수
            local function isRedAttackPart(part)
                if not part:IsA("BasePart") then return false end
                if part.Transparency >= 0.8 then return false end -- 너무 투명하면 무시
                local c = part.Color
                -- 색상이 붉은 계열인지 확인 (R값 높음, G/B값 낮음)
                return c.R >= 0.6 and c.G < 0.4 and c.B < 0.4
            end

            -- 맵 전체에서 빨간 파트 찾기
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if isRedAttackPart(obj) then 
                    redAttackParts[obj] = true 
                end
            end

            -- 새로 생기는 파트 감지 (스킬 시전 시 생성되는 파트)
            table.insert(connections, Workspace.DescendantAdded:Connect(function(obj)
                if isRedAttackPart(obj) then 
                    redAttackParts[obj] = true 
                end
            end))

            -- 사라지는 파트 목록에서 제거
            table.insert(connections, Workspace.DescendantRemoving:Connect(function(obj)
                redAttackParts[obj] = nil
            end))

            local lastRedHitTime = 0
            local RED_CHECK_INTERVAL = 0 -- 매 프레임 체크 (필요시 값 조절 가능)
            local lastRedCheck = 0

            -- 주기적으로 내가 빨간 파트 위에 있는지 검사
            table.insert(connections, RunService.Heartbeat:Connect(function()
                if not root or not humanoid then return end
                local now = tick()
                
                if now - lastRedCheck >= RED_CHECK_INTERVAL then
                    lastRedCheck = now
                    local pos = root.Position
                    local hitRed = false
                    
                    -- 등록된 모든 빨간 파트와 거리/범위 체크
                    for part, _ in pairs(redAttackParts) do
                        if part.Parent and (part.Position - pos).Magnitude <= 60 then
                            local localPos = part.CFrame:PointToObjectSpace(pos)
                            local half = part.Size * 0.5
                            -- 내 위치가 파트의 크기(박스) 안에 들어와 있는지 확인
                            if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z then
                                hitRed = true
                                break
                            end
                        end
                    end
                    
                    if hitRed then
                        lastRedHitTime = now
                        if not insideRedPart then
                            insideRedPart = true
                            setInvisible(true)
                            noclipActive = true -- 회피 시작
                        end
                    else
                        -- 장판에서 벗어났어도 설정한 딜레이(RedReleaseDelay)만큼 더 회피 유지
                        if insideRedPart and (now - lastRedHitTime) >= RedReleaseDelay then
                            insideRedPart = false
                        end
                    end
                end
            end))
        else
            cleanupAll()
        end
    end
})

EvadeGroup:AddSlider('RedReleaseSlider', {
    Text = '스킬 회피 유지 시간',
    Default = 1.0,
    Min = 0,
    Max = 10,
    Rounding = 1,
    Tooltip = '빨간 파트 감지 후 회피 유지시간',
    Callback = function(Value)
        RedReleaseDelay = Value
    end
})

-- -----------------------------------------------------------
-- [3] 메인 루프: 실제 회피 동작 수행 (좌표 이동)
-- -----------------------------------------------------------
table.insert(connections, RunService.Heartbeat:Connect(function()
    if not root or not humanoid then return end
    
    -- 유효하지 않은 몹(사라짐 등) 정리
    for mobRoot in pairs(attackingMobs) do
        if not mobRoot or not mobRoot.Parent or not mobRoot:IsDescendantOf(workspace) then
            attackingMobs[mobRoot] = nil
        end
    end

    -- 회피가 필요한 상황인지 종합 판단
    local shouldBeInvisible = (HitAnimToggle and next(attackingMobs) ~= nil) or (RedPartToggle and insideRedPart)
    
    -- 회피 상황이 끝났으면 상태 복구
    if InvisibleState and not shouldBeInvisible then
        setInvisible(false)
        noclipActive = false
    end
    
    -- [핵심 회피 로직]
    -- noclipActive가 켜져 있으면 캐릭터의 히트박스를 땅 밑으로 내림
    if noclipActive and root and humanoid then
        local oldCF = root.CFrame
        local oldOffset = humanoid.CameraOffset

        -- 캐릭터를 지하 50스터드로 이동 (공격을 피하기 위함)
        local downCF = oldCF * CFrame.new(0, -50, 0)
        
        -- 카메라는 원래 위치에 고정 (화면이 덜컹거리지 않게 보정)
        local camOffset = downCF:ToObjectSpace(CFrame.new(oldCF.Position)).Position

        root.CFrame = downCF
        humanoid.CameraOffset = camOffset
        
        -- 한 프레임 대기 (서버가 내가 지하에 있다고 인식하게 함)
        RunService.RenderStepped:Wait()
        
        -- 다시 원래 위치로 복귀 (매우 빠르게 일어나서 눈에는 안 보임)
        root.CFrame = oldCF
        humanoid.CameraOffset = oldOffset
    end
end))

-- [[ 텔레포트 그룹 (Teleport 탭) ]]
local LunaVillageGroup = Tabs.Teleport:AddRightGroupbox('스폰포인트')

-- 스폰 포인트 이동 버튼들
-- 작동 원리: 
-- 1. 해당 위치로 이동 
-- 2. ProximityPrompt(상호작용 키) 강제 발동
-- 3. (옵션) 원래 위치로 복귀
LunaVillageGroup:AddButton({
    Text = '루나마을 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

         local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(-50.4700165, 136.039993, 1992.54004, 1, 0, 0, 0, 1, 0, 0, 0, 1)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["루나마을 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

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

LunaVillageGroup:AddButton({
    Text = '겨울성 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(2177.99341, 378.901886, 4562.57129, 0.399358451, 0, 0.916794896, 0, 1, 0, -0.916794896, 0, 0.399358451)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["겨울성 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

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

LunaVillageGroup:AddButton({
    Text = '겨울 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(331.624847, 192.511246, 3749.88232, 1, 0, 0, 0, 1, 0, 0, 0, 1)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["겨울 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
        end)

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

LunaVillageGroup:AddButton({
    Text = '메이플 스폰',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local originalCFrame = root.CFrame

        local targetCFrame = CFrame.new(-1433.6543, 199.052856, 3796.99219, -1, 0, 0, 0, 1, 0, 0, 0, -1)

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.SpawnPoint["메이플 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt")
         end)

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

-- 2세계 텔레포트 버튼
LunaVillageGroup:AddButton({
    Text = '2세계 텔레포트',
    Func = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local root = character:WaitForChild("HumanoidRootPart")

        local targetCFrame = CFrame.new(
            -36.1729698, 150.903793, -2374.63696,
            4.59551811e-05, 1.87382102e-06, -0.99999994,
             0.0814801306, -0.996674895, 1.87382102e-06,
            -0.996674955, -0.0814801306, -4.58955765e-05
        )

        root.CFrame = targetCFrame
        task.wait(0.5)

        local prompt
        pcall(function()
            prompt = workspace.Map.Teleport["World2"]:FindFirstChildOfClass("ProximityPrompt")
        end)

        if prompt then
             local backup = prompt.HoldDuration
            prompt.HoldDuration = 0
            task.wait(0.05)
            fireproximityprompt(prompt)
            prompt.HoldDuration = backup
        end
    end
})

-- [[ 텔레포트 버튼 (미리 정의된 좌표) ]]
local TeleportGroup = Tabs.Teleport:AddLeftGroupbox('텔레포트 위치')
TeleportGroup:AddButton({ Text = '스폰', Func = function() teleportTo("스폰") end })
TeleportGroup:AddButton({ Text = '이름 몰?루', Func = function() teleportTo("이름 몰?루") end })
TeleportGroup:AddButton({ Text = '피라미드', Func = function() teleportTo("피라미드") end })
TeleportGroup:AddButton({ Text = '무사관', Func = function() teleportTo("무사관") end })
TeleportGroup:AddButton({ Text = '메이플 월드', Func = function() teleportTo("메이플 월드") end })
TeleportGroup:AddButton({ Text = '고대사막', Func = function() teleportTo("고대사막") end })



local ScriptGroup = Tabs.Misc:AddRightGroupbox('스크립트')
-- Infinite Yield 실행 (유명한 관리자 명령어 스크립트)
ScriptGroup:AddButton({
    Text = '인피니티 야드',
    Func = function()
        loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source', true))()
    end
})

-- [[ 캐릭터 스킨 변경 그룹 (Main 탭) ]]
local SkinChangerGroup = Tabs.Misc:AddRightGroupbox('캐릭터 체인저')
local SkinUserIdBox = nil

SkinChangerGroup:AddInput('SkinUserIdInput', {
    Default = "",
    Numeric = true,
    Text = 'UserId 입력',
    Tooltip = '변장할 계정의 UserId 입력',
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
         })
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
            Text = "외형 로드 실패: " .. tostring(userIdNum),
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
        or inst:IsA("ShirtGraphic") then
            inst:Destroy()
        end
    end

    -- 머리 메시 제거
    local head = character:FindFirstChild("Head")
    if head then
        for _, inst in ipairs(head:GetChildren()) do
            if inst:IsA("SpecialMesh") and inst:GetAttribute("FromMorph") == true then
                inst:Destroy()
             end
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

         elseif inst:IsA("Accessory") then
            inst.Name = "#ACCESSORY_" .. inst.Name
            inst.Parent = character

        elseif inst:IsA("SpecialMesh") and head then
            inst:SetAttribute("FromMorph", true)
            inst.Parent = head

        elseif inst.Name == "R6" and character:FindFirstChildOfClass("Humanoid").RigType == Enum.HumanoidRigType.R6 then
            local cm = inst:FindFirstChildOfClass("CharacterMesh")
            if cm then cm.Parent = character end

        elseif inst.Name == "R15" and character:FindFirstChildOfClass("Humanoid").RigType == Enum.HumanoidRigType.R15 then
            local cm = inst:FindFirstChildOfClass("CharacterMesh")
            if cm then cm.Parent = character end
        end
    end

    -- 얼굴 적용
    if head then
        local faceInModel = appearanceModel:FindFirstChild("face")
        if faceInModel then
            faceInModel.Parent = head
        else
            local decal = Instance.new("Decal")
            decal.Face = Enum.NormalId.Front
            decal.Name = "face"
            decal.Texture = "rbxasset://textures/face.png"
            decal.Parent = head
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
    Text = '캐릭터 체인지',
    Func = function()
        applyDisguiseByUserId(SkinUserIdBox)
    end
})

-- [[ 저장된 변장 목록 관리 ]]
local SavedDisguises = {}
local SavedDisguiseFileName = "Bgns1Hub_RPG_SavedDisguises.json"

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
    local ok, decoded = pcall(function()
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
        if not createdFlags[name] then
            createdFlags[name] = true
            SkinChangerGroup:AddButton({
                Text = "저장 불러오기: " .. name .. " (" .. userId .. ")",
                Func = function()
                    applyDisguiseByUserId(userId, name)
                 end
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
                Title = "Disguise 저장 실패",
                Text = "UserId를 숫자로 입력하세요!",
                Duration = 4
            })
            return
        end

        local ok, name = pcall(function()
             return game.Players:GetNameFromUserIdAsync(userIdNum)
        end)
        if not ok or not name then
            name = "User_" .. tostring(userIdNum)
        end

        SavedDisguises[name] = userIdNum
        saveDisguisesToFile()
        refreshDisguiseButtons()

        game.StarterGui:SetCore("SendNotification", {
            Title = "Disguise 저장됨",
            Text = name .. "(" .. userIdNum .. ") 저장 완료!",
            Duration = 5
        })
    end
})

loadSavedDisguises()
refreshDisguiseButtons()

-- [[ 커스텀 무기 획득 스크립트 ]]
-- 특정 검을 소지하고 있을 때, 개발자용 무기([DEV] 미드나이트 천화의낫)로 외형과 기능을 변경
ScriptGroup:AddButton({
    Text = '[DEV] 미드나이트 천화의낫',
    Func = function()
        local player = game.Players.LocalPlayer
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local char = workspace:WaitForChild(player.Name)
        local humanoid = char:WaitForChild("Humanoid")

        -- 변경 가능한 원본 검 목록
        local validSwords = {
            "나무 검", "돌 검", "철 검", "왕의 검", "강철 대검",
            "데저트의 전설", "샌드 단검", "미라 학살자", "고블린의 분노",
            "맹세의 검", "카타나", "마그마 대검", "골렘 파괴자",
            "선혈도", "프로스트론", "툰드라의 기회", "냉기의 검",
            "일렉트릭 아이서", "여명의 손길", "저주받은 눈",
            "겨울성의 재보", "[DEV] 산나비 사슬팔", "다크 파이어",
            "저주혈검", "천멸추", "벚꽃도", "급사의 파훼", "용화도"
        }

        local swordTool = nil
        -- 인벤토리에 해당 검이 있는지 확인
        for _, tool in pairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                for _, name in pairs(validSwords) do
                    if tool.Name == name then
                        swordTool = tool
                         break
                    end
                end
            end
            if swordTool then break end
        end

        if not swordTool then
            warn("지정된 검을 찾을 수 없습니다!")
            return
        end

        -- 기존 검의 위치 데이터 저장
        local oldHandle = swordTool:WaitForChild("Handle")
        local oldGrip = swordTool:FindFirstChild("RightGrip", true)
        local gripC0
        if oldGrip and oldGrip:IsA("Motor6D") then
            gripC0 = oldGrip.C0
         end

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
         if oldRightGrip then oldRightGrip:Destroy() end

        local rightGrip = Instance.new("Motor6D")
        rightGrip.Name = "RightGrip"
        rightGrip.Part0 = rightHand
        rightGrip.Part1 = newHandle
        rightGrip.Parent = rightHand
        if gripC0 then
            rightGrip.C0 = gripC0
        else
             rightGrip.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 180, 0)
        end

        swordTool:Destroy()

        task.wait(0.5)

        -- 공격 애니메이션 및 클릭 이벤트 연결
        local UserInputService = game:GetService("UserInputService")
        local Players = game:GetService("Players")

        local player = Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local animator = humanoid:WaitForChild("Animator")

        local toolModel = workspace:WaitForChild(player.Name):WaitForChild("[DEV] 미드나이트 천화의낫")
        local attackAni1 = toolModel:WaitForChild("AttackAni1")
        local attackAni2 = toolModel:WaitForChild("AttackAni2")

        local clickCount = 0
        local canAttack = true
        local currentTrack = nil

        local function stopCurrentAnimation()
            if currentTrack then
                 currentTrack:Stop()
                currentTrack = nil
            end
        end

        -- 클릭 시 애니메이션 재생 (콤보 시스템)
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not canAttack then return end

            canAttack = false
            clickCount += 1

            stopCurrentAnimation()
            if clickCount % 2 == 1 then
                currentTrack = animator:LoadAnimation(attackAni1)
            else
                 currentTrack = animator:LoadAnimation(attackAni2)
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
local HasOriginalSky = false

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
        HasOriginalSky = false
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
                Sky[prop] = assetId
            end
            Lighting.GlobalShadows = true
        else
            for _, prop in pairs({"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}) do
                Sky[prop] = ""
             end
            Lighting.GlobalShadows = true
        end
        
        game.StarterGui:SetCore("SendNotification", {
            Title = "Skybox",
            Text = "기본 스카이박스로 복원됨",
            Duration = 3
        })
    else
        -- 외부 소스에서 스카이박스 데이터 로드
        local success, SkyboxLoader = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Forexium/eclipse/main/Skyboxes.lua", true))()
        end)

        if success and SkyboxLoader and SkyboxLoader[Value] then
            local skyboxData = SkyboxLoader[Value]
            for i, prop in ipairs({"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}) do
                 Sky[prop] = "rbxassetid://" .. skyboxData[i]
            end
            Lighting.GlobalShadows = false

            game.StarterGui:SetCore("SendNotification", {
                Title = "Skybox",
                Text = Value .. " 스카이박스 적용됨!",
                Duration = 3
            })
        else
            game.StarterGui:SetCore("SendNotification", {
                Title = "Skybox 오류",
                Text = "로드 실패: " .. Value,
                Duration = 5
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
    Default = false,
    Tooltip = '플레이어 주위로 눈이 계속 내림',
    Callback = function(Value)
        SnowEnabled = Value
        
        if Value then
            SnowConnection = game:GetService("RunService").Heartbeat:Connect(function()
                local player = game.Players.LocalPlayer
                local char = player.Character
                if not char or not char:FindFirstChild("HumanoidRootPart") then return end
                
                local playerPos = char.HumanoidRootPart.Position
                
                -- 확률적으로 눈송이 생성
                if math.random(1, 8) == 1 then
                     task.spawn(function()
                        local snowflake = snowflakeModel:Clone()
                        snowflake.Size = snowflake.Size * 0.3
                        snowflake.Anchored = true
                         snowflake.CanCollide = false
                        snowflake.CanTouch = false
                        snowflake.CanQuery = false
                        snowflake.Massless = true
                        
                        -- 플레이어 주변 랜덤 위치에 스폰
                        local angle = math.random() * math.pi * 2
                        local distance = math.random() * 500
                         local spawnPos = playerPos + Vector3.new(
                            math.cos(angle) * distance,
                            200,
                             math.sin(angle) * distance
                        )
                        
                        snowflake.Position = spawnPos
                         snowflake.Parent = game.Workspace
                        
                        local rotation = 0
                        local startTime = tick()
                        
                        -- 눈송이 하강 및 회전 애니메이션
                        while tick() - startTime < 8 and snowflake.Parent do
                            local currentPos = snowflake.Position
                            snowflake.CFrame = CFrame.new(currentPos.X, currentPos.Y - 1, currentPos.Z) 
                                * CFrame.Angles(0, math.rad(rotation), 0)
                            rotation += 2
                            task.wait(0.03)
                         end
                        
                        snowflake:Destroy()
                    end)
                 end
            end)
            print("눈 내리기 활성화")
        else
            if SnowConnection then
                SnowConnection:Disconnect()
                SnowConnection = nil
            end
             print("눈 내리기 비활성화")
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
             setfpscap(9999)
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
        AntiLagEnabled = not AntiLagEnabled
        
        if AntiLagEnabled then
            -- 물리, 렌더링, 그림자, 조명 효과 제거 및 품질 저하
            settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalPhysicsThrottle.Always
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9000000000
            Lighting.Brightness = 2
             
            for _, effect in pairs(Lighting:GetChildren()) do
                if effect:IsA("PostEffect") or effect:IsA("BloomEffect") or effect:IsA("BlurEffect") or 
                   effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") then
                    effect.Enabled = false
                 end
            end
            
            pcall(function()
                sethiddenproperty(Workspace.Terrain, "Decoration", false)
            end)
            
            -- 모든 파트의 재질을 단순화하고 텍스처 투명화
            for _, obj in pairs(game:GetDescendants()) do
                if obj:IsA("BasePart") and not obj:IsA("MeshPart") then
                    obj.Material = Enum.Material.SmoothPlastic
                elseif obj:IsA("Texture") or obj:IsA("Decal") then
                    obj.Transparency = 1
                 end
            end
            
            game.StarterGui:SetCore("SendNotification", {
                Title = "Optimizer",
                Text = "Anti LAG 활성화됨 (그래픽 강제 저하 + 효과 off)",
                 Duration = 4
            })
        else
            -- 복구 (완벽하지 않을 수 있음)
            Lighting.GlobalShadows = true
            pcall(function()
                sethiddenproperty(Workspace.Terrain, "Decoration", true)
            end)
            
            game.StarterGui:SetCore("SendNotification", {
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
     Func = function()
        FPSBoosterEnabled = not FPSBoosterEnabled
        
        if FPSBoosterEnabled then
            for _, obj in pairs(game:GetDescendants()) do
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Explosion") then
                    obj.Enabled = false
                 end
            end
            
            game.StarterGui:SetCore("SendNotification", {
                Title = "Optimizer",
                Text = "FPS Booster 활성화 (파티클/트레일/폭발 off)",
                 Duration = 4
            })
        else
            game.StarterGui:SetCore("SendNotification", {
                Title = "Optimizer",
                Text = "FPS Booster 비활성화 (기존 파티클 복구 안 됨)",
                Duration = 4
             })
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
    Text = 'AFK 방지', Default = true,
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
     Default = false,
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
    end
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

    local animFolder = getAnimFolder()
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
        print("정지할 애니메이션이 없습니다.")
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
    Func = function()
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

if game.Players.LocalPlayer.Character then
    game.Players.LocalPlayer.Character.Humanoid.PlatformStand = false
end

print("Bgns1 Hub | 실행 성공")

game.StarterGui:SetCore("SendNotification", {
        Title = "Bgns1-Hub",
        Text = "Gui에서 마우스 커서가 보이지 않는다면 F4를 누르세요!",
        Duration = 5
    })
