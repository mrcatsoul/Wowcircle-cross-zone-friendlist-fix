-- скрипт по восстановление друзей с их заметками обратно в список, чудным образом удалённых на кросс-сервере вовциркуля
-- данные сохраняются в таблицу FriendlistFix_Data в области глобальных переменных

local AUTO_NOTE_BY_NAME = true -- если нет заметки то автозаполнять её ником
local FAST_FRIENDLIST_UPDATE_WHEN_VISIBLE = true -- быстрое обновление френдлиста когда тот открыт
local FAST_FRIENDLIST_UPDATE_INTERVAL = 0.1 -- интервал обновлений открытого френдлиста

local ADDON_NAME, core = ...
_G[ADDON_NAME] = {}

local colorName = core.colorName or function(n,q,w,e,r,t) return n or "" end

local function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

local ERR_FRIEND_LIST_FULL = ERR_FRIEND_LIST_FULL
local ERR_FRIEND_WRONG_FACTION = ERR_FRIEND_WRONG_FACTION
local UNKNOWN = UNKNOWN
local ERR_FRIEND_REMOVED_S_localizedPattern = ERR_FRIEND_REMOVED_S:gsub("%%s", "(.+)")
local ERR_FRIEND_ADDED_S_localizedPattern = ERR_FRIEND_ADDED_S:gsub("%%s", "(.+)")

local L = GetLocale()
local ULDUAR = L=="ruRU" and "Ульдуар" or "Ulduar"
local AZSHARA_CRATER = L=="ruRU" and "Кратер Азшары" or "Azshara Crater"

local GetNumFriends,AddFriend,GetFriendInfo,ShowFriends,SetFriendNotes = GetNumFriends,AddFriend,GetFriendInfo,ShowFriends,SetFriendNotes
local IsInInstance = IsInInstance
local GetTime = GetTime
local UnitIsPVPSanctuary = UnitIsPVPSanctuary
local UnitName = UnitName
local GetRealZoneText = GetRealZoneText
local StaticPopup_Visible = StaticPopup_Visible
local print = print
local select = select
local _

local friendListIsFull
local curFriendsNames,data={},{}
local lastAddFriendTime=0
local currentName

