#include <sdktools>
#include <sdkhooks>

#define EF_BONEMERGE                (1 << 0)
#define EF_NOSHADOW                 (1 << 4)
#define EF_NORECEIVESHADOW          (1 << 6)

#define HEADSCALE 1.0
//#define HEADPROP "models/props/de_dust/hr_dust/dust_soccerball/dust_soccer_ball001.mdl"
#define HEADPROP "models/player/holiday/facemasks/facemask_tf2_spy_model.mdl"
#define HEADATTACH "facemask"

#define NORMATTACH "primary"

ConVar cColor[2];
ConVar cDefault;
ConVar cLifeState;
ConVar cNotify;
ConVar cTeam;
ConVar cModel;

int colors[2][4];

bool isUsingESP[MAXPLAYERS+1];
bool canSeeESP[MAXPLAYERS+1];
int playersInESP = 0;
ConVar sv_force_transmit_players;

int playerModels[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE,...};
int playerModelsIndex[MAXPLAYERS+1] = {-1,...};

int playerTeam[MAXPLAYERS+1] = {0,...};

#define PLUGIN_NAME    "Advanced Admin ESP"
#define PLUGIN_VERSION "1.3.6"
public Plugin myinfo = {
    name        = PLUGIN_NAME,
    author      = "Mitch",
    description = "Allow admins to use a server side ESP/WH",
    version     = PLUGIN_VERSION,
    url         = "mtch.tech"
};

public OnPluginStart() {
    sv_force_transmit_players = FindConVar("sv_force_transmit_players");
    // Create plugin console variables on success
    CreateConVar("sm_advanced_esp_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
    cColor[0] = CreateConVar("sm_advanced_esp_tcolor",  "144 120 72", "Determines R G B glow colors for Terrorists team\nFormat should be \"R G B\" (with spaces)", 0);
    cColor[1] = CreateConVar("sm_advanced_esp_ctcolor", "72 96 144", "Determines R G B glow colors for Counter-Terrorists team\nFormat should be \"R G B\" (with spaces)", 0);
    cDefault = CreateConVar("sm_advanced_esp_default", "0", "Set to 1 if admins should automatically be given ESP", 0);
    cLifeState = CreateConVar("sm_advanced_esp_lifestate", "0", "Set to 1 if admins should only see esp when dead, 2 to only see esp while alive, 0 dead or alive.", 0);
    cNotify = CreateConVar("sm_advanced_esp_notify", "0", "Set to 1 if giving and setting esp should notify the rest of the server.", 0);
    cTeam = CreateConVar("sm_advanced_esp_team", "0", "0 - Display all teams, 1 - Display enemy, 2 - Display teammates", 0);
    cModel = CreateConVar("sm_advanced_esp_model", "0", "0 - Use current model (full body glow), 1 - Use facemask model on head", 0);
    AutoExecConfig(true, "csgo_advanced_esp");
    cColor[0].AddChangeHook(ConVarChange);
    cColor[1].AddChangeHook(ConVarChange);
    cLifeState.AddChangeHook(ConVarChange);
    cTeam.AddChangeHook(ConVarChange);
    cModel.AddChangeHook(ConVarChange);
    for(int i = 0; i <= 1; i++) {
        retrieveColorValue(i);
    }

    LoadTranslations("common.phrases");
    LoadTranslations("esp.phrases");

    RegAdminCmd("sm_giveesp", Command_GiveESP, ADMFLAG_RCON); //Give other players
    RegAdminCmd("sm_esp", Command_ESP, ADMFLAG_GENERIC);

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);

    playersInESP = 0;
}

public void ConVarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
    for(int i = 0; i <= 1; i++) {
        if(convar == cColor[i]) {
            retrieveColorValue(i);
        }
    }
    checkGlows();
}

public void retrieveColorValue(int index) {
    char pieces[4][16];
    char color[64];
    cColor[index].GetString(color, sizeof(color));
    if(ExplodeString(color, " ", pieces, sizeof(pieces), sizeof(pieces[])) >= 3) {
        for(int j = 0; j < 3; j++) {
            colors[index][j] = StringToInt(pieces[j]);
        }
    }
}

public Action Command_GiveESP(client, args) {
    if(args < 1) {
        ReplyToCommand(client, "[SM] sm_giveesp <player/#userid> [0/1]");
        return Plugin_Handled;
    }
    char arg1[32];
    char targetName[MAX_TARGET_LENGTH+8];
    int clientList[MAXPLAYERS];
    int clientCount;
    bool multiLang;
    GetCmdArg(1, arg1, sizeof(arg1));
    if((clientCount = ProcessTargetString(arg1,client,clientList,MAXPLAYERS,COMMAND_FILTER_CONNECTED,targetName,sizeof(targetName),multiLang)) <= 0) {
        ReplyToTargetError(client, clientCount);
        return Plugin_Handled;
    }
    bool value = false;
    if(args > 1) {
        GetCmdArg(2, arg1, sizeof(arg1));
        value = (StringToInt(arg1) != 0);
    }
    for(int i = 0; i < clientCount; i++) {
        if(!IsClientInGame(clientList[i])) continue;
        if(args > 1) {
            isUsingESP[clientList[i]] = value;
        } else {
            isUsingESP[clientList[i]] = !isUsingESP[clientList[i]];
        }
    }
    if(clientCount > 0) {
        checkGlows();
    }
    notifyServer(client, targetName, (args > 1) ? (value ? 1 : 0) : 2);
    return Plugin_Handled;
}

