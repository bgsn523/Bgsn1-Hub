-- [[ 서비스 및 기본 변수 정의 ]]
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- [[ 캐릭터 굳음 방지 ]]
if LocalPlayer.Character then
    local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
    if hum then hum.PlatformStand = false end
end

-- [[ 오토팜 설정 테이블 ]]
local AutoFarmConfig = {
    Enabled = false,       -- 오토팜 활성화 여부
    Distance = 0,          -- 몹과의 거리 조절
    HeightOffset = 5,      -- 몹 위에서의 높이 조절
    TargetMob = nil,       -- 공격 대상 몹 이름
    CurrentTarget = nil,   -- 현재 타겟팅 중인 몹 객체
    AutoSkillEnabled = false, -- 스킬 자동 사용 여부
    AutoClickEnabled = true,  -- 자동 클릭(물리 공격) 활성화 여부
    Skills = {E = false, R = false, T = false} -- 사용할 스킬 목록
}

local AttackDirection = "Front" -- 공격 방향
local DirectionAngles = {Front = 0, Back = 180, Up = -90, Down = 90}
local Mobs = Workspace:WaitForChild("Mobs") 
local MobList, MobMap = {}, {} 
local AutoFarmConnection = nil 
local lastAttackTime = 0 
local lastSkillTime = 0 
local LastSpawnTime = 0 -- 마지막 리스폰 시간 기록용 변수

-- 캐릭터가 새로 생길 때마다 시간 기록
Players.LocalPlayer.CharacterAdded:Connect(function()
    LastSpawnTime = tick()
end)

-- [[ 캐릭터 객체 가져오기 ]]
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

-- [[ 스킬 사용 함수 ]]
local function fireSkill(skillKey)
    pcall(function()
        local remote = ReplicatedStorage:WaitForChild("Remote"):WaitForChild("Skill")
        remote:FireServer(skillKey)
    end)
end

-- [[ 몹 리스트 갱신 함수 ]]
local function getMobList()
    local mobsFolder = Workspace:FindFirstChild("Mobs")
    if not mobsFolder then return {}, {} end

    local processedMobs = {}
    local mobDisplayList = {}
    local mobNameMap = {}

    for _, mob in ipairs(mobsFolder:GetChildren()) do
        if mob.Name and mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") then
            if not processedMobs[mob.Name] then
                local displayName = mob.Name 
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

-- [[ 타겟 몹 찾기 ]]
local function findTargetMob()
    if not AutoFarmConfig.TargetMob then return nil end
    
    for _, mob in pairs(Mobs:GetChildren()) do
        if not isMobDead(mob) then
            if mob.Name == AutoFarmConfig.TargetMob or string.find(mob.Name, AutoFarmConfig.TargetMob) then
                return mob
            end
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

-- [[ 위치 계산 (CFrame) ]]
local function calculatePerfectCFrame(targetPos, distanceOffset, attackDirection)
    local targetRootPart = AutoFarmConfig.CurrentTarget:FindFirstChild("HumanoidRootPart") or AutoFarmConfig.CurrentTarget:FindFirstChild("HRP")
    if not targetRootPart then return CFrame.new(targetPos) end

    local npcLookDirection = targetRootPart.CFrame.LookVector
    local offsetPosition = targetRootPart.Position + (npcLookDirection * distanceOffset)
    offsetPosition = Vector3.new(offsetPosition.X, targetPos.Y, offsetPosition.Z)

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

        -- [[ 타겟이 없을 때 대기 로직 ]] 
        if not currentTarget then
            hrp.Velocity = Vector3.new(0, 0, 0)
            
            if not waitCFrame then
                -- 현재 위치에서 위로 10만큼 설정
                waitCFrame = hrp.CFrame * CFrame.new(0, 10, 0)
            end
            
            hrp.CFrame = waitCFrame 
            return
        else
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

-- [[ Rayfield UI 라이브러리 로드 ]]
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Bgsn1-Hub",
    LoadingTitle = "스크립트 로딩 중...",
    LoadingSubtitle = "by Bgsn1",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AutoFarmConfig",
        FileName = "MyConfig"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true 
    },
    KeySystem = false,
})

-- [[ 탭 생성 ]]
local MainTab = Window:CreateTab("오토팜", 4483362458) -- 아이콘 ID (적절한 것으로 변경 가능)

-- [[ 메인 설정 섹션 ]]
MainTab:CreateSection("메인 설정")

