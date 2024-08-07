require("lua/utils/table_utils.lua")
require("lua/utils/rules_utils.lua")
require("lua/utils/string_utils.lua")
require("lua/utils/numeric_utils.lua")
require("lua/utils/find_utils.lua")

class 'mission_base' ( LuaGraphNode )

function mission_base:__init()
    LuaGraphNode.__init(self,self)
end

function mission_base:GetTileRegionBounds( s, e )
    local world_min = MissionService:GetWorldBoundsMin()
    local world_max = MissionService:GetWorldBoundsMax()
	
    local center_offset = 
    {
        x = math.fmod( ( world_max.x + world_min.x ) / 2.0, 128 ),
        z = math.fmod( ( world_max.z + world_min.z ) / 2.0, 128 ),
    }

    local start_coord = { z = math.min( s.x, e.x ), x = math.min( s.y, e.y ) }
    local end_coord = { z = math.max( s.x, e.x ), x = math.max( s.y, e.y ) }

    local region_min = 
    {
        x = start_coord.x * 128.0 - center_offset.x,
        y = -10,
        z = start_coord.z * 128.0 - center_offset.z
    }

    local region_max = 
    {
        x = ( end_coord.x + 1 ) * 128.0 - center_offset.x,
        y = 40.0,
        z = ( end_coord.z + 1 ) * 128.0 - center_offset.z
    }

    return {
        min = region_min,
        max = region_max
    } 
end

function mission_base:GetNonPlayableRegions()
    local playable_min = MissionService:GetPlayableRegionMin();
    local playable_max = MissionService:GetPlayableRegionMax();

    local margin = tonumber(ConsoleService:GetConfig("map_non_playable_margin"))

    return
    {
		-- Due to camera rotation -x,x is not left right and -z,z is not down up
        [ "spawn_enemy_border_north" ] =
        {
            min = { x = playable_max.x,                 y = -10,    z = playable_min.z },
            max = { x = playable_max.x + margin,        y = 10,     z = playable_max.z } 
        },
        [ "spawn_enemy_border_east" ] =
        {
            min = { x = playable_min.x,                 y = -10,    z = playable_max.z },
            max = { x = playable_max.x,                 y = 10,     z = playable_max.z + margin } 
        },
        [ "spawn_enemy_border_south" ] =
        {
            min = { x = playable_min.x - margin,        y = -10,    z = playable_min.z },
            max = { x = playable_min.x,                 y = 10,     z = playable_max.z } 
        },
        [ "spawn_enemy_border_west" ] =
        {
            min = { x = playable_min.x,                 y = -10,    z = playable_min.z - margin },
            max = { x = playable_max.x,                 y = 10,     z = playable_min.z } 
        },
    };
end


function mission_base:RemoveBlueprintsOutOfPlayableBounds(blueprints)
    local groupBounds = self:GetNonPlayableRegions()
    for group,bounds in pairs( groupBounds ) do
        for blueprint in Iter(blueprints) do
            local entities = FindService:FindEntitiesByBlueprintInBox(blueprint, bounds.min, bounds.max );

            for entity in Iter( entities ) do
                EntityService:RemoveEntity( entity );
            end
        end
    end
end

function mission_base:SetAccessibleWorldRegion( min, max )
    local regions = self:GetNonPlayableRegions()
    for group,_ in pairs( regions ) do
        local entities = FindService:FindEntitiesByGroup( group );
        for entity in Iter( entities ) do
            EntityService:SetName( entity, "" );
            EntityService:SetGroup( entity, "" );

            local children = EntityService:GetChildren( entity, false )
            for child in Iter( children ) do
                if EntityService:GetBlueprintName( child ) == "logic/spawn_enemy_grid_culler" then
                    EntityService:RemoveEntity( child )
                end
            end
        end
    end

    local margin = tonumber(ConsoleService:GetConfig("map_non_playable_margin"))
    min.x = min.x + margin
    min.z = min.z + margin
    max.x = max.x - margin
    max.z = max.z - margin
    
    -- we need to swap x/z here so it maches in game tile grid indexing
    MissionService:SetPlayableRegion( { x = min.z, y = min.y, z = min.x }, { x = max.z, y = max.y, z = max.x } )
    EntityService:SpawnEntity("effects/world/map_resized", 0.0, 0.0, 0.0, "none")
    
    self:PrepareSpawnPoints()
