/*
 * SourceMod adminWatch (Redux)
 * by:Pat841 @ www.amitygaming.org and Spectre Servers
 *
 * This file is part of SM adminWatch.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>
 */
 
#define PLUGIN_VERSION "1.3"
#include <sourcemod>

// DB Handles
Handle hDatabase = INVALID_HANDLE;

// Timer Handles
Handle hTimerTotal[MAXPLAYERS + 1] = INVALID_HANDLE;
Handle hTimerPlayed[MAXPLAYERS + 1] = INVALID_HANDLE;

// Cvar Handles
Handle cvarEnabled = INVALID_HANDLE;
Handle cvarLoggingEnabled = INVALID_HANDLE;
Handle cvarAdminFlag = INVALID_HANDLE;
Handle cvarPrecision = INVALID_HANDLE;

// Globals
bool gEnabled;
bool gLoggingEnabled;
char gAdminFlag[MAXPLAYERS + 1];
int gAdminFlagBits = 0;
bool gPrecision;

// Trackers
int gTrackTotal[MAXPLAYERS + 1] = 0;
int gTrackPlayed[MAXPLAYERS + 1] = 0;

// Database Queries
char DBQueries[] =
{
	"CREATE TABLE IF NOT EXISTS `adminwatch` (`id` INT(10) NOT NULL AUTO_INCREMENT, `steam` VARCHAR(50) NOT NULL, `name` VARCHAR(50) NOT NULL, `total` INT(11) NOT NULL DEFAULT '0', `played` INT(11) NOT NULL DEFAULT '0', `last_played` VARCHAR(50) NOT NULL, PRIMARY KEY (`id`)) COLLATE='latin1_swedish_ci' ENGINE=MyISAM;",
	"SELECT * FROM `adminwatch` WHERE `steam` = '%s'",
	"UPDATE `adminwatch` SET `total` = '%i', `played` = '%i', `last_played` = '%i' WHERE `steam` = '%s'",
	"INSERT INTO `adminwatch` (`steam`, `name`, `total`, `played`, `last_played`) VALUES ('%s', '%s', '0', '0', '')"
};

char DBQueriesLogs[] =
{
	"CREATE TABLE IF NOT EXISTS `adminwatch_logs` (`id` INT(10) NOT NULL AUTO_INCREMENT, `hostname` VARCHAR(50) NOT NULL, `name` VARCHAR(50) NOT NULL, `steam` VARCHAR(50) NOT NULL, `command` VARCHAR(100) NOT NULL, `time` VARCHAR(50) NOT NULL, PRIMARY KEY (`id`)) COLLATE='latin1_swedish_ci' ENGINE=MyISAM;",
	"INSERT INTO `adminwatch_logs` (`hostname`, `steam`, `name`, `command`, `time`) VALUES ('%s', '%s', '%s', '%s', '%i')"
};

// Plugin Info
public Plugin myinfo = 
{
	name = "adminWatch (Redux)",
	author = "Pat841 and Spectre Servers",
	description = "Tracks play time and server idle time for a specific admin flag and stores results in a database.",
	version = PLUGIN_VERSION,
	url = "https://spectre.gg/"
};

