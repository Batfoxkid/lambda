#pragma semicolon 1

#include <sourcemod>
#include <dhooks>

#pragma newdecls required

#define	SF_NPCMAKER_START_ON		1	// start active ( if has targetname )
#define SF_NPCMAKER_NPCCLIP		8	// Children are blocked by NPCclip
#define SF_NPCMAKER_FADE			16	// Children's corpses fade
#define SF_NPCMAKER_INF_CHILD		32	// Infinite number of children
#define	SF_NPCMAKER_NO_DROP		64	// Do not adjust for the ground's position when checking for spawn
#define SF_NPCMAKER_HIDEFROMPLAYER		128	// Don't spawn if the player's looking at me
#define SF_NPCMAKER_ALWAYSUSERADIUS	256	// Use radius spawn whenever spawning
#define SF_NPCMAKER_NOPRELOADMODELS	512	// Suppress preloading into the cache of all referenced .mdl files

enum struct SpawnForward
{
	Function Func;
	bool Post;
	Handle Plugin;
	char Classname[64];
}

ArrayList SpawnHooks;
char LastClassname[64];
DynamicHook HookMakeNPC;
GlobalForward ForwardSpawner;
Handle CallDeathNotice;
Handle CallCanMakeNPC;
Handle CallChildPreSpawn;
Handle CallChildPostSpawn;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	ForwardSpawner = new GlobalForward("LF_OnMakeNPC", ET_Event, Param_String, Param_CellByRef);
	CreateNative("LF_HookSpawn", Native_HookSpawn);
	CreateNative("LF_UnhookSpawn", Native_UnhookSpawn);
	return APLRes_Success;
}

public void OnPluginStart()
{
	SpawnHooks = new ArrayList(sizeof(SpawnForward));
	
	GameData gamedata = LoadGameConfigFile("lambda");
	
	DynamicDetour detour = DynamicDetour.FromConf(gamedata, "CEntityFactoryDictionary::Create");
	detour.Enable(Hook_Pre, DHook_EntityCreated);
	delete detour;
	
	HookMakeNPC = DynamicHook.FromConf(gamedata, "MakeNPC");
	if(!HookMakeNPC)
		SetFailState("Offset ''MakeNPC'' is invalid");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "DeathNotice");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	CallDeathNotice = EndPrepSDKCall();
	if(!CallDeathNotice)
		SetFailState("Offset ''DeathNotice'' is invalid");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseNPCMaker::CanMakeNPC");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	CallCanMakeNPC = EndPrepSDKCall();
	if(!CallCanMakeNPC)
		SetFailState("Signature ''CBaseNPCMaker::CanMakeNPC'' is invalid");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "ChildPreSpawn");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	CallChildPreSpawn = EndPrepSDKCall();
	if(!CallChildPreSpawn)
		SetFailState("Offset ''ChildPreSpawn'' is invalid");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "ChildPostSpawn");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	CallChildPostSpawn = EndPrepSDKCall();
	if(!CallChildPostSpawn)
		SetFailState("Offset ''ChildPostSpawn'' is invalid");
	
	delete gamedata;
	
	/*HookEntityOutput("math_counter", "OutValue", OnCounterValue);
}

public Action OnCounterValue(const char[] sOutput, int iCaller, int iActivator, float flDelay)
{
	char sTargetName[128];
	GetEntPropString(iCaller, Prop_Data, "m_iName", sTargetName, sizeof(sTargetName));
	
	static int iOffset = -1;
	iOffset = FindDataMapInfo(iCaller, "m_OutValue");
	PrintToChatAll("%s %f", sTargetName, GetEntDataFloat(iCaller, iOffset));*/
}

void DeathNotice(int entity, int victim)
{
	SDKCall(CallDeathNotice, entity, victim);
}

bool CanMakeNPC(int entity, bool ignoreEntities=false)
{
	return SDKCall(CallCanMakeNPC, entity, ignoreEntities);
}

void ChildPreSpawn(int entity, int child)
{
	SDKCall(CallChildPreSpawn, entity, child);
}

void ChildPostSpawn(int entity, int child)
{
	SDKCall(CallChildPostSpawn, entity, child);
}