end

function mission_base:SelectWaveSpawnPoints()
    local groupBounds = self:GetNonPlayableRegions()
    for group,bounds in pairs( groupBounds ) do
        local entities = FindService:FindEntitiesByBlueprintInBox("logic/spawn_enemy", bounds.min, bounds.max );
        Assert( #entities > 0, "Failed to find entities for: `" .. group .. "` in bounds:\nMin: " .. tostring(bounds.min.x) .. "," ..tostring(bounds.min.y) .."," ..tostring(bounds.min.z) .. "\nMax: " .. tostring(bounds.max.x) .. "," ..tostring(bounds.max.y) .."," ..tostring(bounds.max.z) )
		
		LogService:Log("[GetNonPlayableRegionsTop] #entities: " .. tostring(#entities) )
		
        for entity in Iter( entities ) do
            EntityService:SetName( entity, group .. "/" .. tostring(entity) );
            EntityService:SetGroup( entity, group );
            EntityService:SpawnAndAttachEntity("logic/spawn_enemy_grid_culler", entity)
        end
    end
end

function mission_base:SelectPlayerSpawnpointNearPosition(spawnPoints)
    local spawn_near_position = self.data:GetStringOrDefault("spawn_near_position", "");
    if IsNullOrEmpty(spawn_near_position) then
        return INVALID_ID
    end

    local tokens = Split(spawn_near_position,",")
    if not Assert( #tokens == 3, "ERROR: invalid format of 'spawn_near_position='" .. spawn_near_position .. "'" ) then
        return INVALID_ID
    end

    local pos = {
        x = tonumber(tokens[1]),
        y = tonumber(tokens[2]),
        z = tonumber(tokens[3]),
    }

    LogService:Log("[MapGenerator] spawn_near_position: " .. tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z))

    local temp = EntityService:SpawnEntity("logic/spawn_player", pos.x, pos.y, pos.z, "")

    local result = FindClosestEntityWithDistance(temp,spawnPoints)
    if Assert( result.entity ~= INVALID_ID, "ERROR: failed to find spawn near requested position!" ) then
        local targetPos = EntityService:GetPosition(result.entity)
        LogService:Log("[MapGenerator] spawn found: " .. tostring(targetPos.x) .. "," .. tostring(targetPos.y) .. "," .. tostring(targetPos.z) .. " distance: " .. tostring(result.distance) )
    end

    EntityService:RemoveEntity( temp )

    return result.entity
end

function mission_base:SelectPlayerSpawnpointForObjectiveTile(spawnPoints)
    local objectiveTile = self.data:GetStringOrDefault("objective_tile", "");
    if IsNullOrEmpty(objectiveTile) then
        return INVALID_ID
    end

    local objectiveMinDistance = self.data:GetFloatOrDefault("objective_min_distance", 0.0);
    local objectiveMaxDistance = self.data:GetFloatOrDefault("objective_max_distance", 10000000000000.0);
    
    local tilePositions = MapGenerator:GetTilePositions( objectiveTile );
    if #tilePositions == 0 then
        return INVALID_ID
    end

    local validSpawns = {}
    local farthestSpawn = {
        distance = 0.0,
        entity = INVALID_ID
    };

    for spawnPoint in Iter( spawnPoints ) do
        local spawnPos = EntityService:GetPosition( spawnPoint );

        local minDistance = 10000000000000.0
        for tileCenter in Iter( tilePositions ) do
            local distance = Distance( spawnPos, tileCenter )
            if distance > farthestSpawn.distance then
                farthestSpawn.distance = distance;
                farthestSpawn.entity = spawnPoint;
            end

            minDistance = math.min( minDistance, distance );
        end

        if minDistance > objectiveMinDistance and minDistance < objectiveMaxDistance then
            Insert(validSpawns, spawnPoint)
        end
    end

    if Assert( #validSpawns > 0, "ERROR: failed to find spawnpoint within objective distance: " .. tostring( objectiveMinDistance ) .. " " .. tostring( objectiveMaxDistance )) then
        local index = RandInt( 1, #validSpawns );
        return validSpawns[ index ];
    end

    return farthestSpawn.entity;
end

function mission_base:SelectPlayerSpawnPoint()
    local spawnPoints = FindService:FindPlayerSpawnPoints();
    if not Assert( #spawnPoints > 0,"ERROR: no player spawn points on map?") then
        return INVALID_ID;
    end

    local spawn_point = self:SelectPlayerSpawnpointForObjectiveTile(spawnPoints)
    if spawn_point ~= INVALID_ID then
        return spawn_point;
    end
    
    spawn_point = self:SelectPlayerSpawnpointNearPosition(spawnPoints)
    if spawn_point ~= INVALID_ID then
        return spawn_point;
    end

    return MapGenerator:SelectSpawnPoint();
end


function mission_base:GetNonPlayableRegionsMy(t)
    return
    {
		-- Due to camera rotation -x,x is not left right and -z,z is not down up
        [ "spawn_enemy_border_north" ] = --북
        {
            min = t.n.min,
            max = t.n.max 
        },
        [ "spawn_enemy_border_east" ] = --동
        {
            min = t.e.min,
            max = t.e.max 
        },
        [ "spawn_enemy_border_south" ] = --남
        {
			min = t.s.min,
            max = t.s.max 
        },
        [ "spawn_enemy_border_west" ] = --서
        {
            min = t.w.min,
            max = t.w.max 
        },
    };
end

function mission_base:RadarPulse(position)
    local radarPulseEffect = EntityService:SpawnEntity( "items/consumables/radar_pulse", position.x,position.y,position.z, "")

	local radarRevealer = EntityService:GetComponent(radarPulseEffect, "FogOfWarRevealerComponent" )
	if ( radarRevealer == nil ) then
		Assert( false, "ERROR: No fog of war revealer component:" )
	end
	
	local helper = reflection_helper( radarRevealer ) 	
	helper.radius = 128
	EntityService:CreateOrSetLifetime( radarPulseEffect, 60, "normal" )
	
end

function mission_base:SelectWaveSpawnPointsMy(t)
    local groupBounds = self:GetNonPlayableRegionsMy(t)	
	
    for group1,bounds in pairs( groupBounds ) do
        local entities = FindService:FindEntitiesByBlueprintInBox("logic/spawn_enemy", bounds.min, bounds.max );
        if Assert( #entities > 0, "Failed to find entities for: `" .. group1 .. "` in bounds:\nMin: " .. tostring(bounds.min.x) .. "," ..tostring(bounds.min.y) .."," ..tostring(bounds.min.z) .. "\nMax: " .. tostring(bounds.max.x) .. "," ..tostring(bounds.max.y) .."," ..tostring(bounds.max.z) ) then
			LogService:Log("[SelectWaveSpawnPointsMy] #entities: " .. tostring(#entities) )
			LogService:Log("[SelectWaveSpawnPointsMy] group1: " .. group1 )
			local position1={
			x=(bounds.min.x+bounds.max.x)/2,
			y=(bounds.min.y+bounds.max.y)/2,
			z=(bounds.min.z+bounds.max.z)/2,
			}
			--BuildingService:CreateRadarComponent( entity1, 128 );
			self:RadarPulse( position1 )
			
			--EntityService:SpawnEntity( "buildings/defense/portal",position1.x,position1.y,position1.z,"player" ) 
			
			for entity1 in Iter( entities ) do
				LogService:Log("[SelectWaveSpawnPointsMy] entity1: " .. tostring(entity1) )
				local position = EntityService:GetPosition( entity1 ) 
				--EntityService:SpawnAndAttachEntity( "buildings/main/headquarters/portal", entity1)
				--EntityService:SpawnEntity( "buildings/defense/portal",position.x,position.y,position.z,"player" ) 
				for group,bounds1 in pairs( groupBounds ) do
					local entity = EntityService:SpawnEntity( "logic/spawn_enemy",position.x,position.y,position.z,"" ) 
					LogService:Log("[SelectWaveSpawnPointsMy] entity: " .. tostring(entity) )
					EntityService:SetName( entity, group .. "/" .. tostring(entity) );
					EntityService:SetGroup( entity, group );
					EntityService:SpawnAndAttachEntity("logic/spawn_enemy_grid_culler", entity)
				end
			end
			return 0
		end
    end
	return 1
end

function mission_base:PrepareSpawnPoints(safeRadius)
    if MapGenerator:GetInitialSpawnPoint() == INVALID_ID then
        local spawn_point = self:SelectPlayerSpawnPoint();
        MapGenerator:SetInitialSpawnPoint( spawn_point );
    end

    local playable_min = MissionService:GetPlayableRegionMin();
    local playable_max = MissionService:GetPlayableRegionMax();
	local margin = tonumber(ConsoleService:GetConfig("map_non_playable_margin"));
	local rt=1
	local ar={}		
	
	local margin1=4
	EntityService:SpawnEntity( "buildings/defense/portal",0,0,0,"player" ) 
	
	EntityService:SpawnEntity( "buildings/defense/portal",playable_min.x+margin*margin1,10,playable_max.z-margin*margin1,"player" ) 
	EntityService:SpawnEntity( "buildings/defense/portal",playable_min.x+margin*margin1,10,playable_min.z+margin*margin1,"player" ) 
	EntityService:SpawnEntity( "buildings/defense/portal",playable_max.x-margin*margin1,10,playable_min.z+margin*margin1,"player" ) 
	EntityService:SpawnEntity( "buildings/defense/portal",playable_max.x-margin*margin1,10,playable_max.z-margin*margin1,"player" ) 
	
	EntityService:SpawnEntity( "buildings/defense/portal",0,10,playable_max.z-margin*margin1,"player" ) 
	EntityService:SpawnEntity( "buildings/defense/portal",0,10,playable_min.z+margin*margin1,"player" ) 
	EntityService:SpawnEntity( "buildings/defense/portal",playable_max.x-margin*margin1,10,0,"player" ) 
	EntityService:SpawnEntity( "buildings/defense/portal",playable_max.x-margin*margin1,10,0,"player" ) 

	-- TOP Center
	if rt>0 then
		rt=self:SelectWaveSpawnPointsMy({
		-- z:가로 x:세로
        n = --북
        {
            min = { x = playable_max.x - margin*1,      y = -10,    z = (playable_max.z+playable_min.z)/2 - margin*2 },
            max = { x = playable_max.x + margin,        y = 10,     z = (playable_max.z+playable_min.z)/2 + margin*2 } 
        },
        e = --동
        {
            min = { x = (playable_max.x+playable_min.x)/2  + margin*2,  y = -10,    z = playable_max.z - margin*1 },
            max = { x = (playable_max.x+playable_min.x)/2  - margin*2,  y = 10,     z = playable_max.z + margin } 
        },
        s = --남
        {
            min = { x = playable_min.x - margin,        y = -10,    z = (playable_max.z+playable_min.z)/2 + margin*2 },
            max = { x = playable_min.x + margin*1,      y = 10,     z = (playable_max.z+playable_min.z)/2 - margin*2 } 
        },
        w = --서
        {
            min = { x = (playable_max.x+playable_min.x)/2  + margin*2,   y = -10,    z = playable_min.z - margin },
            max = { x = (playable_max.x+playable_min.x)/2  - margin*2,   y = 10,     z = playable_min.z + margin*1 } 
        },
    })
		LogService:Log("[SelectWaveSpawnPointsMy] TOP Corner : " .. tostring(rt) )
	end
	-- Corner
	if rt>0 then
		rt=self:SelectWaveSpawnPointsMy({
		-- z:가로 x:세로
        w = --서북
        {
            min = { x = playable_max.x - margin*3,      y = -10,    z = playable_min.z - margin },
            max = { x = playable_max.x + margin,        y = 10,     z = playable_min.z + margin*3} 
        },
        n = --북동
        {
            min = { x = playable_max.x - margin*3,      y = -10,    z = playable_max.z - margin*3 } ,
            max = { x = playable_max.x + margin,        y = 10,     z = playable_max.z + margin}
        },
        e = --동남
        {
            min = { x = playable_min.x - margin,        y = -10,    z = playable_max.z - margin*3},
            max = { x = playable_min.x + margin*3,      y = 10,     z = playable_max.z + margin } 
        },
        s = --남서
        {
            min = { x = playable_min.x - margin,        y = -10,    z = playable_min.z - margin} ,
            max = { x = playable_min.x + margin*3,      y = 10,     z = playable_min.z + margin*3 }
        },
    })
		LogService:Log("[SelectWaveSpawnPointsMy] Corner : " .. tostring(rt) )
	end
	-- Center
	if rt>0 then
		rt=self:SelectWaveSpawnPointsMy({w={
				min = { x = (playable_max.x+playable_min.x)/2 - margin,        y = -10,    z = (playable_max.z+playable_min.z)/2 - margin },
				max = { x = (playable_max.x+playable_min.x)/2 + margin,        y = 10,     z = (playable_max.z+playable_min.z)/2 + margin } 
			},e={
				min = { x = (playable_max.x+playable_min.x)/2 - margin*1.5,        y = -10,    z = (playable_max.z+playable_min.z)/2 - margin*1.5 },
				max = { x = (playable_max.x+playable_min.x)/2 + margin*1.5,        y = 10,     z = (playable_max.z+playable_min.z)/2 + margin*1.5 } 
			},s={
				min = { x = (playable_max.x+playable_min.x)/2 - margin*2,        y = -10,    z = (playable_max.z+playable_min.z)/2 - margin*2 },
				max = { x = (playable_max.x+playable_min.x)/2 + margin*2,        y = 10,     z = (playable_max.z+playable_min.z)/2 + margin*2 } 
			},n={
				min = { x = (playable_max.x+playable_min.x)/2 - margin*2.5,        y = -10,    z = (playable_max.z+playable_min.z)/2 - margin*2.5 },
				max = { x = (playable_max.x+playable_min.x)/2 + margin*2.5,        y = 10,     z = (playable_max.z+playable_min.z)/2 + margin*2.5 } 
			},})
		LogService:Log("[SelectWaveSpawnPointsMy] Center : " .. tostring(rt) )
	end
	-- TOP
	if rt>0 then
		rt=self:SelectWaveSpawnPointsMy({n={
            min = { x = playable_max.x,                 y = -10,    z = playable_min.z },
            max = { x = playable_max.x + margin,        y = 10,     z = playable_max.z } 
        },s={
            min = { x = playable_min.x - margin,        y = -10,    z = playable_min.z },
            max = { x = playable_min.x ,                y = 10,     z = playable_max.z } 
        },e={
            min = { x = playable_min.x,                 y = -10,    z = playable_max.z },
            max = { x = playable_max.x,                 y = 10,     z = playable_max.z + margin} 
        },w={
            min = { x = playable_min.x,                 y = -10,    z = playable_min.z - margin },
            max = { x = playable_max.x,                 y = 10,     z = playable_min.z } 
        },})
		LogService:Log("[SelectWaveSpawnPointsMy] TOP : " .. tostring(rt) )
	end
	-- 
	if rt>0 then
		self:SelectWaveSpawnPoints();
	end
    --self:RemoveBlueprintsOutOfPlayableBounds({ "logic/spawn_objective" });

    return spawn_point
end

function mission_base:init()
    self:PrepareSpawnPoints();
	--ConsoleService:ExecuteCommand("cheat_finish_all_research")
	ConsoleService:ExecuteCommand("r_show_map_info 1")
end

function mission_base:Activated()
	self:RegisterHandler( event_sink, "LuaGlobalEvent", "_OnLuaGlobalEvent" )
end

function mission_base:OnMissionFinish( status )
    MissionService:FinishCurrentMission( status )
end

function mission_base:_OnLuaGlobalEvent( evt)
    if (evt:GetEvent() == "win_game") then
        self:OnMissionFinish( MISSION_STATUS_WIN )
    elseif ( evt:GetEvent() == "lose_game") then
        self:OnMissionFinish( MISSION_STATUS_LOSE )
    elseif( evt:GetEvent() == "change_world_bounds") then
        local params = evt:GetDatabase()

        local minX = params:GetIntOrDefault("minX", -1)
        local minY = params:GetIntOrDefault("minY", -1)
        local maxX = params:GetIntOrDefault("maxX", 1)
        local maxY = params:GetIntOrDefault("maxY", 1)

        if params:HasString("min") then
            local min = Split(params:GetString("min"), "," )
            minX = tonumber(min[1])
            minY = tonumber(min[2])
        end

        if params:HasString("max") then
            local max = Split(params:GetString("max"), "," )
            maxX = tonumber(max[1])
            maxY = tonumber(max[2])
        end
        
        local world_region = self:GetTileRegionBounds( { x = minX, y = minY }, { x = maxX, y = maxY } )
        self:SetAccessibleWorldRegion( world_region.min, world_region.max )
    end
end

function mission_base:OnLoad()
    if ( self:HasEventHandler( event_sink, "LuaGlobalEvent") == false ) then
        self:RegisterHandler( event_sink, "LuaGlobalEvent", "_OnLuaGlobalEvent" )
    end
end
return mission_base