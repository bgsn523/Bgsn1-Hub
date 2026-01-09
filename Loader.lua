local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local PlaceId = game.PlaceId

-- [[ 알림 전송 함수 ]] --
local function SendAlert(title, text)
    StarterGui:SetCore("SendNotification", {
        Title = title;
        Text = text;
        Duration = 2;
    })
end

SendAlert("Notice","만약 실행에 문제가 있다면 실행기를 바꾸세요!")

-- [[ 기기 감지 로직 ]] --
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- [[ 게임 리스트 설정 ]] --
local GameList = {
    -- 제목 없는 rpg 1세계
    [118582391303761] = {
        Default = "https://raw.githubusercontent.com/bgsn523/Bgns1-Hub/refs/heads/main/scripts/UntitledRPG/1.lua",
        Mobile = "https://raw.githubusercontent.com/bgsn523/Bgsn1-Hub/refs/heads/main/scripts/UntitledRPG/Mobile/mb-1st.lua"
    },

    -- 제목 없는 rpg 2세계
    [117917823443279] = {
        Default = "https://raw.githubusercontent.com/bgsn523/Bgns1-Hub/refs/heads/main/scripts/UntitledRPG/2.lua",
        Mobile = "https://raw.githubusercontent.com/bgsn523/Bgsn1-Hub/refs/heads/main/scripts/UntitledRPG/Mobile/mb-1st.lua"
    },

    -- Blindshot
    [118614517739521] = {
        Default = "https://raw.githubusercontent.com/bgsn523/Bgsn1-Hub/refs/heads/main/scripts/BlindShot/bds.lua",
        Mobile = nil 
    },
}

-- ==================================================================

local GameData = GameList[PlaceId]

if GameData then
    local ScriptUrl = GameData.Default
    local DeviceName = IsMobile and "Mobile" or "PC"

    -- 모바일 전용 링크 체크
    if IsMobile and GameData.Mobile then
        ScriptUrl = GameData.Mobile
    end

    if ScriptUrl then
        SendAlert("Hub Loader", DeviceName .. " 스크립트 로딩 중...")
        
        local success, err = pcall(function()
            loadstring(game:HttpGet(ScriptUrl))()
        end)

        if success then
            -- 로딩 성공 알림
            task.wait(0.5)
            SendAlert("Success", "스크립트가 성공적으로 실행되었습니다.")
        else
            SendAlert("Error", "스크립트 실행 실패: " .. tostring(err))
        end
    else
        SendAlert("Error", "스크립트 주소가 비어있습니다.")
    end
else
    SendAlert("Not Found", "이 맵은 지원되지 않습니다 (ID: " .. PlaceId .. ")")
end
