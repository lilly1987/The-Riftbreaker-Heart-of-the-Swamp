local building_base = require("lua/buildings/building_base.lua");

class 'building' ( building_base )

function building:__init()
	building_base.__init(self)
end

function building:init()
	building_base.init(self)	
	self:RegisterHandler( self.entity, "AnimationMarkerReached", "OnAnimationMarkerReached" ) 
	self:RegisterHandler( self.entity, "DamageEvent", "OnDamageEvent" )

	self.resourceMissing = {}
end

function building:OnAnimationMarker( markerName )

end

function building:OnAnimationMarkerReached(evt)
	EffectService:AttachEffects(self.entity, evt:GetMarkerName())
	self:OnAnimationMarker( evt:GetMarkerName())
end

function building:OnDamage( evt )
end

function building:OnDamageEvent(evt)
	self:OnDamage(evt)
end

function building:_OnBuildingResourceMissing()
	if BuildingService:IsBuildingPowered(self.entity) then
		local buildingName = BuildingService:GetBuildingName(self.entity)
		if (buildingName == "carbonium_factory" or buildingName == "steel_factory" or buildingName == "rare_element_mine") then
			if not BuildingService:IsOnResource(self.entity, "carbon_vein") and not BuildingService:IsOnResource(self.entity, "iron_vein") and not BuildingService:IsOnResource(self.entity, "uranium_ore_vein") and not BuildingService:IsOnResource(self.entity, "titanium_vein") and not BuildingService:IsOnResource(self.entity, "palladium_vein") and not BuildingService:IsOnResource(self.entity, "cobalt_vein") then
				BuildingService:DisableBuilding(self.entity)
			end
		end
	end
end

return building