local f=CreateFrame("frame", ADDON_NAME.."Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, ...) if self[event] then self[event](self, ...) end end)

-- функция отложенного вызова другой функции
local DelayedCall
do
  local f = CreateFrame("frame")  -- Создаем один фрейм для всех отложенных вызовов
  local calls = {}  -- Таблица для хранения отложенных вызовов
  
  local function OnUpdate(self, elapsed)
    for i, call in ipairs(calls) do
      call.time = call.time + elapsed
      if call.time >= call.delay then
        call.func()
        tremove(calls, i)  -- Удаляем вызов из списка
      end
    end
  end
  
  f:SetScript("OnUpdate", OnUpdate)
  
  -- Основная функция для отложенных вызовов
  DelayedCall = function(delay, func)
    tinsert(calls, { delay = delay, time = 0, func = func })
  end
end

local function inCrossZone()
  local type = select(2,IsInInstance())
  return 
  type=="pvp" or
  type=="arena" or
  GetRealZoneText()==ULDUAR or
  GetRealZoneText()==AZSHARA_CRATER
  or (type=="raid" and UnitIsPVPSanctuary("player"))
end
_G[ADDON_NAME].inCrossZone=inCrossZone

function f:ADDON_LOADED(...)
  if ... ~= ADDON_NAME then return end
  
  if FriendlistFix_Data==nil then FriendlistFix_Data={} end

  local realm = GetRealmName():gsub("%b[]", ""):gsub("%s+$", "")
  local characterProfileKey = UnitName("player").." ~ "..realm
  
  if FriendlistFix_Data[characterProfileKey] == nil then
    FriendlistFix_Data[characterProfileKey] = {}
  end
  
  data = FriendlistFix_Data[characterProfileKey]
  if data["RemovedInCrossZoneFriendsNames"]==nil then data["RemovedInCrossZoneFriendsNames"]={} end
  if data["SavedFriendsNames"]==nil then data["SavedFriendsNames"]={} end
  
  for k,v in pairs(data) do
    --table.insert(_G[ADDON_NAME], data[k])
    _G[ADDON_NAME][k]=v
  end

  f:RegisterEvent("CHAT_MSG_SYSTEM")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_LEAVING_WORLD")
end

function f:CHAT_MSG_SYSTEM(msg)
  if msg == ERR_FRIEND_LIST_FULL then -- сообщение в чат о том что список друзей заполнен
    friendListIsFull = true
    currentName = nil
  elseif msg == ERR_FRIEND_WRONG_FACTION and currentName then -- сообщение в чат о том что персонаж враждебной фракции
    data["RemovedInCrossZoneFriendsNames"][currentName] = nil
    print("|cffff0000" .. currentName .. " враждебной фракции|r, убираем из сохраненных.|r")
    currentName = nil
  else
    -- Проверяем, соответствует ли сообщение шаблону
    local nameRemoved = msg:match(ERR_FRIEND_REMOVED_S_localizedPattern)
    local nameAdded = msg:match(ERR_FRIEND_ADDED_S_localizedPattern)
    
    if nameRemoved then -- сообщение соответствует шаблону удаления из друзей
      friendListIsFull = nil
      nameRemoved = nameRemoved:gsub("^%-?%d*", "")  -- Убирает числовой префикс и знак минус
      nameRemoved = nameRemoved:gsub("[%(%)]", "")  -- Убирает круглые скобки
      
      if inCrossZone() and nameRemoved~="" and nameRemoved~=UNKNOWN and not data["RemovedInCrossZoneFriendsNames"][nameRemoved] then
        data["RemovedInCrossZoneFriendsNames"][nameRemoved] = data["SavedFriendsNames"][nameRemoved]
        local note = data["RemovedInCrossZoneFriendsNames"][nameRemoved]
        local nameNote = note~="" and colorName(nameRemoved,nil,nil,nil,1,1).."("..note..")" or colorName(nameRemoved,nil,nil,nil,1,1)
        print("|cffff5522" .. nameNote .. " удалился из друзей на кроссе, сохранен для передобавления.|r")
      end
    elseif nameAdded then -- сообщение соответствует шаблону добавления в друзья
      friendListIsFull = nil
      currentName = nil
      nameAdded = nameAdded:gsub("^%-?%d*", "")  -- Убирает числовой префикс и знак минус
      nameAdded = nameAdded:gsub("[%(%)]", "")  -- Убирает круглые скобки
      
      if not inCrossZone() and nameAdded~="" and nameAdded~=UNKNOWN and data["RemovedInCrossZoneFriendsNames"][nameAdded] then
        lastAddFriendTime=GetTime()
        local note = data["RemovedInCrossZoneFriendsNames"][nameAdded]
        --local nameNote = note~="" and colorName(nameAdded,nil,nil,nil,1,1).."("..note..")" or colorName(nameAdded,nil,nil,nil,1,1)
        print("|cff44ff44" .. nameAdded .. " добавлен в список друзей заново.|r")
        if note~="" then
          print("|cff44ff44" .. nameAdded .. " бывшая заметка: "..note.."|r")
          SetFriendNotes(nameAdded, note)
        end
        data["RemovedInCrossZoneFriendsNames"][nameAdded]=nil
        --core.checkFriends("ERR_FRIEND_ADDED",true)
      end
    end
  end
end

function f:FRIENDLIST_UPDATE()
  --print("FRIENDLIST_UPDATE")
  f:checkFriends("FRIENDLIST_UPDATE")
end

function f:PLAYER_ENTERING_WORLD()
  f:UnregisterEvent("PLAYER_ENTERING_WORLD")
  DelayedCall(1, function()
    f:RegisterEvent("FRIENDLIST_UPDATE")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:checkFriends("PLAYER_ENTERING_WORLD",true)
  end)
end

function f:PLAYER_LEAVING_WORLD()
  table.wipe(f.SetFriendNotesQueue)
end

function f:ZONE_CHANGED_NEW_AREA()
  DelayedCall(1, function()
    f:checkFriends("ZONE_CHANGED_NEW_AREA",true)
  end)
end

local function addRemovedOnCrossZoneFriendsNames()
  if inCrossZone() or tablelength(data["RemovedInCrossZoneFriendsNames"])==0 or friendListIsFull --[[GetNumFriends()>=50]] then
    return
  end
  
  f.t = 0 
  if not f:GetScript("OnUpdate") then
    f:SetScript("OnUpdate", function(_,e)
      f.t = f.t + e
      if f.t < 0.1 then return end 
      f.t = 0
      
      if inCrossZone() then
        f.addRemovedStarted=nil
        currentName=nil
        f:SetScript("OnUpdate",nil)
        return
      end
      
      if currentName --[[ or lastAddFriendTime+0.5>GetTime() ]] then
        print("|cffaaaa33Ждем пока чел "..colorName(currentName,nil,nil,nil,1,1).." добавится или нет.|r")
        return
      end
      
      if tablelength(data["RemovedInCrossZoneFriendsNames"])==0 or friendListIsFull --[[GetNumFriends()>=50]] then
        if friendListIsFull --[[GetNumFriends()>=50]] then
          print("|cffff0000Список друзей заполнен.|r")
          
          if tablelength(data["RemovedInCrossZoneFriendsNames"])>0 then
            print("|cffaaaa33Список сохраненных удаленных на кроссе друзей очищен в связи с заполнением настоящего.|r")
          end
          
          data["RemovedInCrossZoneFriendsNames"]={}
        end
        
        if tablelength(data["RemovedInCrossZoneFriendsNames"])==0 then
          print("|cffaaaa33Список сохраненных удаленных на кроссе друзей пуст, удаление скрипта OnUpdate.|r")
        end
        
        f.addRemovedStarted=nil
        currentName=nil
        f:SetScript("OnUpdate",nil)
        return
      end
        
      if not f.addRemovedStarted then
        f.addRemovedStarted=true
        local text="|cffaaaa33"..tablelength(data["RemovedInCrossZoneFriendsNames"]).." друзей были удалены на кроссе и могут быть добавлены:|r"
        for name,note in pairs(data["RemovedInCrossZoneFriendsNames"]) do
          text = text .. " " .. colorName(name,nil,nil,nil,1,1)
          if note~="" then
            text = text.."("..note..")"
          end
        end
        print(text)
      end
      
      for name,note in pairs(data["RemovedInCrossZoneFriendsNames"]) do
        if not curFriendsNames[name] then
          if not inCrossZone() then 
            lastAddFriendTime=GetTime()+0.5
            local nameNote = note~="" and colorName(name,nil,nil,nil,1,1).."("..note..")" or colorName(name,nil,nil,nil,1,1)
            print("|cffaaaa33"..nameNote.." добавляется в друзья из очереди сохраненных удаленных на кроссе.|r")
            currentName=name
            AddFriend(name)
          end
          break
        else
          data["RemovedInCrossZoneFriendsNames"][name]=nil
        end
      end
    end)
  end
end

f.checkFriendsNextTime = 0
f.SetFriendNotesQueue = {}

function f:checkFriends(test,forceShowFriends)
  local time = GetTime()
  if f.checkFriendsNextTime > time or f.checkFriendsInProgress then return end
  f.checkFriendsNextTime = time + 0.5
  f.checkFriendsInProgress = true
  --print("checkFriendsInProgress")
  
  table.wipe(curFriendsNames)
  
  if forceShowFriends then
    ShowFriends()
  end
  
  local count = -1
  for i=GetNumFriends(),1,-1 do
    local name,_,_,_,_,_,note=GetFriendInfo(i)
    if name and name~="" and name~=UNKNOWN then 
      curFriendsNames[name] = note or ""
      if not inCrossZone() then
        if not note and not f.SetFriendNotesQueue[name] and not StaticPopup_Visible("SET_FRIENDNOTE") then
          f.SetFriendNotesQueue[name] = true
          count = count + 1
          DelayedCall(count/2, function()
            if not select(7, GetFriendInfo(name)) and not inCrossZone() and not StaticPopup_Visible("SET_FRIENDNOTE") then
              print(""..name.." автозаметка с ником прописана.")
              SetFriendNotes(name, name)
            end
          end)
        end
        if not f:GetScript("OnUpdate") then
          data["RemovedInCrossZoneFriendsNames"][name]=nil
        end
      end
    end
  end
  
  if not inCrossZone() then
    --print("|cff00dd33SavedFriendsNames +|r")
    table.wipe(data["SavedFriendsNames"])
    for name,note in pairs(curFriendsNames) do
      data["SavedFriendsNames"][name] = note
    end
  end
  
  addRemovedOnCrossZoneFriendsNames()
  f.checkFriendsInProgress = nil
end

-- обновление френдлиста пока тот открыт
if FAST_FRIENDLIST_UPDATE_WHEN_VISIBLE then
  CreateFrame("frame"):SetScript("onupdate",function(f,e)
    f.t=f.t and f.t+e or 0
    f.t2=f.t2 and f.t2+e or 0
    if f.t<FAST_FRIENDLIST_UPDATE_INTERVAL then return end
    f.t=0
    if FriendsListFrame and FriendsListFrame:IsVisible() then
      ShowFriends()
    end
  end)
end
