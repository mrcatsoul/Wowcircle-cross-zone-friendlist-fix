local ADDON_NAME,core=...
local _

local colorName = core.colorName or function(n,q,w,e,r,t) return n or "" end

local function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

local ERR_FRIEND_REMOVED_S_localizedPattern = ERR_FRIEND_REMOVED_S:gsub("%%s", "(.+)")
local ERR_FRIEND_ADDED_S_localizedPattern = ERR_FRIEND_ADDED_S:gsub("%%s", "(.+)")

local L = GetLocale()
local ULDUAR = L=="ruRU" and "Ульдуар" or "Ulduar"
local AZSHARA_CRATER = L=="ruRU" and "Кратер Азшары" or "Azshara Crater"

local GetNumFriends,AddFriend,GetFriendInfo,GetTime,ShowFriends = GetNumFriends,AddFriend,GetFriendInfo,GetTime,ShowFriends

local f=CreateFrame("frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, ...) if self[event] then self[event](self, ...) end end)

local function DelayedCall(delay,func)
  local t=0
  CreateFrame("frame"):SetScript("onupdate",function(self,elapsed)
    t = t+elapsed
    if t<delay then return end
    func()
    self:SetScript("onupdate",nil)
    self=nil
  end)
end

local function inCrossZone()
  --print(select(2,IsInInstance()),GetZoneText())
  return --core.inCrossZone or
  select(2,IsInInstance())=="pvp" or
  select(2,IsInInstance())=="arena" or
  GetZoneText()==ULDUAR or
  GetZoneText()==AZSHARA_CRATER
end

local curFriendsNames={}
local lastAddFriendTime=0
local data={}

function f:AddFriend(name)
  if name and name~="" and name~=STRING_SCHOOL_UNKNOWN and not inCrossZone() then
    AddFriend(name)
  end
end

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
  
  f:RegisterEvent("CHAT_MSG_SYSTEM")
  f:RegisterEvent("FRIENDLIST_UPDATE")
  f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function f:CHAT_MSG_SYSTEM(msg)
  -- Проверяем, соответствует ли сообщение шаблону
  local nameRemoved = msg:match(ERR_FRIEND_REMOVED_S_localizedPattern)
  local nameAdded = msg:match(ERR_FRIEND_ADDED_S_localizedPattern)
  
  if nameRemoved then
    nameRemoved = nameRemoved:gsub("^%-?%d*", "")  -- Убирает числовой префикс и знак минус
    nameRemoved = nameRemoved:gsub("[%(%)]", "")  -- Убирает круглые скобки
    
    if inCrossZone() then
      data["RemovedInCrossZoneFriendsNames"][nameRemoved] = data["SavedFriendsNames"][nameRemoved] or ""
      local note = data["RemovedInCrossZoneFriendsNames"][nameRemoved]
      local nameNote = note~="" and colorName(nameRemoved,nil,nil,nil,1,1).."("..note..")" or colorName(nameRemoved,nil,nil,nil,1,1)
      print("" .. nameNote .. " |cffff0000удалился|r из друзей на кроссе, сохранен для добавления заново в мире.")
    end
  elseif nameAdded then
    nameAdded = nameAdded:gsub("^%-?%d*", "")  -- Убирает числовой префикс и знак минус
    nameAdded = nameAdded:gsub("[%(%)]", "")  -- Убирает круглые скобки
    
    if not inCrossZone() then
      if data["RemovedInCrossZoneFriendsNames"][nameAdded] then
        lastAddFriendTime=GetTime()
        local note = data["RemovedInCrossZoneFriendsNames"][nameAdded]
        local nameNote = note~="" and colorName(nameAdded,nil,nil,nil,1,1).."("..note..")" or colorName(nameAdded,nil,nil,nil,1,1)
        print("" .. nameNote .. " |cff00ff00добавлен|r в список друзей заново(по причине бага с удалением на кроссе).")
        if note~="" then
          SetFriendNotes(nameAdded, data["RemovedInCrossZoneFriendsNames"][nameAdded])
        end
        data["RemovedInCrossZoneFriendsNames"][nameAdded]=nil
        --print("dfsdfdsf",data["RemovedInCrossZoneFriendsNames"][nameAdded])
      end
      
      core.checkFriends("nameAdded not inCrossZone",true)
    end
  end
end

-- function f:FRIENDLIST_UPDATE()
  -- print("FRIENDLIST_UPDATE")
  -- local t=GetTime()
  -- if not inCrossZone() and lastAddFriendTime<t then
    -- lastAddFriendTime=t+0.5
    -- core.checkFriends("FRIENDLIST_UPDATE")
  -- end
-- end

function f:PLAYER_ENTERING_WORLD()
  --print("PLAYER_ENTERING_WORLD, inCrossZone:",inCrossZone())
  f:UnregisterEvent("PLAYER_ENTERING_WORLD")
  DelayedCall(1,function()
    core.checkFriends("PLAYER_ENTERING_WORLD",true)
  end)
end

function f:ZONE_CHANGED_NEW_AREA()
  --print("ZONE_CHANGED_NEW_AREA inCrossZone",inCrossZone())
  DelayedCall(1,function()
    core.checkFriends("ZONE_CHANGED_NEW_AREA",true)
  end)
end

local function addRemovedOnCrossZoneFriendsNames()
  if inCrossZone() or tablelength(data["RemovedInCrossZoneFriendsNames"])==0 or GetNumFriends()>=50 then
    return
  end
  
  f.t = 0 
  if f:GetScript("OnUpdate")==nil then
    f:SetScript("OnUpdate", function(_,elapsed)
      f.t = f.t + elapsed
      if f.t < 0.1 then return end 
      f.t = 0

      if inCrossZone() then
        f.started=nil
        f:SetScript("OnUpdate",nil)
        return
      end
      
      if lastAddFriendTime+0.5>GetTime() then
        return
      end
      
      if tablelength(data["RemovedInCrossZoneFriendsNames"])==0 or GetNumFriends()>=50 then
        if GetNumFriends()>=50 then
          print("Список друзей заполнен.")
          
          if tablelength(data["RemovedInCrossZoneFriendsNames"])>0 then
            print("Список временно сохраненных друзей удаленных на кроссе очищен в связи с заполнением настоящего.")
          end
          
          data["RemovedInCrossZoneFriendsNames"]={}
        end
        
        if tablelength(data["RemovedInCrossZoneFriendsNames"])==0 then
          print("Список сохраненных друзей(удаленных на кроссе) пуст, удаление OnUpdate-а.")
        end
        
        f.started=nil
        f:SetScript("OnUpdate",nil)
        return
      end
        
      if not f.started then
        f.started=true
        local text=""..tablelength(data["RemovedInCrossZoneFriendsNames"]).." друзей были удалены на кроссе и могут быть добавлены:"
        for name,note in pairs(data["RemovedInCrossZoneFriendsNames"]) do
          text = text .. " " .. colorName(name,nil,nil,nil,1,1)
          if note~="" then
            text = text.."("..note..")"
          end
        end
        print(text)
      end
      
      --print(tablelength(data["RemovedInCrossZoneFriendsNames"]))
       
      for name,note in pairs(data["RemovedInCrossZoneFriendsNames"]) do
        if not curFriendsNames[name] then
          --if inCrossZone() then break end
          lastAddFriendTime=GetTime()+0.5
          local nameNote = note~="" and colorName(name,nil,nil,nil,1,1).."("..note..")" or colorName(name,nil,nil,nil,1,1)
          print(""..nameNote.." |cffffff00добавляется|r в друзья из очереди сохраненных(удаленных на кроссе)...")
          f:AddFriend(name)
          break
        else
          data["RemovedInCrossZoneFriendsNames"][name]=nil
        end
      end
    end)
  end
end

local function checkFriends(test,forceShowFriends)
  --print("checkFriends,",test,"inCrossZone:",inCrossZone())
  
  table.wipe(curFriendsNames)
  
  if forceShowFriends then
    ShowFriends()
  end
  
  for i=1,GetNumFriends() do
    local name,_,_,_,_,_,note=GetFriendInfo(i)
    if name and name~="" and name~=STRING_SCHOOL_UNKNOWN then 
      curFriendsNames[name] = note or ""
      data["SavedFriendsNames"][name] = note or ""
      --print(colorName(name,nil,nil,nil,1,1),f.SavedFriendsNames[name],"в настоящем списке друзей")
      if not inCrossZone() then
        data["RemovedInCrossZoneFriendsNames"][name]=nil
      end
    end
  end
  
  if not inCrossZone() then
    data["SavedFriendsNames"]=curFriendsNames
  end
  
  addRemovedOnCrossZoneFriendsNames()
end
core.checkFriends=checkFriends

CreateFrame("frame"):SetScript("onupdate",function(f,e)
  f.t=f.t and f.t+e or 0
  f.t2=f.t2 and f.t2+e or 0
  if f.t<.1 then return end
  f.t=0
  if FriendsListFrame and FriendsListFrame:IsVisible() then
    ShowFriends()
    --print("ShowFriends()")
    if f.t2>1 then 
      checkFriends("onupdate",true)
      f.t2=0
    end
  end
end)