public Action Command_ESP(client, args) {
    if(!client || !IsClientInGame(client)) {
        return Plugin_Handled;
    }
    bool value = false;
    if(args > 0) {
        char arg1[32];
        GetCmdArg(1, arg1, sizeof(arg1));
        toggleGlow(client, (StringToInt(arg1) != 0));
    } else {
        toggleGlow(client, !isUsingESP[client]);
    }
    char targetName[64];
    GetClientName(client, targetName, sizeof(targetName));
    notifyServer(client, targetName, (args > 1) ? (value ? 1 : 0) : 2);
    return Plugin_Handled;
}

public void notifyServer(int client, char[] targetName, int status) {
    if(cNotify.BoolValue) {
        switch(status) {
            case 0:  ShowActivity(client, "%t", "ESP Off", targetName);
            case 1:  ShowActivity(client, "%t", "ESP On", targetName);
            default: ShowActivity(client, "%t", "ESP Toggle", targetName);
        }
    }
}

public OnPluginEnd() {
    destoryGlows();
}

public void OnMapStart() {
    PrecacheModel(HEADPROP);
    resetPlayerVars(0);
}

public void OnClientDisconnect(int client) {
    resetPlayerVars(client);
}

public void OnClientPutInServer(int client) {
    resetPlayerVars(client);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client <= 0 || client > MaxClients || !IsClientInGame(client)) {
        return;
    }
    playerTeam[client] = GetClientTeam(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client <= 0 || client > MaxClients || !IsClientInGame(client)) {
        return;
    }
    if(cDefault.BoolValue) {
        if(CheckCommandAccess(client, "sm_esp", ADMFLAG_CHEATS, false)) {
            isUsingESP[client] = true;
        }
    }
    if(isUsingESP[client]) {
        if(cLifeState.IntValue != 1) {
            canSeeESP[client] = true;
        } else {
            canSeeESP[client] = false;
        }
    }
    checkGlows();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if(cLifeState.IntValue != 2) {
        //Display glow to the dead.
        int client = GetClientOfUserId(event.GetInt("userid"));
        if(client > 0 && client <= MaxClients && IsClientInGame(client) && isUsingESP[client]) {
            canSeeESP[client] = true;
        }
    }
    checkGlows();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    destoryGlows();
}

public void toggleGlow(int client, bool value) {
    isUsingESP[client] = value;
    checkGlows();
}

public void resetPlayerVars(int client) {
    if(client == 0) {
        for(int i = 1; i <= MaxClients; i++) {
            resetPlayerVars(i);
        }
        return;
    }
    isUsingESP[client] = false;
    playerTeam[client] = 0;
    if(IsClientInGame(client)) {
        playerTeam[client] = GetClientTeam(client);
    }
}

public bool getCanSeeEsp(int client, int lifestate) {
    switch(lifestate) {
        case 1: return !IsPlayerAlive(client);
        case 2: return IsPlayerAlive(client);
    }
    return true;
}

public void checkGlows() {
    //Check to see if some one has a glow enabled.
    playersInESP = 0;
    int lifestate = cLifeState.IntValue;
    for(int client = 1; client <= MaxClients; client++) {
        if(!IsClientInGame(client) || !isUsingESP[client]) {
            isUsingESP[client] = false;
            canSeeESP[client] = false;
            continue;
        }
        canSeeESP[client] = getCanSeeEsp(client, lifestate);
        if(canSeeESP[client]) {
            playersInESP++;
        }
    }
    //Force transmit makes sure that the players can see the glow through wall correctly.
    //This is usually for alive players for the anti-wallhack made by valve.
    destoryGlows();
    if(playersInESP > 0) {
        sv_force_transmit_players.SetString("1", true, false);
        createGlows();
    } else {
        sv_force_transmit_players.SetString("0", true, false);
    }
}

public void destoryGlows() {
    for(int client = 1; client <= MaxClients; client++) {
        if(IsClientInGame(client)) {
            RemoveSkin(client);
        }
    }
}

