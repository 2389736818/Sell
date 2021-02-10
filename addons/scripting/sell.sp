#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define PLUGIN_VERSION "1.2"
#define MAX_FILE_LEN 80
#define MAX_NUM_WEAPONS 30
#define WEAPON_STRING_SIZE 30
#define MAX_MONEY 16000

// Plugin definitions
public Plugin myinfo = 
{
	name = "Sell!",
	author = "AMP Kittencn",
	description = "Allows players to sell their weapons back",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net"
};

// Global Variables
Handle hGameConf = INVALID_HANDLE;
Handle hEquipWeapon = INVALID_HANDLE;
Handle g_CvarMultiplier = INVALID_HANDLE;
int g_weaponCount;
char g_weaponNames[MAX_NUM_WEAPONS][WEAPON_STRING_SIZE];
int g_weaponCost[MAX_NUM_WEAPONS];
int iBuyZone = -1;
int iAccount = -1;
int iMyWeapons = -1;

public void OnPluginStart()
{
	// Create the CVARs
	CreateConVar("sm_sell_version", PLUGIN_VERSION, "Sell! Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_CvarMultiplier = CreateConVar("sm_c4_timer_multiplier", "1.0", "Multpier for the sell price");
	
	// Get offsets
	iBuyZone = FindSendPropInfo("CCSPlayer", "m_bInBuyZone");
	iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
	iMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
	
	// Load the gamedata file
	hGameConf = LoadGameConfigFile("sell.games");
	if(hGameConf == INVALID_HANDLE)
	{
		SetFailState("gamedata/sell.games.txt not loadable");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Weapon_Equip");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hEquipWeapon = EndPrepSDKCall();

	LoadConfig();
}

// Once the configs have executed we register the admin commands if appropriate
public void OnConfigsExecuted()
{
	RegConsoleCmd("sm_sell", CommandSell);
}

// This is called when the sm_last command is executed
public Action CommandSell(int client, int args)
{
	if(client < 1 || client > MaxClients)
	{
		ReplyToCommand(client, "You must be a real client in order to sell!");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client))
	{
		ReplyToCommand(client, "You must be in the game in order to sell!");
		return Plugin_Handled;
	}	
	if(!IsClientInBuyZone(client))
	{
		PrintToChat(client, "You must be in a buy zone to sell!");
		return Plugin_Handled;
	}
	if(args != 1)
	{
		ReplyToCommand(client, "Usage: sm_sell <pri|sec>");
		return Plugin_Handled;
	}

	// Get the command argument
	char buffer[50];
	GetCmdArg(1, buffer, sizeof(buffer));
	
	// Associate the slot with item type
	//new slot;
	int weaponEntity;
	char weapon[WEAPON_STRING_SIZE];
	if(!strcmp(buffer, "pri"))
	{
		weaponEntity = GetPlayerWeaponSlot(client, 0);
	} else if(!strcmp(buffer, "sec")) {
		weaponEntity = GetPlayerWeaponSlot(client, 1);
	} else if(!strcmp(buffer, "cur")) {
		GetClientWeapon(client, weapon, sizeof(weapon));
		weaponEntity = FindWeaponByName(client, weapon);
	} else if(!strcmp(buffer, "gre")) {
		weaponEntity = GetPlayerWeaponSlot(client, 3);
	} else if(!strcmp(buffer, "all")) {
		SellAll(client);
		return Plugin_Handled;
	} else if(!strcmp(buffer, "menu")) {
		SellMenu(client);
		return Plugin_Handled;
	} else {
		weaponEntity = FindWeaponByName(client, buffer);
	}
		
	if(weaponEntity == -1)
	{
		PrintToChat(client, "Nothing to sell");
		return Plugin_Handled;
	}
	
	if(!SellWeapon(client, weaponEntity))
	{
		GetEdictClassname(weaponEntity, weapon, sizeof(weapon));
		PrintToChat(client, "This server does not allow you to sell the %s", weapon[7]);
	} else {
		EquipAvailableWeapon(client);
	}
		
	return Plugin_Handled;
}

// Loads the costs out the configuration file
public void LoadConfig()
{
	Handle kv = CreateKeyValues("sell");
	char filename[MAX_FILE_LEN];

	BuildPath(Path_SM, filename, MAX_FILE_LEN, "configs/sell.cfg");
	FileToKeyValues(kv, filename);
	
	if (!KvGotoFirstSubKey(kv))
	{
		SetFailState("configs/sell.cfg not found or not correctly structured");
		return;
	}

	g_weaponCount = 0;
	do {
		KvGetSectionName(kv, g_weaponNames[g_weaponCount], WEAPON_STRING_SIZE);
		g_weaponCost[g_weaponCount] = KvGetNum(kv, "cost", 0);
		if(g_weaponCost[g_weaponCount] > 0)
		{
			g_weaponCount++;
		}
	} while(KvGotoNextKey(kv) && g_weaponCount < MAX_NUM_WEAPONS);
	
	if(g_weaponCount == MAX_NUM_WEAPONS)
	{
		PrintToServer("Stopped reading weapons file after %s, too many weapons", g_weaponNames[g_weaponCount - 1]);
	}
	
	CloseHandle(kv);
}

// checks to see if a given client is in a buy zone
public bool IsClientInBuyZone(int client)
{
	return GetEntData(client, iBuyZone, 1) ? true : false;
}

public FindWeaponByName(int client, char[] weapon)
{
	// The client needs to be valid or bad things could happen
	if(!(client && IsClientInGame(client)))
	{
		return -1;
	}
	
	// search through the players inventory for the weapon
	int weaponEntity;
	char slotWeapon[WEAPON_STRING_SIZE];
	for(new i = 0; i < 32; i++)
	{
		weaponEntity = GetEntDataEnt2(client, iMyWeapons + i * 4);
		if(weaponEntity && weaponEntity != -1)
		{
			GetEdictClassname(weaponEntity, slotWeapon, sizeof(slotWeapon));
			if(strcmp(weapon, slotWeapon) == 0)
			{
				return weaponEntity;
			}
		}
	}
	
	// if we get to here than we didn't find the weapon we were searching for
	return -1;
}

//  This creates the menu
public Action SellMenu(int client)
{
	Handle menu = CreateMenu(MenuHandlerSell);
	char weapon[WEAPON_STRING_SIZE];
	char entityString[5];
	
	SetMenuTitle(menu, "Sell! Menu");
	
	// Add a menu item for each valid weapon
	int weaponEntity;
	for(int i = 0; i < 32; i++)
	{
		weaponEntity = GetEntDataEnt2(client, iMyWeapons + i * 4);
		if(weaponEntity && weaponEntity != -1)
		{
			GetEdictClassname(weaponEntity, weapon, sizeof(weapon));
			IntToString(weaponEntity, entityString, sizeof(entityString));
			AddMenuItem(menu, entityString, weapon[7]);
		}
	}
	
	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 15);
 
	return Plugin_Handled;
}

