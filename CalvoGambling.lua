local ADDON_NAME = "CalvoGambling"

--SavedVariables
Gon_Env = {
    stats = {},
    mainChars = {},
}

local channels = {
    default = "RAID",
    raid = "RAID",
    party = "PARTY",
    guild = "GUILD",
}
local chatEvents = {
    RAID = {"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER"},
    PARTY = {"CHAT_MSG_PARTY_LEADER", "CHAT_MSG_PARTY"},
    GUILD = {"CHAT_MSG_GUILD"}
}
local currentChannel = channels["raid"]
local PLAYERLIST = {}
local GAME_IN_PROGRESS = false
local SIGN_UP_IN_PROGRESS = false
local ROLLS_IN_PROGRESS = false
local SavedVariablesLoaded = false
local GAME_AMOUNT = -1

local GameFrame, SignUpFrame, LoadFrame

local function stringSplit (inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local function sendMessage(msg, channel)
    SendChatMessage(msg, channel, nil)
end

local function resetGame ()
    GAME_IN_PROGRESS = false
    SIGN_UP_IN_PROGRESS = false
    ROLLS_IN_PROGRESS = false
    GAME_AMOUNT = -1
    PLAYERLIST = {}
    currentChannel = channels["default"]
    GameFrame:UnregisterAllEvents()
end

local function startSignUp ()
    GAME_IN_PROGRESS = true
    SIGN_UP_IN_PROGRESS = true
    for _,v in pairs(chatEvents[currentChannel]) do
        SignUpFrame:RegisterEvent(v)
    end
end

local function updateStats (winner, loser, payout)
    -- Point towards the correct main character (Max 10 intermediate links)
    local i = 1
    repeat
        local out = false
        local res = Gon_Env.mainChars[winner] or winner
        if res ~= winner then
            winner = res
        else
            out = true
        end
    until out or i > 10

    i = 1
    repeat
        local out = false
        local res = Gon_Env.mainChars[loser] or loser
        if res ~= loser then
            loser = res
        else
            out = true
        end
    until out or i > 10

    Gon_Env.stats[winner] = (Gon_Env.stats[winner] or 0) + payout
    Gon_Env.stats[loser] = (Gon_Env.stats[loser] or 0) - payout
end

local function endGame ()
    local maxPlayer, maxRoll = "", -1
    local minPlayer, minRoll = "", GAME_AMOUNT+1
    for player, roll in pairs(PLAYERLIST) do
        if roll > maxRoll then
            maxPlayer, maxRoll = player, roll
        end
        if roll < minRoll then
            minPlayer, minRoll = player, roll
        end
    end
    local payout = maxRoll - minRoll
    local msgbody = string.format("%s owes %s %d gold. Good luck next time!", minPlayer, maxPlayer, payout)
    sendMessage(msgbody, currentChannel)
    updateStats(maxPlayer, minPlayer, payout)
    resetGame()
end

local function initiateGame (params)
    if GAME_IN_PROGRESS then
        print("There is already a game in progress!")
        return
    end
    if not params[2] or not tonumber(params[2]) then
        print("Quantity needs to be correctly set")
    end

    currentChannel = params[3] and channels[params[3]:lower()] or channels["default"]

    local body = string.format([[Welcome to %s: type 1 in chat to join the game or -1 to leave it. Bet is set to %s. Happy Gambling!]], ADDON_NAME, params[2])
    GAME_AMOUNT = tonumber(params[2])
    sendMessage(body, currentChannel)
    startSignUp()
end

local function indioTV (params)
    local channel = params[2] and channels[params[2]:lower()] or channels["default"]
    local newparams = {"indiotv", 10, channel}
    initiateGame(newparams)
end

local function abortGame ()
    local body = [[Game has been aborted. You get to keep your gold!]]
    sendMessage(body, currentChannel)
    resetGame()
end

local function rollStart ()
    if not SIGN_UP_IN_PROGRESS then
        print("You need to start a game first!")
        return
    end
    if #PLAYERLIST < 2 then
        print("")
    end
    SIGN_UP_IN_PROGRESS = false
    ROLLS_IN_PROGRESS = true
    SignUpFrame:UnregisterAllEvents()
    GameFrame:RegisterEvent("CHAT_MSG_SYSTEM")

    local msgbody = [[Start Rolling! Good luck and have fun.]]
    sendMessage(msgbody, currentChannel)
end

local function gameStats (params)
    local channel = channels["default"]
    if params[2] then
        channel = channels[params[2]:lower()]
    end

    local statsTable = {}
    for player, balance in pairs(Gon_Env.stats) do
        local entry = {
            player = player,
            balance = balance,
        }
        table.insert(statsTable, entry)
    end
    table.sort(statsTable, function (a,b) return a.balance > b.balance end)
    sendMessage(string.format("----- %s stats -----", ADDON_NAME), channel)
    for i, v in ipairs(statsTable) do
        local player = v.player
        local balance = v.balance
        local verb = balance > 0 and "won" or "lost"
        local messagebody = string.format("%d. %s %s %d gold.", i, player, verb, math.abs(balance))
        sendMessage(messagebody, channel)
    end
end

local function linkChar (params)
    if not params[2] and params[3] then
        print("You need to input both the main character's name and the alter's name")
        return
    end
    local alter = params[3]:gsub("^%l", string.upper)
    local main = params[2]:gsub("^%l", string.upper)
    updateStats(main, alter,Gon_Env.stats[alter] or 0)
    Gon_Env.stats[alter] = nil
    Gon_Env.mainChars[alter] = main
    print(string.format("Player %s set as an alter of %s", alter, main))
end

local function unlinkChar (params)
    if not params[2] then
        print("You need to input a player name!")
        return
    end
    Gon_Env.mainChars[params[2]] = nil
end

local function resetStats ()
    Gon_Env.stats = {}
    print("Stats have been reset")
end

local function printUsage ()
    print(
            [[
            ------  Commands for CalvoGambling  ------
            ** Channel is one of "party", "raid" or "guild". **
            indioTV <channel>: Starts a roll for 10g. Defaults to raid.
            start <qty> <channel>: Starts sign up phase for a game for the specified quantity. Defaults to raid.
            roll: Stops the sign up phase and starts the game.
            abort: Aborts the current game.
            stats <channel>: Posts the saved statistics to the specified channel. Defaults to raid.
            link <main> <alter>: Links two characters.
            unlink <character>: Gets rid of links where <character> is set as an alter
            resetStats: Fully resets statistics. This is not reversible!
            ]]
    )
end

local function whosLeft ()
    for player, roll in pairs(PLAYERLIST) do
        if roll < 0 then
            local body = "Player " .. player .. " still needs to roll"
			sendMessage(body, currentChannel)
        end
    end
end

local function CalvoGambling_SlashCmd (param)
    if not SavedVariablesLoaded then
        print("Please wait a second while the addon loads")
        return
    end
    local options = {
        indiotv = indioTV,
        start = initiateGame,
        abort = abortGame,
        stats = gameStats,
        roll = rollStart,
        link = linkChar,
        unlink = unlinkChar,
        resetstats = resetStats,
		whosleft = whosLeft,
    }
    local params = stringSplit(param)
    local opt = params[1] and params[1]:lower() or nil
    local handler = options[opt] or printUsage

    handler(stringSplit(param))
end

local function gameHandler (self, event, ...)
    local msg = ...
    if msg:find("rolls") then
        local words = stringSplit(msg, " ")
        local player = words[1]
        local value = tonumber(words[3])
        local toplimit = stringSplit(words[4], "-")[2]
        toplimit = tonumber(toplimit:sub(1,#toplimit-1))
        if toplimit == GAME_AMOUNT and PLAYERLIST[player] == -1 then
            PLAYERLIST[player] = value
        end
        for _,v in pairs(PLAYERLIST) do
            if v == -1 then
                return
            end
        end
        -- Everyone has rolled
        endGame()
    end
end

local function signUpHandler (self, event, ...)
    local msg, player = ...
    player = stringSplit(player, "-")[1]
    if msg == "1" then
        PLAYERLIST[player] = -1
    elseif msg == "-1" then
        PLAYERLIST[player] = nil
    end
end

local function CalvoGambling_OnLoad ()
    LoadFrame = CreateFrame("Frame")
    LoadFrame:RegisterEvent("ADDON_LOADED")
    GameFrame = CreateFrame("Frame")
    SignUpFrame = CreateFrame("Frame")
    GameFrame:SetScript("OnEvent", gameHandler)
    SignUpFrame:SetScript("OnEvent", signUpHandler)
    LoadFrame:SetScript("OnEvent", function(self, event, ...)
        local addon = ...
        if addon:lower() == ADDON_NAME:lower() then
            SavedVariablesLoaded = true
        end
    end
    )
end

SLASH_CalvoGambling1 = "/gon"
SLASH_CalvoGambling2 = "/calvo"
SLASH_CalvoGambling3 = "/cg"
SlashCmdList["CalvoGambling"] = CalvoGambling_SlashCmd

CalvoGambling_OnLoad()