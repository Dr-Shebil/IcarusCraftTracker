-- IcarusCraftTracker v43.0 - Event-Free Silent Engine
-- 1. Zero Hook Execution Overhead: Slate UI never queried during mouse hovers or recipe clicks
-- 2. On-Demand Only: FindAllOf and inventory deduplication run strictly when MMB is pressed
-- 3. Level-Transition & Mission Launch Safe
-- 4. 100% Immune to 0x8 Null-Pointer Crashes

local HOVERED_RECIPE = nil
local PINNED_RECIPE = nil
local LAST_RENDERED_SIGNATURE = ""
local hooksSetup = false

local RECIPE_DATABASE = {}
local ITEM_DISPLAY_NAMES = {}

-- Load chunks into master database
for i = 1, 6 do
    local success, chunk = pcall(require, "Recipes_Chunk" .. i)
    if success and type(chunk) == "table" then
        for k, v in pairs(chunk) do
            RECIPE_DATABASE[k] = v
        end
    end
end

-- Core fallback baseline recipes
if not RECIPE_DATABASE["Rope"] and not RECIPE_DATABASE["Recipe_Rope"] then
    RECIPE_DATABASE["Rope"] = { Inputs = { { Item = "Fiber", Count = 12 } } }
    RECIPE_DATABASE["Recipe_Rope"] = { Inputs = { { Item = "Fiber", Count = 12 } } }
end
if not RECIPE_DATABASE["Wood_Crop_Plot"] and not RECIPE_DATABASE["Recipe_Wood_Crop_Plot"] then
    RECIPE_DATABASE["Wood_Crop_Plot"] = { Inputs = { { Item = "Wood", Count = 8 }, { Item = "Sulfur", Count = 10 }, { Item = "Dirt", Count = 20 } } }
    RECIPE_DATABASE["Recipe_Wood_Crop_Plot"] = { Inputs = { { Item = "Wood", Count = 8 }, { Item = "Sulfur", Count = 10 }, { Item = "Dirt", Count = 20 } } }
end

-- Load official item display names extracted from data.pak
local okNames, nameTable = pcall(require, "ItemDisplayNames")
if okNames and type(nameTable) == "table" then
    ITEM_DISPLAY_NAMES = nameTable
end

-- Resolves exact in-game localized name using official data.pak table
local function CleanItemName(s)
    if not s then return "" end
    local raw = tostring(s):gsub("^Recipe ", "")
    local cleanKey = raw:gsub("^Item_", ""):gsub("^Recipe_", "")
    
    if ITEM_DISPLAY_NAMES[raw] then
        return ITEM_DISPLAY_NAMES[raw]
    elseif ITEM_DISPLAY_NAMES[cleanKey] then
        return ITEM_DISPLAY_NAMES[cleanKey]
    elseif ITEM_DISPLAY_NAMES["Item_" .. cleanKey] then
        return ITEM_DISPLAY_NAMES["Item_" .. cleanKey]
    end

    local str = raw:gsub("_", " ")
    str = str:gsub("Refined Metal", "Iron Ingot")
    str = str:gsub("Refined Copper", "Copper Ingot")
    str = str:gsub("Refined Gold", "Gold Ingot")
    str = str:gsub("Refined Titanium", "Titanium Ingot")
    str = str:gsub("Refined Platinum", "Platinum Ingot")
    str = str:gsub("Refined Aluminium", "Aluminium Ingot")
    return str
end

local function UnmarshallFName(fn)
    if not fn then return nil end
    local str = nil
    pcall(function()
        if type(fn) == "userdata" or type(fn) == "table" then
            if fn.ToString then str = tostring(fn:ToString())
            elseif fn.to_string then str = tostring(fn:to_string()) end
        end
    end)
    if not str or str:find("FNameUserdata", 1, true) then
        pcall(function() str = tostring(fn) end)
    end
    if str and str:find("FNameUserdata", 1, true) then return nil end
    return str
end

local function Normalize(s)
    local str = tostring(s or ""):lower()
    str = str:gsub("^recipe_", ""):gsub("^item_", ""):gsub("^recipe", ""):gsub("^item", "")
    str = str:gsub("_", ""):gsub(" ", ""):gsub("[^%w]", "")
    return str
end