local AutoFarmToggle = MainTab:CreateToggle({
    Name = "오토팜 켜기",
    CurrentValue = false,
    Flag = "AutoFarmToggle",
    Callback = function(Value)
        AutoFarmConfig.Enabled = Value
        AutoFarmConfig.CurrentTarget = nil
        
        if Value then
            startAutoFarm()
        else
            if AutoFarmConnection then
                AutoFarmConnection:Disconnect()
                AutoFarmConnection = nil
            end
            
            local character = getCharacter()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local hrp = character:FindFirstChild("HumanoidRootPart")
            
            if humanoid then humanoid.PlatformStand = false end
            if hrp then
                hrp.Velocity = Vector3.new(0,0,0)
                pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
            end
        end
    end,
})

local AutoClickToggle = MainTab:CreateToggle({
    Name = "자동 클릭 (평타)",
    CurrentValue = true,
    Flag = "AutoClickToggle",
    Callback = function(Value)
        AutoFarmConfig.AutoClickEnabled = Value
    end,
})

-- 드롭다운 객체를 변수에 담아 나중에 Refresh 할 수 있게 함
local MobDropdown 
MobDropdown = MainTab:CreateDropdown({
    Name = "적 선택",
    Options = (#MobList > 0 and MobList) or {"몹 없음"},
    CurrentOption = "몹 없음", -- 초기값
    MultipleOptions = false,
    Flag = "MobDropdown",
    Callback = function(Option)
        -- Rayfield는 단일 선택 시 string, 다중 선택 시 table 반환할 수 있음
        -- 여기선 단일 선택이므로 Option은 string일 가능성이 높음 (버전에 따라 다를 수 있어 처리)
        local val = (type(Option) == "table" and Option[1]) or Option
        
        local targetName = MobMap[val] or val
        AutoFarmConfig.TargetMob = targetName
        AutoFarmConfig.CurrentTarget = nil
        
        print("타겟 설정됨: " .. tostring(targetName))
    end,
})

MainTab:CreateButton({
    Name = "몹 목록 새로고침",
    Callback = function()
        local newMobList, newMobMap = getMobList()
        MobList = newMobList
        MobMap = newMobMap
        
        -- Dropdown 갱신
        MobDropdown:Refresh((#MobList > 0 and MobList) or {"몹 없음"})
    end,
})

-- [[ 🛡️ 매크로 방지 우회 섹션 ]]
-- MainTab 변수가 이미 정의되어 있다고 가정합니다 (이전 코드의 오토팜 탭)

MainTab:CreateSection("매크로 방지 우회")

local AntiMacroEnabled = false -- 토글 상태 저장 변수

MainTab:CreateToggle({
    Name = "매크로 방지 자동 우회",
    CurrentValue = false,
    Flag = "AntiMacroToggle",
    Callback = function(Value)
        AntiMacroEnabled = Value
        if Value then
            Rayfield:Notify({
                Title = "시스템 알림",
                Content = "매크로 방지 감시가 시작되었습니다.",
                Duration = 3,
                Image = 4483362458,
            })
        else
            Rayfield:Notify({
                Title = "시스템 알림",
                Content = "매크로 방지 감시가 종료되었습니다.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end,
})

-- [[ 🕵️‍♂️ 감시 및 자동 입력 로직 (백그라운드 실행) ]]
task.spawn(function()
    while true do
        task.wait(1) -- 1초마다 매크로 창이 떴는지 검사 (너무 빠르면 렉 유발 가능성)
        
        if AntiMacroEnabled then
            pcall(function()
                local player = game:GetService("Players").LocalPlayer
                if not player then return end
                
                -- 매크로 GUI 찾기 (경로: PlayerGui -> MacroGui -> Frame -> Frame)
                local playerGui = player:FindFirstChild("PlayerGui")
                if not playerGui then return end

                local macroGui = playerGui:FindFirstChild("MacroGui")
                if macroGui then
                    local frame1 = macroGui:FindFirstChild("Frame")
                    if frame1 then
                        local mainFrame = frame1:FindFirstChild("Frame")
                        
                        if mainFrame then
                            local inputLabel = mainFrame:FindFirstChild("Input")
                            local inputTextBox = mainFrame:FindFirstChild("TextBox")
                            
                            if inputLabel and inputTextBox then
                                -- [핵심] 텍스트에서 "숫자"만 추출 (예: "다음 숫자... 1234" -> "1234")
                                local targetNum = inputLabel.Text:match("%d+")
                                
                                -- 숫자가 존재하고, 입력창이 비어있거나 다르면 입력 실행
                                if targetNum and inputTextBox.Text ~= targetNum then
                                    inputTextBox.Text = targetNum
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- [[ 스킬 설정 섹션 ]]
MainTab:CreateSection("스킬 설정")

MainTab:CreateToggle({
    Name = "오토스킬 사용",
    CurrentValue = false,
    Flag = "AutoSkillToggle",
    Callback = function(Value)
        AutoFarmConfig.AutoSkillEnabled = Value
    end,
})

MainTab:CreateToggle({ Name = "E 스킬", CurrentValue = false, Flag = "SkillE", Callback = function(V) AutoFarmConfig.Skills.E = V end })
MainTab:CreateToggle({ Name = "R 스킬", CurrentValue = false, Flag = "SkillR", Callback = function(V) AutoFarmConfig.Skills.R = V end })
MainTab:CreateToggle({ Name = "T 스킬", CurrentValue = false, Flag = "SkillT", Callback = function(V) AutoFarmConfig.Skills.T = V end })

-- [[ 위치/방향 설정 섹션 ]]
MainTab:CreateSection("위치/방향 설정")

MainTab:CreateSlider({
    Name = "거리 조절 (앞/뒤)",
    Range = {-20, 20},
    Increment = 1,
    Suffix = "Studs",
    CurrentValue = 0,
    Flag = "DistanceSlider",
    Callback = function(Value)
        AutoFarmConfig.Distance = Value
    end,
})

MainTab:CreateSlider({
    Name = "높이 조절 (위/아래)",
    Range = {-20, 20},
    Increment = 1,
    Suffix = "Studs",
    CurrentValue = 5,
    Flag = "HeightOffsetSlider",
    Callback = function(Value)
        AutoFarmConfig.HeightOffset = Value
    end,
})

MainTab:CreateDropdown({
    Name = "공격 방향",
    Options = {'Front', 'Back', 'Up', 'Down'},
    CurrentOption = 'Front',
    MultipleOptions = false,
    Flag = "AttackDirDropdown",
    Callback = function(Option)
        local val = (type(Option) == "table" and Option[1]) or Option
        AttackDirection = val
    end,
})


-- [[ 💊 아이템 자동 사용 변수 및 로직 ]]
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

-- [[ 탭 생성: 아이템 자동 사용 ]]
local ItemTab = Window:CreateTab("아이템 자동 사용", 4483362458) -- 아이콘 ID는 적절히 변경 가능

-- ==============================
-- [1번 퀵바 설정]
-- ==============================
ItemTab:CreateSection("1번 퀵바 설정")

ItemTab:CreateToggle({
    Name = "1번 퀵바 자동 사용",
    CurrentValue = false,
    Flag = "AutoItem1_Toggle",
    Callback = function(Value)
        AutoItemConfig.Slot1.Enabled = Value
    end,
})

ItemTab:CreateSlider({
    Name = "1번 사용 딜레이 (초)",
    Range = {0, 30},
    Increment = 0.1,
    Suffix = "초",
    CurrentValue = 5,
    Flag = "AutoItem1_Delay",
    Callback = function(Value)
        AutoItemConfig.Slot1.Delay = Value
    end,
})

-- ==============================
-- [2번 퀵바 설정]
-- ==============================
ItemTab:CreateSection("2번 퀵바 설정")

ItemTab:CreateToggle({
    Name = "2번 퀵바 자동 사용",
    CurrentValue = false,
    Flag = "AutoItem2_Toggle",
    Callback = function(Value)
        AutoItemConfig.Slot2.Enabled = Value
    end,
})

ItemTab:CreateSlider({
    Name = "2번 사용 딜레이 (초)",
    Range = {0, 30},
    Increment = 0.1,
    Suffix = "초",
    CurrentValue = 5,
    Flag = "AutoItem2_Delay",
    Callback = function(Value)
        AutoItemConfig.Slot2.Delay = Value
    end,
})

-- ==============================
-- [3번 퀵바 설정]
-- ==============================
ItemTab:CreateSection("3번 퀵바 설정")

ItemTab:CreateToggle({
    Name = "3번 퀵바 자동 사용",
    CurrentValue = false,
    Flag = "AutoItem3_Toggle",
    Callback = function(Value)
        AutoItemConfig.Slot3.Enabled = Value
    end,
})

ItemTab:CreateSlider({
    Name = "3번 사용 딜레이 (초)",
    Range = {0, 30},
    Increment = 0.1,
    Suffix = "초",
    CurrentValue = 5,
    Flag = "AutoItem3_Delay",
    Callback = function(Value)
        AutoItemConfig.Slot3.Delay = Value
    end,
})

-- [[ 🔄 작동 루프 (비동기 실행) ]]

-- 1번 슬롯 루프
task.spawn(function()
    while true do
        if AutoItemConfig.Slot1.Enabled then
            simulateKeyPress(Enum.KeyCode.One) -- 숫자 1 입력
            local waitTime = math.max(0.1, AutoItemConfig.Slot1.Delay)
            task.wait(waitTime)
        else
            task.wait(1)
        end
    end
end)

-- 2번 슬롯 루프
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

-- 3번 슬롯 루프
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

-- [[ 📍 위치 저장 및 자동 복귀 탭 ]] --
local TeleportTab = Window:CreateTab("위치 저장/이동", 4483362458) -- 아이콘 ID는 변경 가능
local SavePosSection = TeleportTab:CreateSection("위치 관리")

-- 변수 정의
local SavedPosition = nil -- 저장된 CFrame
local AutoTpOnDeath = false
local PosInputObject = nil -- Rayfield Input 객체 저장용

-- 1. [입력창] 좌표 직접 수정 & 표시
-- Rayfield에서는 객체를 변수에 담아야 나중에 값을 바꿀 수 있습니다.
PosInputObject = TeleportTab:CreateInput({
    Name = "저장된 좌표",
    PlaceholderText = "예: 100, 50, -200",
    RemoveTextAfterFocusLost = false, -- 입력 후 텍스트가 사라지지 않게 설정
    Callback = function(Text)
        -- 사용자가 직접 입력했을 때 좌표 파싱
        local x, y, z = Text:match("([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)")
        if x and y and z then
            SavedPosition = CFrame.new(tonumber(x), tonumber(y), tonumber(z))
            -- (선택사항) 디버깅용 프린트
            -- print("좌표 수동 업데이트됨:", x, y, z)
        end
    end,
})

-- 2. [버튼] 현재 위치 가져오기
TeleportTab:CreateButton({
    Name = "현재 위치 가져오기",
    Callback = function()
        local p = game.Players.LocalPlayer
        if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            -- 1. 현재 위치 저장
            SavedPosition = p.Character.HumanoidRootPart.CFrame
            local pos = SavedPosition.Position
            
            -- 2. 좌표를 보기 좋게 문자열로 변환 (소수점 1자리까지)
            local posString = string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
            
            -- 3. [핵심] Rayfield 입력창의 텍스트 강제 변경
            if PosInputObject then
                PosInputObject:Set(posString) 
            end
            
            Rayfield:Notify({
                Title = "위치 저장 완료",
                Content = "현재 위치가 저장되었습니다.\n" .. posString,
                Duration = 3,
                Image = 4483362458,
            })
        else
            Rayfield:Notify({
                Title = "오류",
                Content = "캐릭터를 찾을 수 없습니다.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end,
})

-- 3. [토글] 죽으면 자동 복귀
TeleportTab:CreateToggle({
    Name = "죽으면 자동 복귀",
    CurrentValue = false,
    Flag = "AutoTpToggle",
    Callback = function(Value)
        AutoTpOnDeath = Value
    end,
})

-- 4. [로직] 캐릭터 부활 시 자동 이동
game:GetService("Players").LocalPlayer.CharacterAdded:Connect(function(newChar)
    if AutoTpOnDeath and SavedPosition then
        task.wait(1.5) -- 로딩 대기 (너무 빠르면 씹힐 수 있음)
        local hrp = newChar:WaitForChild("HumanoidRootPart", 10)
        
        if hrp then
            hrp.CFrame = SavedPosition
            
            -- (선택사항) 알림 띄우기
            Rayfield:Notify({
                Title = "자동 복귀",
                Content = "저장된 위치로 이동했습니다.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end
end)





Rayfield:Notify({
    Title = "스크립트 로드 완료",
    Content = "guns.lol/bgsn1.",
    Duration = 6.5,
    Image = 4483362458,
})