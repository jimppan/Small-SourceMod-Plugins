#pragma semicolon 1

#define PLUGIN_AUTHOR "Rachnus"
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

#define DEFLECT_SOUND "physics/metal/metal_barrel_impact_soft2.wav"

#pragma newdecls required

/* Convars */
ConVar g_DeflectForce;
ConVar g_MaxDeflectDist;
ConVar g_ResetGrenadeTimer;
ConVar g_DeflectDotProduct;

ConVar g_DeflectFlash;
ConVar g_DeflectHE;
ConVar g_DeflectMolotov;
ConVar g_DeflectSnowball;
ConVar g_DeflectDecoy;
ConVar g_DeflectSmoke;
ConVar g_DeflectTA;

public Plugin myinfo = 
{
	name = "Ballistic Bouncer v1.0",
	author = PLUGIN_AUTHOR,
	description = "Deflect nades with ballistic shield",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rachnus"
};

public void OnPluginStart()
{
	if(GetEngineVersion() != Engine_CSGO)
		SetFailState("This plugin is for CSGO only.");
		
	HookEvent("weapon_fire", Event_WeaponFire);
	
	g_DeflectForce =      CreateConVar("ballisticbouncer_deflect_force",        "600",    "Amount of force to deflect nades");
	g_MaxDeflectDist =    CreateConVar("ballisticbouncer_max_deflect_distance", "100",    "The max amount of distance between the grenade and the player for a deflect");
	g_ResetGrenadeTimer = CreateConVar("ballisticbouncer_reset_grenade_timer",  "1",      "If enabled, grenades explosion timer will be reset after deflected (HE, Flashes, Mollies)");
	g_DeflectDotProduct = CreateConVar("ballisticbouncer_dot_product",          "0.70",   "Dot between player forward angle and angle from player eyes to grenade position (The higher value, the preciser your aim has to be)", _, true, 0.0, true, 1.0);
	
	g_DeflectFlash =      CreateConVar("ballisticbouncer_deflect_flashbang",    "1",      "If enabled, flashbangs can be deflected");
	g_DeflectHE =         CreateConVar("ballisticbouncer_deflect_he",           "1",      "If enabled, HE grenades can be deflected");
	g_DeflectMolotov =    CreateConVar("ballisticbouncer_deflect_molotov",      "1",      "If enabled, molotovs/incendiaries can be deflected");
	g_DeflectSnowball =   CreateConVar("ballisticbouncer_deflect_snowball",     "1",      "If enabled, snowballs can be deflected");
	g_DeflectDecoy =      CreateConVar("ballisticbouncer_deflect_decoy",        "1",      "If enabled, decoys can be deflected");
	g_DeflectSmoke =      CreateConVar("ballisticbouncer_deflect_smoke",        "1",      "If enabled, smokes can be deflected");
	g_DeflectTA =         CreateConVar("ballisticbouncer_deflect_ta",           "1",      "If enabled, TA grenades can be deflected");
	
	#if defined DEBUG
	RegAdminCmd("sm_ndnade",  Command_GiveBotNade, ADMFLAG_ROOT);
	RegAdminCmd("sm_ndthrow", Command_ThrowNade,   ADMFLAG_ROOT);
	RegAdminCmd("sm_ndequip", Command_EquipNade,   ADMFLAG_ROOT);
	#endif
}

#if defined DEBUG
public Action Command_GiveBotNade(int client, int args)
{
	int target = GetClientAimTarget(client, true);
	if(target == INVALID_ENT_REFERENCE)
		return Plugin_Handled;
		
	GivePlayerItem(target, "weapon_snowball");
	return Plugin_Handled;
}

public Action Command_ThrowNade(int client, int args)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsFakeClient(i))
		{
			int wep = GetEntPropEnt(i, Prop_Data, "m_hActiveWeapon");
			if(wep != INVALID_ENT_REFERENCE)
				SetEntProp(wep, Prop_Send, "m_bPinPulled", 1);
		}		
	}

		
	return Plugin_Handled;
}

public Action Command_EquipNade(int client, int args)
{
	int target = GetClientAimTarget(client, true);
	if(target == INVALID_ENT_REFERENCE)
		return Plugin_Handled;
		
	FakeClientCommand(target, "use weapon_snowball");
	return Plugin_Handled;
}
#endif

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	
	if(StrEqual(weapon, "weapon_shield", true))
		DeflectGrenades(client);
}

public int DeflectEntity(float startPos[3], float deflectDir[3], float addedVelocity[3], const char[] classname)
{
	int deflected = 0;
	int entity = INVALID_ENT_REFERENCE;
	while((entity = FindEntityByClassname(entity, classname)) != INVALID_ENT_REFERENCE)
	{
		float grenadePos[3], dirToNade[3];
		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", grenadePos);
		
		float cmpStartPos[3];
		cmpStartPos = startPos;
		cmpStartPos[2] - 30.0; // Compare at the center of the player

		if(GetVectorDistance(cmpStartPos, grenadePos) > g_MaxDeflectDist.FloatValue)
			continue;
		
		SubtractVectors(grenadePos, startPos, dirToNade);
		NormalizeVector(dirToNade, dirToNade);
		
		float angle = GetVectorDotProduct(dirToNade, deflectDir);
		
		if(angle > g_DeflectDotProduct.FloatValue)
		{
			deflected++;
			float newDir[3];
			newDir = deflectDir;

			ScaleVector(newDir, g_DeflectForce.FloatValue);
			AddVectors(addedVelocity, newDir, newDir);
			
			TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, newDir);
			if(g_ResetGrenadeTimer.BoolValue)
				ResetGrenadeTimer(entity);
		} 
	}
	return deflected;
}

public void DeflectGrenades(int client)
{
	float clientEyePos[3], clientDir[3], playerVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", playerVel);
	GetClientEyePosition(client, clientEyePos);
	GetClientEyeAngles(client, clientDir);
	
	GetAngleVectors(clientDir, clientDir, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(clientDir, clientDir);
	
	int deflected = 0;
	if(g_DeflectHE.BoolValue)       deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "hegrenade_projectile");
	if(g_DeflectFlash.BoolValue)    deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "flashbang_projectile");
	if(g_DeflectMolotov.BoolValue)  deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "molotov_projectile");
	if(g_DeflectSmoke.BoolValue)    deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "smokegrenade_projectile");
	if(g_DeflectDecoy.BoolValue)    deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "decoy_projectile");
	if(g_DeflectSnowball.BoolValue) deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "snowball_projectile");
	if(g_DeflectTA.BoolValue)       deflected += DeflectEntity(clientEyePos, clientDir, playerVel, "tagrenade_projectile");
	
	if(deflected > 0)
		EmitAmbientSound(DEFLECT_SOUND, clientEyePos);
}

public void ResetGrenadeTimer(int entity)
{
	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	if(StrEqual(classname, "hegrenade_projectile", true) || StrEqual(classname, "flashbang_projectile", true))
		SetGrenadeDetonationTime(entity, 1.5); // 1.5 seconds for he/flash
	else if(StrEqual(classname, "molotov_projectile", true) || StrEqual(classname, "incgrenade_projectile", true))
		SetGrenadeDetonationTime(entity, 2.0); // 2 seconds for mollies
}

public void SetGrenadeDetonationTime(int grenade, float time)
{
	SetEntDataFloat(grenade, FindSendPropInfo("CBaseCSGrenadeProjectile", "m_hThrower") + 36, GetGameTime() + time, true);
}

public void OnMapStart()
{
	PrecacheSound(DEFLECT_SOUND);
}