public OnPluginStart ()
{
	// Hook Events
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
	// Create ConVars
	CreateConVar("sm_adminwatch_version", PLUGIN_VERSION, "adminWatch plugin version (unchangeable)", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	cvarEnabled = CreateConVar("sm_adminwatch_enabled", "1", "Enables or disables the plugin: 0 - Disabled, 1 - Enabled", _, true, 0.0, true, 1.0);
	gEnabled = true;
	
	cvarLoggingEnabled = CreateConVar("sm_adminwatch_logging", "1", "Enables or disables logging commands: 0 - Disabled, 1 - Enabled", _, true, 0.0, true, 1.0);
	gLoggingEnabled = true;
	
	cvarAdminFlag = CreateConVar("sm_adminwatch_adminflag", "1", "The admin flag to track: 1 - All admins, flag values: abcdefghijklmnopqrst");
	Format(gAdminFlag, sizeof(gAdminFlag), "z");
	
	cvarPrecision = CreateConVar("sm_adminwatch_precision", "0", "Timer precision. Careful, use 0 if rounds end in less than 1 minute: 0 - Seconds, 1 - Minutes", _, true, 0.0, true, 1.0);
	gPrecision = false;
	
	// Hook Cvar Changes
	HookConVarChange(cvarEnabled, HandleCvars);
	HookConVarChange(cvarAdminFlag, HandleCvars);
	HookConVarChange(cvarPrecision, HandleCvars);
	
	// Connect to Database
	char error[64];
	hDatabase = SQL_Connect("adminwatch", true, error, sizeof(error));
	
	if (hDatabase == INVALID_HANDLE)
	{
		LogError("Unable to connect to the database. Error: %s", error);
		LogMessage("[adminWatch] - Unable to connect to the database.");
	}
	
	// Autoload Config
	AutoExecConfig(true, "adminwatch");
	
	// If needed, create tables
	if (gEnabled)
	{
		SQL_TQuery(hDatabase, DBNoAction, DBQueries[0], DBPrio_High);
	}
	if (gLoggingEnabled)
	{
		SQL_TQuery(hDatabase, DBNoAction, DBQueriesLogs[0], DBPrio_High);
	}
}

public OnPluginEnd ()
{
	CloseHandle(hDatabase);
	hDatabase = INVALID_HANDLE;
}

public OnConfigsExecuted ()
{
	gEnabled = GetConVarBool(cvarEnabled);
	gLoggingEnabled = GetConVarBool(cvarLoggingEnabled);
	GetConVarString(cvarAdminFlag, gAdminFlag, sizeof(gAdminFlag));
	gPrecision = GetConVarBool(cvarPrecision);
	RefreshFlags();
	ResetTrackers();
}

public OnClientPostAdminCheck (client)
{
	// Reset client
	ResetClient(client);
	
	// Check if client has flags
	if (gEnabled && (GetUserFlagBits(client) & gAdminFlagBits))
	{
		// Add to database if needed
		decl String:query[255], String:authid[32];
		GetClientAuthString(client, authid, sizeof(authid));
		
		Format(query, sizeof(query), DBQueries[1], authid);
		SQL_TQuery(hDatabase, DBInsert, query, client, DBPrio_High);
		
		// Is admin, start timer to track total time in server
		if (gPrecision && hTimerTotal[client] == INVALID_HANDLE)
		{
			hTimerTotal[client] = CreateTimer(60.0, TimerAddTotal, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
		else if (hTimerTotal[client] == INVALID_HANDLE)
		{
			hTimerTotal[client] = CreateTimer(1.0, TimerAddTotal, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public OnClientDisconnect (client)
{
	if (gEnabled && (GetUserFlagBits(client) & gAdminFlagBits))
	{
		CheckoutClient(client);
	}
	
	ResetClient(client);
}

// Events
public Action:Event_RoundStart (Handle:event, const String:name[], bool:dontBroadcast)
{
	if (gEnabled)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && (GetUserFlagBits(i) & gAdminFlagBits) && (GetClientTeam(i) == 2 || GetClientTeam(i) == 3) && hTimerPlayed[i] == INVALID_HANDLE)
			{
				if (gPrecision)
				{
					hTimerPlayed[i] = CreateTimer(60.0, TimerAddPlayed, i, TIMER_REPEAT);
				}
				else
				{
					hTimerPlayed[i] = CreateTimer(1.0, TimerAddPlayed, i, TIMER_REPEAT);
				}
			}
		}
	}
}

public Action:Event_RoundEnd (Handle:event, const String:name[], bool:dontBroadcast)
{
	if (gEnabled)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && (GetUserFlagBits(i) & gAdminFlagBits) && hTimerPlayed[i] != INVALID_HANDLE)
			{
				CloseHandle(hTimerPlayed[i]);
				hTimerPlayed[i] = INVALID_HANDLE;
			}
		}	
	}
}

// Credit: Modified TSCDan's function
public Action:OnLogAction (Handle:source, Identity:ident, client, target, const String:message[])
{
	/* If there is no client or they're not an admin, we don't care. */
	if (!gLoggingEnabled || client < 1 || !(GetUserFlagBits(client) & gAdminFlagBits))
	{
		LogMessage("[adminWatch DEBUG] - Client: %d, Target: %d inside OnLogAction().", client, target);
		return Plugin_Continue;
	}
	
	// Get steam
	new String:query[400], String:authid[32];
	GetClientAuthString(client, authid, sizeof(authid));
	
	// Get name
	new String:name[30];
	GetClientName(client, name, sizeof(name));
	
	// Get hostname
	new String:hostname[60];
	new Handle:cvarHostname = INVALID_HANDLE;
	cvarHostname = FindConVar("hostname");
	GetConVarString(cvarHostname, hostname, sizeof(hostname));
	
	// Escape
	new String:bName[61];
	new String:bHost[121];
	
	SQL_EscapeString(hDatabase, name, bName, sizeof(bName));
	SQL_EscapeString(hDatabase, hostname, bHost, sizeof(bHost));
	
	new time = GetTime();
	
	Format(query, sizeof(query), DBQueriesLogs[1], bHost, authid, bName, message, time);
	
	SQL_TQuery(hDatabase, DBNoAction, query, client, DBPrio_High);
	
	return Plugin_Handled;
}

public CheckoutClient (client)
{
	// Get authid (steamid)
	new String:query[255], String:authid[32];
	GetClientAuthString(client, authid, sizeof(authid));
	
	Format(query, sizeof(query), DBQueries[1], authid);
	
	SQL_TQuery(hDatabase, DBCheckout, query, client, DBPrio_High);
	
	return true;
}

// Database Threads
public DBCheckout (Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogMessage("[adminWatch] - DB Query Failed. Error: %s", error);
	}
	else
	{
		new String:query[255];
		
		if (SQL_FetchRow(hndl))
		{
			new String:steam[30];
			SQL_FetchString(hndl, 1, steam, sizeof(steam));
			
			new time = GetTime();
			
			new total = 0;
			new played = 0;
			
			total = SQL_FetchInt(hndl, 3);
			played = SQL_FetchInt(hndl, 4);
			
			total += gTrackTotal[data];
			played += gTrackPlayed[data];
			
			Format(query, sizeof(query), DBQueries[2], total, played, time, steam);
			SQL_TQuery(hDatabase, DBNoAction, query, DBPrio_High);
		}
		else
		{
			LogMessage("[adminWatch] - Unable to update admin times.");
		}
	}
}

