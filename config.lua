-- config.lua
Config = Config or {}

-- Database bootstrap
Config.UseOxmysql = true
Config.MigrationAutoApply = true

-- Locale handling (UI can leverage this later on)
Config.Locale = 'fr' -- default fr/en

-- Permissions ---------------------------------------------------------------
-- Players must match at least one of these requirements to access management
-- features (Get Coords, create / edit jobs, manage migrations, etc.)
Config.RequiredAcePermission = 'outlawjob.manage'
Config.ManagerIdentifiers = {
  -- Example: 'license:1234567890abcdef',
  -- Example: 'steam:11000010abcdef12'
}

-- Coordinate validation ----------------------------------------------------
Config.AutoSnapToGround = true
Config.RadiusLimits = { min = 0.5, max = 100.0 }
Config.PointMinDistance = 1.5 -- minimum distance between two points (meters)
Config.RestrictedInteriors = {
  -- [interiorId] = true -- add entries here if you need to forbid some interiors
}

-- Water detection tolerance (distance in meters from water height to reject)
Config.WaterTolerance = 0.3

-- Logging ------------------------------------------------------------------
Config.EnableActionLogs = true

-- Keybind suggestion (optional): you can add a RegisterKeyMapping in client
-- Command to open UI: /outlawjob
