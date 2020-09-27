require "/scripts/util.lua"

local statusList={--progress status doesnt matter, but for any other status indicators, this should be used. it's used for the item network variant to determine completion state
	waiting="^yellow;Waiting for subject...",
	queenID="^green;Queen identified",
	droneID="^green;Drone identified",
	artifactID="^green;Artifact identified",
	invalid="^red;Invalid sample detected"
}

function init()
	defaultMaxStack=root.assetJson("/items/defaultParameters.config").defaultMaxStack
	playerUsing = nil
	selfWorking = nil
	shoveTimer = 0.0

	rank=config.getParameter("rank",0)
	playerWorkingEfficiency = nil
	selfWorkingEfficiency = nil
	status = statusList.waiting
	progress = 0
	futureItem = nil
	bonusEssence=0
	bonusResearch=0

	message.setHandler("paneOpened", paneOpened)
	message.setHandler("paneClosed", paneClosed)
	message.setHandler("getStatus", getStatus)

	playerWorkingEfficiency = config.getParameter("playerWorkingEfficiency")
	selfWorkingEfficiency = config.getParameter("selfWorkingEfficiency")
	selfWorking = config.getParameter("selfWorking")
end

function update(dt)
	if playerUsing or selfWorking then
		local currentItem = world.containerItemAt(entity.id(), 0)

		if currentItem == nil then
			bonusEssence=0
			bonusResearch=0
			status = statusList.waiting
			itemsDropped=false
			progress=0
			futureItem=nil
		elseif not (root.itemHasTag(currentItem.name, "queen") or root.itemHasTag(currentItem.name, "youngQueen") or root.itemHasTag(currentItem.name, "drone") or root.itemHasTag(currentItem.name, "artifact") ) then
			progress=0
			status = statusList.invalid
			futureItem=nil
			currentItem=nil
		else
			if not futureItem then futureItem=currentItem end
			local isQueen=root.itemHasTag(futureItem.name, "queen") or root.itemHasTag(futureItem.name, "youngQueen")
			local isDrone=root.itemHasTag(futureItem.name, "drone")
			local isArtifact=root.itemHasTag(futureItem.name, "artifact")
			if isQueen or isDrone or isArtifact then
				if currentItem.parameters.genomeInspected or (futureItem.parameters.genomeInspected and itemsDropped) then
					if isQueen then
						status = statusList.queenID
					elseif isDrone then
						status = statusList.droneID
					elseif isArtifact then
						status = statusList.artifactID
					end
					shoveTimer=(shoveTimer or 0.0) + dt
					if not (shoveTimer >= 1.0) then return else shoveTimer=0.0 end
					local slotItem=world.containerItemAt(entity.id(),3)
					local singleCountFutureItem=copy(futureItem)
					local singleCountSlotItem=copy(slotItem)
					singleCountFutureItem.count=1
					if singleCountSlotItem then
						singleCountSlotItem.count=1
					end
					if slotItem and not compare(singleCountSlotItem,singleCountFutureItem) then return end
					if not nudgeItem(futureItem,3,slotItem) then return end
					world.containerTakeAt(entity.id(), 0)
					futureItem=nil
					currentItem=nil
				else
					handleProgress(dt)
					if progress >= 100 then
						if isArtifact then futureItem.parameters.category = "^cyan;Researched Artifact^reset;" end
						futureItem.parameters.genomeInspected = true
						local slotItem=world.containerItemAt(entity.id(),3)
						local singleCountFutureItem=copy(futureItem)
						local singleCountSlotItem=copy(slotItem)
						singleCountFutureItem.count=1
						singleCountSlotItem.count=1
						if slotItem and not compare(singleCountSlotItem,singleCountFutureItem) then return end
						if not nudgeItem(futureItem,3,slotItem) then return end
						world.containerTakeAt(entity.id(), 0)
						futureItem=nil
						currentItem=nil
						handleBonuses()
						progress = 0
						if isQueen then
							status = statusList.queenID
						elseif isDrone then
							status = statusList.droneID
						elseif isArtifact then
							status = statusList.artifactID
						end
						itemsDropped=true
					else
						status = "^cyan;"..progress.."%"
						-- ***** chance to gain research *****
						local randCheck = 0
						if isQueen then randCheck=math.random(25)
						elseif isDrone then randCheck=math.random(100)
						elseif isArtifact then randCheck=math.random(10)
						end
						if randCheck == 1 then
							local bonusValue=0
							if isQueen then
								bonusValue=5
							elseif isDrone then
								bonusValue=2
							elseif isArtifact then
								bonusValue=25
							end
							bonusResearch=bonusResearch+((bonusValue+rank)*currentItem.count) -- Gain research as this is used
						elseif randCheck == 2 then
							local bonusValue=0
							if isArtifact then
								bonusValue=1
							end
							bonusEssence=bonusEssence+((1+rank)*currentItem.count)
						end
					end
				end
			else
				status = statusList.invalid
			end
		end
	else
		script.setUpdateDelta(-1)
	end
end

function handleProgress(dt)
	if playerUsing then
		progress = math.min(100,progress + (playerWorkingEfficiency * dt))
	else
		progress = math.min(100,progress + (selfWorkingEfficiency * dt))
	end
	progress = math.floor(progress * 100) * 0.01
end

function handleBonuses()
	if bonusResearch>0 then
		shoveItem({name="fuscienceresource",count=bonusResearch},1)
	end
	if bonusEssence>0 then
		shoveItem({name="essence",count=bonusEssence},2)
	end
	bonusEssence=0
	bonusResearch=0
end

function shoveItem(item,slot)
	if not item then return end
	local slotItem=world.containerItemAt(entity.id(),slot)
	if slotItem and slotItem.name~=item.name then
		if world.containerTakeAt(entity.id(),slot) then
			world.spawnItem(slotItem,entity.position())
		end
	end
	local leftovers=world.containerPutItemsAt(entity.id(),item,slot)
	if leftovers then
		world.spawnItem(leftovers,entity.position())
	end
end

function nudgeItem(item,slot,slotItem)
	sb.logInfo("%s",{item,slot,slotItem})
	--assumptive: compare(item,slotItem) prior to usage returns true, or slotItem is nil
	if not item then return end
	if not slotItem then
		world.containerPutItemsAt(entity.id(),item,slot)
		return true
	end
	local slotItemConfig=slotItem and root.itemConfig(slotItem)
	if slotItemConfig then
		slotItemConfig=util.mergeTable(slotItemConfig.config,slotItemConfig.parameters)
		slotItemConfig=slotItemConfig.maxStack or defaultMaxStack
	end
	sb.logInfo("%s::%s::%s",item.count,slotItem.count,slotItemConfig)
	if (item.count+slotItem.count > slotItemConfig) then return false end
	world.containerPutItemsAt(entity.id(),item,slot)
	return true
end

-- khe's note: use 'requires' and stop being stupid
-- Straight outta util.lua
-- because NOPE to copying an ENTIRE script just for one function
--[[function compare(t1, t2)
	if t1 == t2 then return true end
	if type(t1) ~= type(t2) then return false end
	if type(t1) ~= "table" then return false end
	for k,v in pairs(t1) do if not compare(v, t2[k]) then return false end end
	for k,v in pairs(t2) do if not compare(v, t1[k]) then return false end end
	return true
end]]

function paneOpened()
	script.setUpdateDelta(config.getParameter("scriptDelta"))
	playerUsing = true
end

function paneClosed()
	playerUsing = nil
end

function getStatus()
	if status then return status end
end

function currentlyWorking()
	for id,label in pairs(statusList) do
		if status==label then return false end
	end
	return true
end