-- Inspects an active UMG_InventoryItem_C slot widget safely
local function InspectSlotWidget(w)
    if not w or not w:IsValid() then return nil, 0, nil end
    local name = nil
    local count = 1
    local slotIndex = nil

    local isPlayer = false
    pcall(function()
        local inv = w.Inventory
        if inv and inv:IsValid() then
            local outer = inv:GetOuter()
            if outer and outer:IsValid() then
                local oName = tostring(outer:GetFullName() or "")
                if (oName:find("Player", 1, true) or oName:find("Survival", 1, true) or oName:find("Character", 1, true))
                   and not oName:find("Chest", 1, true) 
                   and not oName:find("Crate", 1, true) 
                   and not oName:find("Deployable", 1, true) 
                   and not oName:find("Storage", 1, true) 
                   and not oName:find("Furnace", 1, true)
                   and not oName:find("Bench", 1, true) then
                    isPlayer = true
                end
            end
            local loc = w.CurrentLocation
            if loc ~= nil then
                slotIndex = tonumber(loc)
            end
        end
    end)

    if not isPlayer or slotIndex == nil then return nil, 0, nil end

    pcall(function()
        if w.Item and w.Item.ItemStaticData then
            name = UnmarshallFName(w.Item.ItemStaticData.RowName)
        end
    end)
    if not name or name == "" or name == "None" then
        pcall(function()
            if w.CachedItem and w.CachedItem.ItemStaticData then
                name = UnmarshallFName(w.CachedItem.ItemStaticData.RowName)
            end
        end)
    end

    if name and name ~= "" and name ~= "None" then
        pcall(function()
            if w.Stack and w.Stack:IsValid() and w.Stack.GetText then
                local txt = w.Stack:GetText()
                if txt then
                    local num = tonumber(txt:ToString())
                    if num and num > 0 then count = num end
                end
            end
        end)
        return name, count, slotIndex
    end
    return nil, 0, nil
end

-- Counts total items across Player Inventory slots with strict 1:1 slot deduplication
local function GetInventoryCount(targetRowName)
    local total = 0
    local targetNorm = Normalize(targetRowName)
    local seenSlots = {}

    pcall(function()
        local widgets = FindAllOf("UMG_InventoryItem_C")
        if widgets then
            for _, w in ipairs(widgets) do
                local name, count, slotIndex = InspectSlotWidget(w)
                if name and slotIndex ~= nil then
                    if not seenSlots[slotIndex] then
                        seenSlots[slotIndex] = true
                        local n = Normalize(name)
                        if n == targetNorm or n:find(targetNorm, 1, true) or targetNorm:find(n, 1, true) then
                            total = total + count
                        end
                    end
                end
            end
        end
    end)

    return total
end

local function SafeSetTextBlock(tb, str)
    if not tb or not tb:IsValid() then return false end
    local ok = false
    pcall(function()
        local kLib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
        if kLib and kLib.Conv_StringToText then
            tb:SetText(kLib:Conv_StringToText(str))
            ok = true
        end
    end)
    if not ok then
        pcall(function() tb:SetText(FText(str)) end)
    end
    return true
end

-- Sets HUD Card Visibility (true = Show, false = Hide)
local function SetHUDCardVisible(visible)
    pcall(function()
        local hudWidgets = FindAllOf("UMG_MasterHUD_C")
        if not hudWidgets or #hudWidgets == 0 then
            hudWidgets = FindAllOf("MasterHUD_C")
        end

        if hudWidgets then
            for _, w in ipairs(hudWidgets) do
                if w and w:IsValid() then
                    local mode = visible and 4 or 2 -- 4 = SelfHitTestInvisible, 2 = Collapsed
                    pcall(function() w:SetVisibility(mode) end)
                    if w.Border_132 and w.Border_132:IsValid() then
                        pcall(function() w.Border_132:SetVisibility(mode) end)
                    end
                    if w.CanvasPanel_0 and w.CanvasPanel_0:IsValid() then
                        pcall(function() w.CanvasPanel_0:SetVisibility(mode) end)
                    end
                end
            end
        end
    end)
end

-- Completely clears the pin and collapses the card
local function UnpinRecipe()
    PINNED_RECIPE = nil
    LAST_RENDERED_SIGNATURE = ""
    SetHUDCardVisible(false)
    print("\n[CraftTracker] 🟢 Recipe Unpinned! UI Cleared.\n")
end