//  This handles the selling
public int MenuHandlerSell(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)	{
		// first get the entity string out of the menuitem
		char entityString[5];
		GetMenuItem(menu, param2, entityString, sizeof(entityString));
		
		// now, just to be safe double check and make sure this entity is still in the list
		int weaponEntity = StringToInt(entityString);
		for(int i = 0; i < 32; i++)
		{
			if(weaponEntity > 0 && weaponEntity == GetEntDataEnt2(param1, iMyWeapons + i * 4))
			{
				if(!SellWeapon(param1, weaponEntity))
				{
					char weapon[WEAPON_STRING_SIZE];
					GetEdictClassname(weaponEntity, weapon, sizeof(weapon));
					PrintToChat(param1, "This server does not allow you to sell the %s", weapon[7]);
				} else {
					EquipAvailableWeapon(param1);
				}
				SellMenu(param1);
				return;
			}
		}
		char weapon[WEAPON_STRING_SIZE];
		GetEdictClassname(weaponEntity, weapon, sizeof(weapon));
		PrintToChat(param1, "You don't have the %s anymore", weapon[7]);
		SellMenu(param1);
	} else if(action == MenuAction_End)	{
		CloseHandle(menu);
	}
}

public bool SellWeapon(int client, int weaponEntity)
{
	// Get the name of the weapon
	char weapon[WEAPON_STRING_SIZE];
	GetEdictClassname(weaponEntity, weapon, sizeof(weapon));
	
	// Find out which weapon matches the weapon in question
	int pos = 0;
	while(pos < g_weaponCount)
	{
		if(StrEqual(weapon, g_weaponNames[pos]))
		{
			// Increase the money
			int money = GetEntData(client, iAccount) + RoundToNearest(float(g_weaponCost[pos]) * GetConVarFloat(g_CvarMultiplier));
			SetEntData(client, iAccount, money < MAX_MONEY ? money : MAX_MONEY);
			
			// Remove the wepon
			RemovePlayerItem(client, weaponEntity);
			RemoveEdict(weaponEntity);
			return true;
		}
		pos++;
	}
	return false;
}

public void SellAll(int client)
{
	// The client needs to be valid or bad things could happen
	if(!(client && IsClientInGame(client)))
	{
		return;
	}
	
	// search through the players inventory for the weapon
	int weaponEntity;
	for(int i = 0; i < 32; i++)
	{
		weaponEntity = GetEntDataEnt2(client, iMyWeapons + i * 4);
		if(weaponEntity && weaponEntity != -1)
		{
			SellWeapon(client, weaponEntity);
		}
	}
	EquipAvailableWeapon(client);
}

public void EquipAvailableWeapon(int client)
{
	// Find a new weapon to equip
	int pos = 0;
	int weaponEntity = -1;
	do {
		weaponEntity = GetPlayerWeaponSlot(client, pos);
		pos++;
	} while(weaponEntity == -1 && pos < 5);
	if(weaponEntity != -1)
		SDKCall(hEquipWeapon, client, weaponEntity);
}