public DBInsert (Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogMessage("[adminWatch] - DB Query Failed. Error: %s", error);
	}
	else
	{
		if (SQL_GetRowCount(hndl) <= 0)
		{
			// Not found, insert
			decl String:query[255], String:authid[32];
			GetClientAuthString(data, authid, sizeof(authid));
			
			new String:name[60], String:buffer[30];
			GetClientName(data, buffer, sizeof(buffer));
			
			SQL_EscapeString(hDatabase, buffer, name, sizeof(name));
			
			Format(query, sizeof(query), DBQueries[3], authid, name);
			SQL_TQuery(hDatabase, DBNoAction, query, DBPrio_High);
		}
	}
}

public DBNoAction (Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState(error);
	}
}

// Tracker Functions
public Action:TimerAddTotal (Handle:timer, any:client)
{
	if (hTimerTotal[client] != INVALID_HANDLE)
	{
		gTrackTotal[client] += 1;
	}
}

public Action:TimerAddPlayed (Handle:timer, any:client)
{
	if (hTimerPlayed[client] != INVALID_HANDLE)
	{
		gTrackPlayed[client] += 1;
	}
}

// Helper Functions
public HandleCvars (Handle:cvar, const String:oldValue[], const String:newValue[])
{
	if (cvar == cvarEnabled && StrEqual(newValue, "1"))
	{
		gEnabled = true;
	}
	else if (cvar == cvarEnabled && StrEqual(newValue, "0"))
	{
		gEnabled = false;
	}
	if (cvar == cvarLoggingEnabled && StrEqual(newValue, "1"))
	{
		gLoggingEnabled = true;
	}
	else if (cvar == cvarLoggingEnabled && StrEqual(newValue, "0"))
	{
		gLoggingEnabled = false;
	}
	else if (cvar == cvarAdminFlag)
	{
		Format(gAdminFlag, sizeof(gAdminFlag), newValue);
		RefreshFlags();
	}
	else if (cvar == cvarPrecision && StrEqual(newValue, "1"))
	{
		gPrecision = true;
	}
	else if (cvar == cvarPrecision && StrEqual(newValue, "0"))
	{
		gPrecision = false;
	}
}

public RefreshFlags ()
{
	if (StrEqual(gAdminFlag, "1"))
	{
		// Include all but reserved slot flag
		Format(gAdminFlag, sizeof(gAdminFlag), "bcdefghijklmnopqrstz");
	}
	gAdminFlagBits = ReadFlagString(gAdminFlag);
	
	return true;
}

public ResetTrackers ()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		gTrackTotal[i] = 0;
		gTrackPlayed[i] = 0;
		
		if (hTimerTotal[i] != INVALID_HANDLE)
		{
			CloseHandle(hTimerTotal[i]);
			hTimerTotal[i] = INVALID_HANDLE;
		}
		
		if (hTimerPlayed[i] != INVALID_HANDLE)
		{
			CloseHandle(hTimerPlayed[i]);
			hTimerPlayed[i] = INVALID_HANDLE;
		}
	}
}

public ResetClient (client)
{
	if (hTimerTotal[client] != INVALID_HANDLE)
	{
		CloseHandle(hTimerTotal[client]);
		hTimerTotal[client] = INVALID_HANDLE;
	}
	if (hTimerPlayed[client] != INVALID_HANDLE)
	{
		CloseHandle(hTimerPlayed[client]);
		hTimerPlayed[client] = INVALID_HANDLE;
	}
	
	gTrackTotal[client] = 0;
	gTrackPlayed[client] = 0;
	
	return true;
}