public MRESReturn DHook_EntityCreated(DHookReturn ret, DHookParam param)
{
	char classname[64];
	param.GetString(1, classname, sizeof(classname));
	strcopy(LastClassname, sizeof(LastClassname), classname);
	
	Action action = Plugin_Continue;
	SpawnForward hook;
	int length = SpawnHooks.Length;
	for(int i; i<length; i++)
	{
		SpawnHooks.GetArray(i, hook);
		if(!hook.Post && (!hook.Classname[0] || StrEqual(classname, hook.Classname, false)))
		{
			Action action2;
			Call_StartFunction(hook.Plugin, hook.Func);
			Call_PushStringEx(classname, sizeof(classname), SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
			Call_Finish(action2);
			if(action2 > action)
				action = action2;
		}
	}
	
	switch(action)
	{
		case Plugin_Changed:
		{
			param.SetString(1, classname);
			return MRES_ChangedHandled;
		}
		case Plugin_Handled, Plugin_Stop:
		{
			ret.Value = view_as<Handle>(null);
			return MRES_Supercede;
		}
	}
	return MRES_Ignored;
}

public MRESReturn DHook_MakerMakeNPC(int entity)
{
	if(CanMakeNPC(entity))
	{
		char buffer[256];
		GetEntPropString(entity, Prop_Data, "m_iszNPCClassname", buffer, sizeof(buffer));
		
		int npc = -1;
		Action action;
		Call_StartForward(ForwardSpawner);
		Call_PushStringEx(buffer, sizeof(buffer), SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCellRef(npc);
		Call_Finish(action);
		
		switch(action)
		{
			case Plugin_Continue, Plugin_Changed:
			{
				npc = CreateEntityByName(buffer);
			}
			case Plugin_Stop:
			{
				return MRES_Supercede;
			}
		}
		
		if(npc > MaxClients)
		{
			SetVariantString(buffer);
			FireEntityOutput(entity, "OnSpawnNPC", npc);
			
			float pos[3], ang[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
			GetEntPropVector(entity, Prop_Send, "m_angRotation", ang);
			ang[1] = 0.0;
			ang[2] = 0.0;
			
			TeleportEntity(npc, pos, ang, NULL_VECTOR);
			
			ChildPreSpawn(entity, npc);
			
			if(action != Plugin_Handled)
				DispatchSpawn(npc);
			
			SetEntPropEnt(npc, Prop_Data, "m_hOwnerEntity", entity);
			
			if(action != Plugin_Handled)
				ActivateEntity(npc);
			
			GetEntPropString(entity, Prop_Data, "m_ChildTargetName", buffer, sizeof(buffer));
			if(buffer[0])
				SetEntPropString(entity, Prop_Data, "m_iName", buffer);
			
			ChildPostSpawn(entity, npc);
			
			SetEntProp(entity, Prop_Data, "m_nLiveChildren", GetEntProp(entity, Prop_Data, "m_nLiveChildren")+1);
			
			// DeathNotice won't call itself
			/*DataPack pack;
			CreateDataTimer(0.5, Timer_LiveChildCheck, pack, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
			pack.WriteCell(EntIndexToEntRef(npc));
			pack.WriteCell(EntIndexToEntRef(entity));*/
		}
		
		if(!(GetEntProp(entity, Prop_Data, "m_spawnflags") & SF_NPCMAKER_INF_CHILD))
		{
			int amount = GetEntProp(entity, Prop_Data, "m_nMaxNumNPCs")-1;
			SetEntProp(entity, Prop_Data, "m_nMaxNumNPCs", amount);
			if(amount < 1)
			{
				FireEntityOutput(entity, "OnAllSpawned", entity);
				AcceptEntityInput(entity, "Disable");
			}
		}
	}
	return MRES_Supercede;
}

public MRESReturn DHook_TemplateMakeNPC(int entity)
{
	//PrintToChatAll("DHook_TemplateMakeNPC::%d", entity);
	return MRES_Supercede;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "npc_maker"))
	{
		HookMakeNPC.HookEntity(Hook_Pre, entity, DHook_MakerMakeNPC);
	}
	else if(StrEqual(classname, "npc_template_maker"))
	{
		HookMakeNPC.HookEntity(Hook_Pre, entity, DHook_TemplateMakeNPC);
	}
	
	SpawnForward hook;
	int length = SpawnHooks.Length;
	for(int i; i<length; i++)
	{
		SpawnHooks.GetArray(i, hook);
		if(hook.Post && (!hook.Classname[0] || StrEqual(LastClassname, hook.Classname, false)))
		{
			Call_StartFunction(hook.Plugin, hook.Func);
			Call_PushString(LastClassname);
			Call_PushCell(entity);
			Call_Finish();
		}
	}
}

public Action Timer_LiveChildCheck(Handle timer, DataPack pack)
{
	pack.Reset();
	int entity = EntRefToEntIndex(pack.ReadCell());
	if(entity > MaxClients)
		return Plugin_Continue;
	
	entity = EntRefToEntIndex(pack.ReadCell());
	if(entity > MaxClients)
		DeathNotice(entity, entity);
	
	return Plugin_Stop;
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	int id = -1;
	while((id=SpawnHooks.FindValue(plugin, SpawnForward::Plugin)) != -1)
	{
		SpawnHooks.Erase(id);
	}
}

public any Native_HookSpawn(Handle plugin, int numParams)
{
	SpawnForward hook;
	hook.Plugin = plugin;
	GetNativeString(1, hook.Classname, sizeof(hook.Classname));
	hook.Func = GetNativeFunction(2);
	hook.Post = GetNativeCell(3);
	SpawnHooks.PushArray(hook);
}

public any Native_UnhookSpawn(Handle plugin, int numParams)
{
	char classname[64];
	GetNativeString(1, classname, sizeof(classname));
	Function func = GetNativeFunction(2);
	bool post = GetNativeCell(3);
	
	SpawnForward hook;
	int length = SpawnHooks.Length;
	for(int i; i<length; i++)
	{
		SpawnHooks.GetArray(i, hook);
		if(hook.Plugin == plugin &&
		   hook.Post == post &&
		   hook.Func == func &&
		   StrEqual(hook.Classname, classname))
		{
			SpawnHooks.Erase(i);
			return true;
		}
	}
	return false;
}