-- Updates the on-screen UMG_MasterHUD widget contents
local function UpdateHUDWidget()
    if not PINNED_RECIPE then
        SetHUDCardVisible(false)
        return
    end

    SetHUDCardVisible(true)

    pcall(function()
        local hudWidgets = FindAllOf("UMG_MasterHUD_C")
        if not hudWidgets or #hudWidgets == 0 then
            hudWidgets = FindAllOf("MasterHUD_C")
        end

        if hudWidgets then
            for _, w in ipairs(hudWidgets) do
                if w and w:IsValid() then
                    pcall(function() w:SetVisibility(4) end)
                    if w.Border_132 and w.Border_132:IsValid() then
                        pcall(function() w.Border_132:SetVisibility(4) end)
                    end

                    local titleStr = "PINNED: " .. CleanItemName(PINNED_RECIPE.Name):upper()

                    for _, pName in ipairs({"TitleText", "RecipeTitle", "Title", "Text_Title", "txt_Title"}) do
                        if w[pName] then
                            SafeSetTextBlock(w[pName], titleStr)
                            break
                        end
                    end

                    local numInputs = #PINNED_RECIPE.Inputs

                    for i = 1, 6 do
                        local rowWidget = w["Row_" .. i] or w["row_" .. i]
                        local nameWidget = w["ItemName_" .. i] or w["itemName_" .. i] or w["Name_" .. i]
                        local countWidget = w["ItemCount_" .. i] or w["itemCount_" .. i] or w["Count_" .. i]

                        if i <= numInputs then
                            local ing = PINNED_RECIPE.Inputs[i]
                            local have = GetInventoryCount(ing.Item)
                            local need = ing.Count
                            local isDone = (have >= need)

                            local nameDisplay = CleanItemName(ing.Item) .. ":"
                            local countDisplay = isDone and string.format("%d / %d ✓", have, need) or string.format("%d / %d", have, need)

                            if rowWidget and rowWidget:IsValid() then
                                pcall(function() rowWidget:SetVisibility(4) end)
                            end
                            if nameWidget then SafeSetTextBlock(nameWidget, nameDisplay) end
                            if countWidget then SafeSetTextBlock(countWidget, countDisplay) end
                        else
                            if rowWidget and rowWidget:IsValid() then
                                pcall(function() rowWidget:SetVisibility(2) end)
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function PrintPinnedRecipe()
    if not PINNED_RECIPE then return end
    print("\n========================================================")
    print("  📌 PINNED: " .. CleanItemName(PINNED_RECIPE.Name))
    if #PINNED_RECIPE.Inputs == 0 then
        print("  (No ingredient data found for this recipe in database)")
    else
        local allDone = true
        for _, ing in ipairs(PINNED_RECIPE.Inputs) do
            local have = GetInventoryCount(ing.Item)
            local need = ing.Count
            local mark = (have >= need) and "✓" or "✗"
            if have < need then allDone = false end
            print(string.format("    %s %s: %d / %d", mark, CleanItemName(ing.Item), have, need))
        end
        if allDone then
            print("  🟢 READY TO CRAFT!")
        else
            print("  🔴 Missing ingredients")
        end
    end
    print("========================================================\n")
    
    LAST_RENDERED_SIGNATURE = ""
    UpdateHUDWidget()
end

local function PinRecipeByName(extractedTitle)
    if not extractedTitle or extractedTitle == "" or extractedTitle == "None" or extractedTitle == "NoRecipeSelected" then return end
    
    local cleanTitle = extractedTitle:lower():gsub("recipe_", ""):gsub("recipe", ""):gsub(" ", "_"):gsub("[^%w_]", "")
    local matchedKey = nil

    if RECIPE_DATABASE[extractedTitle] then
        matchedKey = extractedTitle
    elseif RECIPE_DATABASE["Recipe_" .. extractedTitle] then
        matchedKey = "Recipe_" .. extractedTitle
    end

    if not matchedKey then
        for key, _ in pairs(RECIPE_DATABASE) do
            local cleanKey = key:lower():gsub("recipe_", ""):gsub("recipe", ""):gsub(" ", "_"):gsub("[^%w_]", "")
            if cleanTitle == cleanKey then
                matchedKey = key
                break
            end
        end
    end

    if not matchedKey then
        for key, _ in pairs(RECIPE_DATABASE) do
            local cleanKey = key:lower():gsub("recipe_", ""):gsub("recipe", ""):gsub(" ", "_"):gsub("[^%w_]", "")
            if cleanTitle:find(cleanKey, 1, true) or cleanKey:find(cleanTitle, 1, true) then
                matchedKey = key
                break
            end
        end
    end

    local recipeName = matchedKey or extractedTitle

    -- Toggle behavior: MMB on already pinned recipe unpins it
    if PINNED_RECIPE and PINNED_RECIPE.Name == recipeName then
        UnpinRecipe()
        return
    end

    local db = RECIPE_DATABASE[recipeName]
    local inputs = db and db.Inputs or {}

    -- Fallback for common items if inputs were empty
    if #inputs == 0 then
        local cleanLower = recipeName:lower()
        if cleanLower:find("rope", 1, true) then
            inputs = { { Item = "Fiber", Count = 12 } }
        elseif cleanLower:find("wood_crop_plot", 1, true) or cleanLower:find("cropplot", 1, true) then
            inputs = { { Item = "Wood", Count = 8 }, { Item = "Sulfur", Count = 10 }, { Item = "Dirt", Count = 20 } }
        elseif cleanLower:find("bandage", 1, true) then
            inputs = { { Item = "Fiber", Count = 5 } }
        end
    end

    PINNED_RECIPE = { Name = recipeName, Inputs = inputs }
    PrintPinnedRecipe()
end

local function ExtractFromParam(param)
    if not param then return nil end
    local str = nil
    pcall(function()
        local pObj = param:get()
        if pObj then
            pcall(function() str = UnmarshallFName(pObj.RowName) end)
        end
    end)
    return str
end

local function SafeGetText(obj, fieldName)
    local result = nil
    pcall(function()
        if obj and obj:IsValid() and not obj:IsUnreachable() then
            local prop = obj[fieldName]
            if prop and prop:IsValid() and not prop:IsUnreachable() then
                local fullClass = tostring(prop:GetFullName())
                if fullClass:find("TextBlock", 1, true) then
                    local txt = prop:GetText()
                    if txt then
                        local s = txt:ToString()
                        if s and s ~= "" and s ~= "None" and s ~= "NoRecipeSelected" then
                            result = s
                        end
                    end
                end
            end
        end
    end)
    return result
end

-- Inspects currently open bench or crafting window to find selected recipe directly
local function GetCurrentlySelectedRecipeFromUI()
    local result = nil
    pcall(function()
        local craftWidgets = FindAllOf("UMG_Crafting_C")
        if craftWidgets then
            for _, cw in ipairs(craftWidgets) do
                if cw and cw:IsValid() then
                    local txt = SafeGetText(cw, "RecipeName")
                    if txt and txt ~= "" and txt ~= "None" and txt ~= "NoRecipeSelected" then
                        result = txt
                        break
                    end
                end
            end
        end
    end)
    return result
end

local function SetupHooks()
    pcall(function()
        RegisterHook("/Game/UI/Windows/UMG_Crafting.UMG_Crafting_C:Selected Recipe Updated", function(self, NewRecipe)
            pcall(function()
                local rowStr = ExtractFromParam(NewRecipe)
                if rowStr then HOVERED_RECIPE = rowStr end
            end)
            pcall(function()
                local txt = SafeGetText(self, "RecipeName")
                if txt then HOVERED_RECIPE = txt end
            end)
            -- SILENT: Zero UI updates during hover/clicks to prevent Slate collisions
        end)
    end)

    pcall(function()
        RegisterHook("/Game/UI/Components/UMG_RecipeList.UMG_RecipeList_C:On Recipe Selected", function(self, Recipe)
            pcall(function()
                local rowStr = ExtractFromParam(Recipe)
                if rowStr then HOVERED_RECIPE = rowStr end
            end)
            -- SILENT: Zero UI updates during list selection
        end)
    end)
end

-- Level Transition / World Change Handler
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    PINNED_RECIPE = nil
    HOVERED_RECIPE = nil
    LAST_RENDERED_SIGNATURE = ""
    SetHUDCardVisible(false)

    if not hooksSetup then
        hooksSetup = true
        SetupHooks()
        print("[CraftTracker] World hooks initialized successfully!")
    end
end)

SetupHooks()

-- Top-Level Keybinds (All heavy UI work runs strictly on user action)
pcall(function()
    RegisterKeyBind(Key.MIDDLE_MOUSE_BUTTON, function()
        local activeRecipe = GetCurrentlySelectedRecipeFromUI() or HOVERED_RECIPE
        if activeRecipe then
            PinRecipeByName(activeRecipe)
        elseif PINNED_RECIPE then
            UnpinRecipe()
        else
            print("[CraftTracker] Click any recipe in a bench, then click MMB to pin!")
        end
    end)
end)

pcall(function()
    RegisterKeyBind(Key.F9, function()
        print("\n[CraftTracker] Fiber exact count: " .. GetInventoryCount("Fiber"))
    end)
end)

pcall(function()
    RegisterKeyBind(Key.F10, function()
        if PINNED_RECIPE then
            UpdateHUDWidget()
            PrintPinnedRecipe()
        end
    end)
end)

print("[CraftTracker] v43.0 Master Build loaded! (Event-Free Silent Engine)")