public void createGlows() {
    char model[PLATFORM_MAX_PATH];
    char attachment[PLATFORM_MAX_PATH];
    int skin = -1;
    int showTeam = cTeam.IntValue;
    int useModel = cModel.IntValue;
    float scale = 1.0;
    if(useModel) {
        model = HEADPROP;
        attachment = HEADATTACH;
        scale = HEADSCALE;
    } else {
        attachment = NORMATTACH;
    }
    //Loop and setup a glow on alive players.
    for(int client = 1; client <= MaxClients; client++) {
        if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
            continue;
        }
        playerTeam[client] = GetClientTeam(client);
        if(playerTeam[client] <= 1) {
            continue;
        }
        //Create Skin
        if(!useModel) {
            GetClientModel(client, model, sizeof(model));
        }
        skin = CreatePlayerModelProp(client, model, attachment, !useModel, scale);
        if(skin > MaxClients) {
            playerTeam[client] = GetClientTeam(client);
            if(showTeam == 1) {
                //Display Enemys
                if(playerTeam[client] == 3 && SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit_T) || 
                   playerTeam[client] == 2 && SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit_CT)) {
                    setGlowTeam(skin, playerTeam[client]);
                }
            } else if(showTeam == 2) {
                //Display Teammates
                if(playerTeam[client] == 2 && SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit_T) || 
                   playerTeam[client] == 3 && SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit_CT)) {
                    setGlowTeam(skin, playerTeam[client]);
                }
            } else {
                if(SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit_All)) {
                    setGlowTeam(skin, playerTeam[client]);
                }
            }
        }
    }
}

public setGlowTeam(int skin, int team) {
    if(team >= 2) {
        SetupGlow(skin, colors[team-2]);
    }
}

public Action OnSetTransmit_All(int entity, int client) {
    if(canSeeESP[client] && playerModelsIndex[client] != entity) {
        return Plugin_Continue;
    }
    return Plugin_Stop;
}
    
public Action OnSetTransmit_T(int entity, int client) {
    if(canSeeESP[client] && playerModelsIndex[client] != entity && playerTeam[client] == 2) {
        return Plugin_Continue;
    }
    return Plugin_Handled;
}
public Action OnSetTransmit_CT(int entity, int client) {
    if(canSeeESP[client] && playerModelsIndex[client] != entity && playerTeam[client] == 3) {
        return Plugin_Continue;
    }
    return Plugin_Handled;
}

public void SetupGlow(int entity, int color[4]) {
    static offset;
    // Get sendprop offset for prop_dynamic_override
    if (!offset && (offset = GetEntSendPropOffs(entity, "m_clrGlow")) == -1) {
        LogError("Unable to find property offset: \"m_clrGlow\"!");
        return;
    }

    // Enable glow for custom skin
    SetEntProp(entity, Prop_Send, "m_bShouldGlow", true);
    SetEntProp(entity, Prop_Send, "m_nGlowStyle", 0);
    SetEntPropFloat(entity, Prop_Send, "m_flGlowMaxDist", 10000.0);

    // So now setup given glow colors for the skin
    for(int i=0;i<3;i++) {
        SetEntData(entity, offset + i, color[i], _, true); 
    }
}

public int CreatePlayerModelProp(int client, char[] sModel, char[] attachment, bool bonemerge, float scale) {
    RemoveSkin(client);
    int skin = CreateEntityByName("prop_dynamic_glow");
    DispatchKeyValue(skin, "model", sModel);
    DispatchKeyValue(skin, "solid", "0");
    DispatchKeyValue(skin, "fademindist", "1");
    DispatchKeyValue(skin, "fademaxdist", "1");
    DispatchKeyValue(skin, "fadescale", "2.0");
    SetEntProp(skin, Prop_Send, "m_CollisionGroup", 0);
    DispatchSpawn(skin);
    SetEntityRenderMode(skin, RENDER_GLOW);
    SetEntityRenderColor(skin, 0, 0, 0, 0);
    if(bonemerge) {
        SetEntProp(skin, Prop_Send, "m_fEffects", EF_BONEMERGE);
    }
    if(scale != 1.0) {
        SetEntPropFloat(skin, Prop_Send, "m_flModelScale", scale);
    }
    SetVariantString("!activator");
    AcceptEntityInput(skin, "SetParent", client, skin);
    SetVariantString(attachment);
    AcceptEntityInput(skin, "SetParentAttachment", skin, skin, 0);
    SetVariantString("OnUser1 !self:Kill::0.1:-1");
    AcceptEntityInput(skin, "AddOutput");
    playerModels[client] = EntIndexToEntRef(skin);
    playerModelsIndex[client] = skin;
    return skin;
}

public void RemoveSkin(int client) {
    int index = EntRefToEntIndex(playerModels[client]);
    if(index > MaxClients && IsValidEntity(index)) {
        SetEntProp(index, Prop_Send, "m_bShouldGlow", false);
        AcceptEntityInput(index, "FireUser1");
    }
    playerModels[client] = INVALID_ENT_REFERENCE;
    playerModelsIndex[client] = -1;
}

public bool IsValidClient(int client) {
    return (1 <= client && client <= MaxClients && IsClientInGame(client));
}