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

-- [[ 🛡️ 매크로 방지 우회 V11 (Text 인식형) ]] --
-- 주의: 아래 'MainTab'은 사용 중인 탭 변수명으로 맞춰주세요.
local AntiMacroSection = MainTab:CreateSection("매크로 방지 우회 (V11)")

-- 서비스 및 변수 정의
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local AntiMacroEnabled = false

-- [[ 1. 토글 생성 ]]
MainTab:CreateToggle({
    Name = "매크로 방지 자동 우회",
    CurrentValue = false,
    Flag = "AntiMacroV11",
    Callback = function(Value)
        AntiMacroEnabled = Value
        if Value then
            Rayfield:Notify({
                Title = "시스템 알림",
                Content = "매크로 방지 감시가 시작되었습니다.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end,
})

-- [[ 2. 헬퍼 함수 ]]

-- GUI 요소 중앙 클릭 함수 (상단바 오차 보정)
local function clickGuiObject(obj)
    if not obj or not obj.Visible or not obj.Active then return end
    
    local pos = obj.AbsolutePosition
    local size = obj.AbsoluteSize
    local topbarInset = GuiService:GetGuiInset().Y
    
    local x = pos.X + (size.X / 2)
    local y = pos.Y + (size.Y / 2) + topbarInset

    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
end

-- 텍스트로 숫자 버튼 찾기 (랜덤 키패드 대응)
local function findDigitButton(keyFrame, digit)
    for _, btn in ipairs(keyFrame:GetChildren()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Text == digit then
            return btn
        end
    end
    return nil
end

-- [[ 3. 감지 및 우회 루프 ]]
task.spawn(function()
    while true do
        task.wait(1) -- 1초마다 검사
        
        if AntiMacroEnabled then
            pcall(function()
                local player = game:GetService("Players").LocalPlayer
                if not player then return end

                local gui = player.PlayerGui:FindFirstChild("MacroGui")
                
                if gui and gui.Enabled then
                    -- GUI 구조 탐색 (게임 업데이트 대비 유연하게)
                    local rootFrame = gui:FindFirstChild("Frame") or gui:FindFirstChild("MacroClient") or gui
                    if not rootFrame then return end
                    
                    local displayFrame = rootFrame:FindFirstChild("Frame")
                    local keyFrame = rootFrame:FindFirstChild("KeyInputFrame")
                    local resetFrame = rootFrame:FindFirstChild("KeyReset")
                    
                    if displayFrame and keyFrame then
                        -- 숫자 표시 라벨 및 입력창 찾기
                        local inputLabel = displayFrame:FindFirstChild("Input") or displayFrame:FindFirstChildWhichIsA("TextLabel")
                        local outputBox = displayFrame:FindFirstChild("TextBox")
                        
                        if inputLabel and outputBox then
                            -- 정규식으로 4자리 숫자 추출
                            local targetNum = inputLabel.Text:match("%d%d%d%d")
                            
                            -- 숫자가 존재하고, 아직 입력하지 않았다면 실행
                            if targetNum and outputBox.Text ~= targetNum then
                                
                                Rayfield:Notify({
                                    Title = "매크로 감지됨",
                                    Content = "목표 숫자: " .. targetNum .. " 입력 시작...",
                                    Duration = 3,
                                    Image = 4483362458,
                                })
                                
                                -- 1단계: TextBox 클릭해서 포커스 (키패드 활성화)
                                if not keyFrame.Visible then
                                    clickGuiObject(outputBox)
                                    task.wait(0.8)
                                end
                                
                                -- 2단계: 리셋 버튼 눌러서 기존 입력 지우기
                                local resetBtn = resetFrame and resetFrame:FindFirstChild("TextButton")
                                if resetBtn then
                                    for i = 1, 5 do
                                        if outputBox.Text == "" then break end
                                        clickGuiObject(resetBtn)
                                        task.wait(0.4)
                                    end
                                end
                                
                                task.wait(0.5)
                                
                                -- 3단계: 숫자 입력 (버튼 Text를 읽어서 클릭)
                                if outputBox.Text == "" then
                                    for i = 1, #targetNum do
                                        local digit = string.sub(targetNum, i, i)
                                        local btn = findDigitButton(keyFrame, digit)
                                        
                                        if btn then
                                            clickGuiObject(btn)
                                            task.wait(0.35) -- 입력 씹힘 방지 딜레이
                                        else
                                            warn("숫자 버튼을 찾을 수 없습니다: " .. digit)
                                        end
                                    end
                                    print("매크로 우회 입력 완료: " .. targetNum)
                                end
                                
                                task.wait(2.5) -- 처리 후 대기
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




-- [[ 🗺️ 지역 이동 탭 ]] --
local LocationTab = Window:CreateTab("지역 이동", 4483362458) -- 아이콘 ID (적절히 변경 가능)
local TpSection = LocationTab:CreateSection("주요 지역")

-- [[ 텔레포트 위치 데이터 ]]
local TeleportLocations = {
    ["스폰"] = CFrame.new(-152.783508, 139.910004, 1791.16602, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    ["이름 몰?루"] = CFrame.new(-5.18880367, 140.157761, 2492.52466, -0.91892904, 0.0095216129, -0.394307911, -0.0174374916, 0.997750401, 0.0647310913, 0.394037217, 0.0663590208, -0.916695774),
    ["피라미드"] = CFrame.new(-294.798401, 245, 4799.24561, 1, 0, 0, 0, 1, 0, 0, 0, 1),
    ["무사관"] = CFrame.new(-1433.65576, 192.344635, 3796.99072, 0.712066472, 0.0192845948, 0.701847136, 3.82279977e-05, 0.99962163, -0.0275053065, -0.702112019, 0.0196124371, 0.711796343),
    ["메이플 월드"] = CFrame.new(-682.302002, 150.36142, 3476.62207, -0.758712471, 0.0163987316, 0.651219189, 4.14453643e-05, 0.999684334, -0.0251253452, -0.65142566, -0.0190359224, -0.758473635),
    ["고대사막"] = CFrame.new(-295.476227, 129.719971, 3825.25537, -0.705779552, -4.20836095e-08, -0.708431542, -2.02547241e-08, 1, -3.92250215e-08, 0.708431542, -1.33351339e-08, -0.705779552)
}

-- 드롭다운에 넣을 이름 목록 추출 및 정렬
local LocationNames = {}
for name, _ in pairs(TeleportLocations) do
    table.insert(LocationNames, name)
end
table.sort(LocationNames) -- 가나다순 정렬

local SelectedTpLocation = LocationNames[1] -- 기본 선택값

-- [[ UI 구성 ]]

-- 1. 장소 선택 드롭다운
LocationTab:CreateDropdown({
    Name = "이동할 장소 선택",
    Options = LocationNames,
    CurrentOption = SelectedTpLocation,
    MultipleOptions = false,
    Flag = "TpLocationDropdown",
    Callback = function(Option)
        -- Rayfield 버전에 따라 Option이 table 혹은 string일 수 있음
        local val = (type(Option) == "table" and Option[1]) or Option
        SelectedTpLocation = val
    end,
})

-- 2. 이동 버튼
LocationTab:CreateButton({
    Name = "선택한 장소로 이동하기",
    Callback = function()
        local destinationCFrame = TeleportLocations[SelectedTpLocation]
        
        if destinationCFrame then
            local character = game:GetService("Players").LocalPlayer.Character
            if character and character:FindFirstChild("HumanoidRootPart") then
                character.HumanoidRootPart.CFrame = destinationCFrame
                
                Rayfield:Notify({
                    Title = "이동 완료",
                    Content = SelectedTpLocation .. "(으)로 순간이동했습니다.",
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
        else
            Rayfield:Notify({
                Title = "오류",
                Content = "유효하지 않은 위치입니다.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end,
})


-- [[ 💾 스폰 포인트 등록 섹션 ]] --
-- 위에서 만든 LocationTab에 이어서 추가됩니다.

LocationTab:CreateSection("스폰 포인트 등록")

-- [헬퍼 함수] 텔레포트 후 ProximityPrompt 상호작용 로직
local function interactWithPrompt(targetCFrame, promptPathFunc, returnToOriginal)
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart")
    
    local originalCFrame = root.CFrame

    -- 1. 목표 위치로 이동
    root.CFrame = targetCFrame
    task.wait(0.5)

    -- 2. 프롬프트 찾기
    local prompt
    pcall(function()
        prompt = promptPathFunc()
    end)

    -- 3. 프롬프트 실행
    if prompt then
        local oldDuration = prompt.HoldDuration
        prompt.HoldDuration = 0 -- 즉시 발동되게 0초로 변경
        fireproximityprompt(prompt)
        task.wait(0.05)
        prompt.HoldDuration = oldDuration -- 원래 시간 복구
        
        Rayfield:Notify({
            Title = "성공",
            Content = "스폰 포인트가 등록되었습니다.",
            Duration = 2,
            Image = 4483362458,
        })
    else
        Rayfield:Notify({
            Title = "오류",
            Content = "상호작용할 대상을 찾지 못했습니다.",
            Duration = 3,
            Image = 4483362458,
        })
    end

    -- 4. 원래 위치로 복귀 (옵션)
    if returnToOriginal then
        root.CFrame = originalCFrame
    end
end

-- 1. 루나마을 스폰
LocationTab:CreateButton({
    Name = "루나마을 스폰 등록",
    Callback = function()
        interactWithPrompt(
            CFrame.new(-50.4700165, 136.039993, 1992.54004, 1, 0, 0, 0, 1, 0, 0, 0, 1),
            function() return workspace.SpawnPoint["루나마을 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt") end,
            true -- 원래 위치로 복귀함
        )
    end,
})

-- 2. 겨울성 스폰
LocationTab:CreateButton({
    Name = "겨울성 스폰 등록",
    Callback = function()
        interactWithPrompt(
            CFrame.new(2177.99341, 378.901886, 4562.57129, 0.399358451, 0, 0.916794896, 0, 1, 0, -0.916794896, 0, 0.399358451),
            function() return workspace.SpawnPoint["겨울성 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt") end,
            true
        )
    end,
})

-- 3. 겨울 스폰
LocationTab:CreateButton({
    Name = "겨울 스폰 등록",
    Callback = function()
        interactWithPrompt(
            CFrame.new(331.624847, 192.511246, 3749.88232, 1, 0, 0, 0, 1, 0, 0, 0, 1),
            function() return workspace.SpawnPoint["겨울 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt") end,
            true
        )
    end,
})

-- 4. 메이플 스폰
LocationTab:CreateButton({
    Name = "메이플 스폰 등록",
    Callback = function()
        interactWithPrompt(
            CFrame.new(-1433.6543, 199.052856, 3796.99219, -1, 0, 0, 0, 1, 0, 0, 0, -1),
            function() return workspace.SpawnPoint["메이플 스폰"].SpawnPart:FindFirstChildOfClass("ProximityPrompt") end,
            true
        )
    end,
})


-- [[ 🌍 세계 이동 섹션 (분리됨) ]] --
LocationTab:CreateSection("세계 이동")

-- 2세계 텔레포트
LocationTab:CreateButton({
    Name = "2세계 텔레포트",
    Callback = function()
        interactWithPrompt(
            CFrame.new(
                -36.1729698, 150.903793, -2374.63696,
                4.59551811e-05, 1.87382102e-06, -0.99999994,
                0.0814801306, -0.996674895, 1.87382102e-06,
                -0.996674955, -0.0814801306, -4.58955765e-05
            ),
            function() return workspace.Map.Teleport["World2"]:FindFirstChildOfClass("ProximityPrompt") end,
            false -- 2세계로 가는 것이므로 원래 위치로 돌아오지 않음
        )
    end,
})

-- [[ 🏃 캐릭터 조작 탭 (모바일 높낮이 조절 수정판) ]] --
local CharacterTab = Window:CreateTab("캐릭터 조작", 4483362458)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 변수 설정
local NoclipConnection = nil
local FlyConnection = nil
local FlySpeed = 20
local BodyVel, BodyGyro = nil, nil

-- [[ 섹션 1: 이동 속도 및 점프 ]]
CharacterTab:CreateSection("이동 속도 및 점프")

CharacterTab:CreateSlider({
    Name = "이동 속도 (WalkSpeed)",
    Range = {16, 300},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "WalkSpeedSlider",
    Callback = function(Value)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = Value end
    end,
})

CharacterTab:CreateSlider({
    Name = "점프력 (JumpPower)",
    Range = {50, 500},
    Increment = 1,
    Suffix = "Power",
    CurrentValue = 50,
    Flag = "JumpPowerSlider",
    Callback = function(Value)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum then
            hum.UseJumpPower = true 
            hum.JumpPower = Value
        end
    end,
})

-- [[ 섹션 2: 유틸리티 ]]
CharacterTab:CreateSection("유틸리티 (노클립/플라이)")

CharacterTab:CreateToggle({
    Name = "노클립 (벽 통과)",
    CurrentValue = false,
    Flag = "NoclipToggle",
    Callback = function(Value)
        if Value then
            NoclipConnection = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                    for _, part in pairs(char:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide == true then
                            part.CanCollide = false
                        end
                    end
                end
            end)
            Rayfield:Notify({Title = "노클립", Content = "활성화됨", Duration = 2})
        else
            if NoclipConnection then NoclipConnection:Disconnect() NoclipConnection = nil end
            Rayfield:Notify({Title = "노클립", Content = "비활성화됨", Duration = 2})
        end
    end,
})

-- [[ 🚀 플라이 (모바일 높낮이 지원) ]]
CharacterTab:CreateSlider({
    Name = "플라이 속도",
    Range = {1, 200},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 20,
    Flag = "FlySpeedSlider",
    Callback = function(Value)
        FlySpeed = Value
    end,
})

CharacterTab:CreateToggle({
    Name = "플라이 (날기)",
    CurrentValue = false,
    Flag = "FlyToggle",
    Callback = function(Value)
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChild("Humanoid")

        if Value then
            if not root or not hum then return end

            -- 물리 객체 생성
            BodyVel = Instance.new("BodyVelocity")
            BodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            BodyVel.Parent = root

            BodyGyro = Instance.new("BodyGyro")
            BodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            BodyGyro.P = 3000 -- 회전 반응 속도
            BodyGyro.Parent = root

            -- [[ 🔥 핵심 로직: 카메라 방향 따라가기 ]]
            FlyConnection = RunService.RenderStepped:Connect(function()
                if not root or not hum or hum.Health <= 0 then
                    -- 캐릭터 사망/사라짐 체크
                    if FlyConnection then FlyConnection:Disconnect() FlyConnection = nil end
                    if BodyVel then BodyVel:Destroy() end
                    if BodyGyro then BodyGyro:Destroy() end
                    return
                end

                local cam = workspace.CurrentCamera
                local moveDir = hum.MoveDirection -- 조이스틱/키보드 입력 (평면)
                
                -- 캐릭터 회전: 무조건 카메라를 바라보게 함
                BodyGyro.CFrame = cam.CFrame

                if moveDir.Magnitude > 0 then
                    -- 입력 값을 카메라 기준(3D)으로 변환
                    -- 1. 카메라의 '평면' 앞방향을 구함 (Y축 제거)
                    local camLookFlat = (cam.CFrame.LookVector * Vector3.new(1,0,1)).Unit
                    local camRightFlat = (cam.CFrame.RightVector * Vector3.new(1,0,1)).Unit
                    
                    -- 예외처리 (바닥/하늘을 수직으로 볼 때 Unit 계산 오류 방지)
                    if camLookFlat.Magnitude == 0 then camLookFlat = cam.CFrame.LookVector end
                    if camRightFlat.Magnitude == 0 then camRightFlat = cam.CFrame.RightVector end

                    -- 2. 내 입력(moveDir)이 앞뒤인지 좌우인지 비율 계산 (Dot Product)
                    local forwardFactor = moveDir:Dot(camLookFlat)
                    local rightFactor = moveDir:Dot(camRightFlat)

                    -- 3. 실제 이동 벡터: 카메라의 '진짜' 앞방향(3D)과 옆방향을 섞음
                    -- (이렇게 하면 위를 보고 앞을 누르면 위로 감)
                    local finalDir = (cam.CFrame.LookVector * forwardFactor) + (cam.CFrame.RightVector * rightFactor)
                    
                    BodyVel.Velocity = finalDir * FlySpeed
                else
                    BodyVel.Velocity = Vector3.new(0, 0, 0)
                end
            end)
            
            hum.PlatformStand = true -- 넘어짐 방지
            Rayfield:Notify({Title = "플라이", Content = "활성화됨 (시점 방향으로 이동)", Duration = 2})

        else
            -- 끄기 로직
            if FlyConnection then FlyConnection:Disconnect() FlyConnection = nil end
            if BodyVel then BodyVel:Destroy() BodyVel = nil end
            if BodyGyro then BodyGyro:Destroy() BodyGyro = nil end
            
            if hum then hum.PlatformStand = false end
            Rayfield:Notify({Title = "플라이", Content = "비활성화됨", Duration = 2})
        end
    end,
})

-- [[ ⚙️ 콘픽(설정) 탭 ]] --
local ConfigTab = Window:CreateTab("콘픽", 4483362458)
local ConfigSection = ConfigTab:CreateSection("사냥터 프리셋")

ConfigTab:CreateButton({
    Name = "나락화 수호자 콘픽 적용 + 리셋",
    Callback = function()
        -- [[ 1. 위치 및 자동 복귀 설정 ]]
        local targetPos = Vector3.new(246.6, -983.3, 4647.6)
        SavedPosition = CFrame.new(targetPos)
        AutoTpOnDeath = true -- 죽으면 자동 복귀 활성화
        
        -- UI 입력창 업데이트
        if PosInputObject then
            PosInputObject:Set("246.6, -983.3, 4647.6")
        end

        -- [[ 2. 오토팜 설정 ]]
        AutoFarmConfig.Enabled = true
        AutoFarmConfig.AutoClickEnabled = true
        AutoFarmConfig.TargetMob = "나락화 수호자"
        AutoFarmConfig.HeightOffset = 9
        AttackDirection = "Up"
        
        -- 드롭다운 UI 업데이트
        if MobDropdown then
            MobDropdown:Refresh({AutoFarmConfig.TargetMob}) -- 목록 갱신
            MobDropdown:Set(AutoFarmConfig.TargetMob) -- 선택
        end

        -- [[ 3. 스킬 설정 ]]
        AutoFarmConfig.AutoSkillEnabled = true
        AutoFarmConfig.Skills.E = true
        AutoFarmConfig.Skills.R = true
        AutoFarmConfig.Skills.T = true

        -- [[ 4. 매크로 방지 설정 ]]
        AntiMacroEnabled = true

        -- [[ 5. 오토팜 시작 ]]
        startAutoFarm()

        -- [[ 6. 알림 띄우기 ]]
        Rayfield:Notify({
            Title = "설정 적용됨",
            Content = "설정 완료! 캐릭터를 재설정하여 이동합니다...",
            Duration = 3,
            Image = 4483362458,
        })

        -- [[ 7. 캐릭터 재설정 (Reset) ]]
        -- 설정을 다 적용한 뒤 죽어야 'AutoTpOnDeath'가 작동함
        local player = game:GetService("Players").LocalPlayer
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.Health = 0
        end
    end,
})

ConfigTab:CreateButton({
    Name = "예티 콘픽 적용 + 리셋",
    Callback = function()
        -- [[ 1. 위치 및 자동 복귀 설정 ]]
        local targetPos = Vector3.new(1370.4, 198.7, 4141.8)
        SavedPosition = CFrame.new(targetPos)
        AutoTpOnDeath = true -- 죽으면 자동 복귀 활성화
        
        -- UI 입력창 업데이트
        if PosInputObject then
            PosInputObject:Set("1370.4, 198.7, 4141.8")
        end

        -- [[ 2. 오토팜 설정 ]]
        AutoFarmConfig.Enabled = true
        AutoFarmConfig.AutoClickEnabled = true
        AutoFarmConfig.TargetMob = "예티" -- 몹 이름 (한글/영어 확인 필요, 게임 내 이름 기준)
        AutoFarmConfig.HeightOffset = 9
        AttackDirection = "Up"
        
        -- 드롭다운 UI 업데이트
        if MobDropdown then
            MobDropdown:Refresh({AutoFarmConfig.TargetMob}) -- 목록 갱신 (선택된 것만 보이게)
            MobDropdown:Set(AutoFarmConfig.TargetMob) -- 선택
        end

        -- [[ 3. 스킬 설정 ]]
        AutoFarmConfig.AutoSkillEnabled = true
        AutoFarmConfig.Skills.E = true
        AutoFarmConfig.Skills.R = true
        AutoFarmConfig.Skills.T = true

        -- [[ 4. 매크로 방지 설정 ]]
        AntiMacroEnabled = true

        -- [[ 5. 오토팜 시작 ]]
        startAutoFarm()

        -- [[ 6. 알림 띄우기 ]]
        Rayfield:Notify({
            Title = "예티 콘픽 적용됨",
            Content = "설정 완료! 캐릭터를 재설정하여 이동합니다...",
            Duration = 3,
            Image = 4483362458,
        })

        -- [[ 7. 캐릭터 재설정 (Reset) ]]
        local player = game:GetService("Players").LocalPlayer
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.Health = 0
        end
    end,
})

Rayfield:Notify({
    Title = "스크립트 로드 완료",
    Content = "guns.lol/bgsn1.",
    Duration = 6.5,
    Image = 4483362458,
})
