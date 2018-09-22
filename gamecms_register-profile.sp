#include <sourcemod>
#include <regex>
#pragma newdecls  required
#pragma semicolon 1
#pragma tabsize 0

public Plugin myinfo = {
    description = "Регистрация и просмотр профиля через внутриигровое меню",
    version     = "1.0.1",
    author      = "CrazyHackGUT, Rostu, Alexbu444",
    name        = "[GameCMS] Register / Profile",
    url         = "http://discord.gg/69kETMy"
};

Database    g_hDB;

#define MPL MAXPLAYERS+1
#define PMP PLATFORM_MAX_PATH

#define GAMECMS_NOTLOADED       -1
#define GAMECMS_NOTREGISTERED    -2

#define GAMESTATE_NONE           0
#define GAMESTATE_LOGIN          1
#define GAMESTATE_EMAIL          2
#define GAMESTATE_PASSWORD       3

#define RESETDATA       0
#define MAINMENU        1
Menu        g_hMenus[2];

char        g_szLogin   [MPL][64],
            g_szEMail   [MPL][64],
            g_szPassword[MPL][128];

int         g_iStatus   [MPL],
            g_iID       [MPL];

char        g_szLogFile[PMP];

public void OnPluginStart() {
    RegConsoleCmd("sm_register", Cmd_Register);
    RegConsoleCmd("sm_profile",Cmd_Profile);
    AddCommandListener(OnSayChat, "say");
    AddCommandListener(OnSayChat, "say_team");
    BuildPath(Path_SM, g_szLogFile, sizeof(g_szLogFile), "logs/GameCMS_Register.log");

    /**
     * Build menus
     */
    g_hMenus[RESETDATA] = new Menu(ResetDataHandler, MenuAction_Select|MenuAction_Cancel);
    g_hMenus[RESETDATA].SetTitle("Вы действительно хотите сбросить\nвсе введённые ранее данные?\n ");
    g_hMenus[RESETDATA].AddItem(NULL_STRING, "Да");
    g_hMenus[RESETDATA].AddItem(NULL_STRING, "Нет");
    g_hMenus[RESETDATA].ExitBackButton = true;
    g_hMenus[RESETDATA].ExitButton = false;

    g_hMenus[MAINMENU] = new Menu(MainHandler, MenuAction_Select|MenuAction_DisplayItem|MenuAction_DrawItem);
    g_hMenus[MAINMENU].SetTitle("Регистрация на сайте");
    g_hMenus[MAINMENU].AddItem(NULL_STRING, "Логин: Не указан");
    g_hMenus[MAINMENU].AddItem(NULL_STRING, "E-Mail: Не указан");
    g_hMenus[MAINMENU].AddItem(NULL_STRING, "Пароль: Не указан");
    g_hMenus[MAINMENU].AddItem(NULL_STRING, NULL_STRING, ITEMDRAW_SPACER);
    g_hMenus[MAINMENU].AddItem(NULL_STRING, "Зарегистрироваться");
    g_hMenus[MAINMENU].AddItem(NULL_STRING, "Сбросить все введённые данные");

    DB_Connect(null);
}

/**
 * DB Connection Worker
 */
public Action DB_Connect(Handle hTimer) {
    Database.Connect(DB_OnConnected, "gamecms");
}

public void DB_OnConnected(Database hDb, const char[] szError, any data) {
    if (szError[0] != 0) {
        LogError("Database failure: %s", szError);
        CreateTimer(30.0, DB_Connect);
        return;
    }

    g_hDB = hDb;
    g_hDB.SetCharset("utf8");

    for (int i = MaxClients; i != 0; --i) {
        if (IsClientInGame(i)) {
            OnClientConnected(i);
            if (IsClientAuthorized(i))
                OnClientAuthorized(i, NULL_STRING);
        }
    }
}

/**
 * DB Users Fetcher
 */
void DB_FetchUser(int iClient) {
    if (g_hDB == null) {
        return;
    }

    char szQuery[512];
    char szAuthIds[4][32];

    for (int i; i < 4; ++i)
        GetClientAuthId(iClient, view_as<AuthIdType>(i), szAuthIds[i], sizeof(szAuthIds[]));

    FormatEx(szQuery, sizeof(szQuery), "SELECT \
                                            `id` \
                                        FROM \
                                            `users` \
                                        WHERE \
                                            `steam_id` = '%s' \
                                            OR `steam_id` = '%s' \
                                            OR `steam_id` = '%s' \
                                            OR `steam_id` = '%s' \
                                            OR `steam_api` = '%s';", szAuthIds[0], szAuthIds[1], szAuthIds[2], szAuthIds[3], szAuthIds[3]);
    g_hDB.Query(DB_OnUserFetched, szQuery, GetClientUserId(iClient), DBPrio_High);
}

public void DB_OnUserFetched(Database hDb, DBResultSet hResults, const char[] szError, int iClient) {
    if ((iClient = GetClientOfUserId(iClient)) == 0) {
        return; // client disconnected.
    }

    if (szError[0] != 0) {
        LogToFileEx(g_szLogFile, "Error when fetching user %L: %s", iClient, szError);
        return;
    }

    if (hResults.FetchRow())
        g_iID[iClient] = hResults.FetchInt(0);
    else
        g_iID[iClient] = GAMECMS_NOTREGISTERED;
}

/**
 * @section SM user events
 */
public void OnClientConnected(int iClient) {
    g_iID[iClient] = GAMECMS_NOTLOADED;
    g_szEMail[iClient][0] = g_szLogin[iClient][0] = g_szPassword[iClient][0] = 0;
}

public void OnClientAuthorized(int iClient, const char[] szAuth) {
    if (!IsFakeClient(iClient))
        DB_FetchUser(iClient);
}

/**
 * @section Command Handler
 */
public Action Cmd_Register(int iClient, int iArgC) {
    if (g_hDB == null)
        PrintToChat(iClient, "Проблемы соединения с сайтом. Повторите попытку позже.");
    else if (g_iID[iClient] == GAMECMS_NOTLOADED)
        PrintToChat(iClient, "Пожалуйста, подождите. Мы ещё загружаем Вас...");
    else if (g_iID[iClient] != GAMECMS_NOTREGISTERED)
        PrintToChat(iClient, "Вы уже зарегистрированы на сайте!");
    else
        g_hMenus[MAINMENU].Display(iClient, 0);
    return Plugin_Handled;
}

/**
 * @section Menus Handlers
 */
#define MenuHandle(%0)      public int %0(Menu hMenu, MenuAction eAction, int iParam1, int iParam2)

MenuHandle(ResetDataHandler) {
    if (eAction == MenuAction_Select && iParam2 == 0) {
        g_szEMail[iParam1][0] = g_szLogin[iParam1][0] = g_szPassword[iParam1][0] = 0;
        g_hMenus[MAINMENU].Display(iParam1, 0);
    } else if ((eAction == MenuAction_Select && iParam2 == 1) || (eAction == MenuAction_Cancel && iParam2 == MenuCancel_ExitBack))
        g_hMenus[MAINMENU].Display(iParam1, 0);
}

MenuHandle(MainHandler) {
    switch (eAction) {
        case MenuAction_Select:         {
            switch (iParam2) {
                case 0: g_iStatus[iParam1] = GAMESTATE_LOGIN,    PrintToChat(iParam1, "[GameCMS] Введите в чат логин, или \"-\" для отмены ввода. Для сброса сохранённого значения - \"+\"");
                case 1: g_iStatus[iParam1] = GAMESTATE_EMAIL,    PrintToChat(iParam1, "[GameCMS] Введите в чат E-Mail, или \"-\" для отмены ввода. Для сброса сохранённого значения - \"+\"");
                case 2: g_iStatus[iParam1] = GAMESTATE_PASSWORD, PrintToChat(iParam1, "[GameCMS] Введите в чат пароль, или \"-\" для отмены ввода. Для сброса сохранённого значения - \"+\"");

                case 4: DB_RegisterMe(iParam1);
                case 5: g_hMenus[RESETDATA].Display(iParam1, 0);
            }
        }

        case MenuAction_DisplayItem:    {
            char szBuffer[192];
            switch (iParam2) {
                case 0: {
                    if (g_szLogin[iParam1][0] != 0) {
                        FormatEx(szBuffer, sizeof(szBuffer), "Логин: %s", g_szLogin[iParam1]);
                        return RedrawMenuItem(szBuffer);
                    }
                }

                case 1: {
                    if (g_szEMail[iParam1][0] != 0) {
                        FormatEx(szBuffer, sizeof(szBuffer), "E-Mail: %s", g_szEMail[iParam1]);
                        return RedrawMenuItem(szBuffer);
                    }
                }

                case 2:
                    if (g_szPassword[iParam1][0] != 0)
                        return RedrawMenuItem("Пароль: Указан");
            }
        }

        case MenuAction_DrawItem:       {
            switch (iParam2) {
                case 4: return (g_szLogin[iParam1][0] != 0 && g_szEMail[iParam1][0] != 0 && g_szPassword[iParam1][0] != 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
                case 5: return (g_szLogin[iParam1][0] != 0 || g_szEMail[iParam1][0] != 0 || g_szPassword[iParam1][0] != 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
            }
        }
    }

    return 0;
}

/**
 * @section DB register worker
 */
void DB_RegisterMe(int iClient) {
    if (g_hDB == null) {
        return;
    }

    char szQuery[1536];
    char szEscapedLogin[128];
    char szEscapedEmail[128];
    char szEscapedPassword[256];
    char szSteamId[2][32];
    char szTime[32];

    g_hDB.Escape(g_szLogin[iClient], szEscapedLogin, sizeof(szEscapedLogin));
    g_hDB.Escape(g_szEMail[iClient], szEscapedEmail, sizeof(szEscapedEmail));
    g_hDB.Escape(g_szPassword[iClient], szEscapedPassword, sizeof(szEscapedPassword));

    GetClientAuthId(iClient, AuthId_Steam2, szSteamId[0], sizeof(szSteamId[]));
    GetClientAuthId(iClient, AuthId_SteamID64, szSteamId[1], sizeof(szSteamId[]));
	FormatTime(szTime, sizeof(szTime), "%Y-%m-%d %H:%M:%S");

    FormatEx(szQuery, sizeof(szQuery), "INSERT IGNORE INTO \
                                            `users` \
                                        (\
                                            `login`, `email`, \
                                            `password`, `steam_id`, \
                                            `steam_api`, `active`, `rights`, \
                                            `regdate`, `avatar` \
                                        ) VALUES ( \ 
                                            '%s', '%s', CONCAT(REVERSE(MD5('%s')), 'a'), '%s', '%s', 1, 2, '%s', 'files/avatars/no_avatar.jpg' \
                                        );", szEscapedLogin, szEscapedEmail, szEscapedPassword, szSteamId[0], szSteamId[1], szTime);
    g_hDB.Query(DB_OnUserRegistered, szQuery, GetClientUserId(iClient), DBPrio_High);
}

public void DB_OnUserRegistered(Database hDb, DBResultSet hResults, const char[] szError, int iClient) {
    if ((iClient = GetClientOfUserId(iClient)) == 0) {
        PrintToChat(iClient, "[GameCMS] Что-то пошло не так...");
        return; // client disconnected.
    }

    if (szError[0] != 0) {
        LogToFileEx(g_szLogFile, "Error when registering user %L: %s", iClient, szError);
        return;
    }

    if (hResults.AffectedRows == 1) {
        LogToFileEx(g_szLogFile, "User successfully registered: %L", iClient);
        PrintToChat(iClient, "[GameCMS] Спасибо за регистрацию!");
        g_iID[iClient] = 228; // this is magic "scratch"
    } else {
        PrintToChat(iClient, "[GameCMS] Что-то пошло не так... Возможно, занят E-Mail или логин.");
    }
}

/**
 * @section Chat Handler
 */
public Action OnSayChat(int iClient, const char[] szCmd, int iArgC) {
    if (iClient == 0 || g_iStatus[iClient] == GAMESTATE_NONE) {
        return Plugin_Continue;
    }

    char szInput[256];
    int iLen;
    if (iArgC == 1)
        GetCmdArg(1, szInput, sizeof(szInput));
    else
        GetCmdArgString(szInput, sizeof(szInput));
    TrimString(szInput);
    iLen = strlen(szInput);

    if ((szInput[0] == '+' || szInput[1] == '-') && szInput[1] == 0) {
        if (szInput[0] == '+') {
            switch (g_iStatus[iClient]) {
                case GAMESTATE_LOGIN:    g_szLogin   [iClient][0] = 0;
                case GAMESTATE_EMAIL:    g_szEMail   [iClient][0] = 0;
                case GAMESTATE_PASSWORD: g_szPassword[iClient][0] = 0;
            }
        }
        g_iStatus[iClient] = GAMESTATE_NONE;

        g_hMenus[MAINMENU].Display(iClient, 0);
    }

    switch (g_iStatus[iClient]) {
        case GAMESTATE_LOGIN:    {
            if (iLen < 3 || iLen > 25) {
                PrintToChat(iClient, "[GameCMS] Логин не может содержать менее 3-ёх символов или более 25!");
                return Plugin_Handled;
            }

            strcopy(g_szLogin[iClient], sizeof(g_szLogin[]), szInput);
        }

        case GAMESTATE_EMAIL:    {
            if (!UTIL_IsValidMail(szInput)) {
                PrintToChat(iClient, "[GameCMS] Некорректно введена почта.");
                return Plugin_Handled;
            }

            strcopy(g_szEMail[iClient], sizeof(g_szEMail[]), szInput);
        }

        case GAMESTATE_PASSWORD: {
            if (iLen < 6 || iLen > 32) {
                PrintToChat(iClient, "[GameCMS] Пароль не может содержать менее 6-и символов или более 32!");
                return Plugin_Handled;
            }

            strcopy(g_szPassword[iClient], sizeof(g_szPassword[]), szInput);
        }
    }

    g_iStatus[iClient] = GAMESTATE_NONE;
    g_hMenus[MAINMENU].Display(iClient, 0);
    return Plugin_Handled;
}

bool UTIL_IsValidMail(const char[] szString) {
    static Regex hRegex = null;
    if (hRegex == null) {
        char szError[256];
        RegexError iErrCode;
        hRegex = new Regex("[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,3}$", PCRE_UTF8|PCRE_CASELESS, szError, sizeof(szError), iErrCode);
        if (hRegex == null) {
            LogToFileEx(g_szLogFile, "Couldn't compile regex for validating emails: %s, error code %d. This functional is disabled.", szError, iErrCode);
            return true;
        }
    }

    return hRegex.Match(szString) != -1;
}



public Action Cmd_Profile(int iClient, int args)
{
    if(IsFakeClient(iClient)) return;

    char sQuery[256], sSteam[32];

    GetClientAuthId(iClient, AuthId_Steam2,sSteam,sizeof sSteam);
    FormatEx(sQuery,sizeof sQuery,"SELECT login,steam_id,shilings,email,regdate,last_activity,rights FROM users WHERE steam_id = '%s'",sSteam);
    g_hDB.Query(GetInfoProfile_Callback,sQuery,GetClientUserId(iClient), DBPrio_High);
}
public void GetInfoProfile_Callback(Database hDatabase, DBResultSet hResult,const char[] sError, int iUserId)
{
    if(sError[0])
    {
        LogError("GetInfoProfile_Callback = %s",sError);
        return;
    }
    int iClient = GetClientOfUserId(iUserId);
    if(iClient && hResult.FetchRow())
    {
        char sLogin[64],sSteam[32],sEmail[64],sRegDate[32],sLastActivity[32];
        hResult.FetchString(0,sLogin,sizeof sLogin);
        hResult.FetchString(1,sSteam,sizeof sSteam);
        hResult.FetchString(3,sEmail,sizeof sEmail);
        hResult.FetchString(4,sRegDate,sizeof sRegDate);
        hResult.FetchString(5,sLastActivity,sizeof sLastActivity);

        DataPack hPack = new DataPack();
        hPack.WriteCell(iUserId);
        hPack.WriteString(sLogin);
        hPack.WriteString(sSteam);
        hPack.WriteCell(hResult.FetchFloat(2)); // Shilings
        hPack.WriteString(sEmail);
        hPack.WriteString(sRegDate);
        hPack.WriteString(sLastActivity);

        char sQuery[128];
        FormatEx(sQuery,sizeof sQuery,"SELECT name FROM users__groups WHERE id = %d",hResult.FetchInt(6));
        g_hDB.Query(GetRightsName_Callback,sQuery,hPack,DBPrio_High);

    }
}
public void GetRightsName_Callback(Database hDatabase, DBResultSet hResult,const char[] sError, any data)
{
    if(sError[0])
    {
        LogError("GetRightsName_Callback = %s",sError);
        CloseHandle(data);
        return;
    }
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();
    int iClient = GetClientOfUserId(hPack.ReadCell());
    if(iClient && hResult.FetchRow())
    {
        char sName[64],sLogin[64],sSteam[32],sEmail[64],sRegDate[32],sLastActivity[32];

        hResult.FetchString(0,sName,sizeof sName);

        hPack.ReadString(sLogin,sizeof sLogin);
        hPack.ReadString(sSteam,sizeof sSteam);
        float fShilings = hPack.ReadCell();
        hPack.ReadString(sEmail,sizeof sEmail);
        hPack.ReadString(sRegDate,sizeof sRegDate);
        hPack.ReadString(sLastActivity,sizeof sLastActivity);

		Menu menu = new Menu(info_);
        menu.ExitButton = false;

		menu.SetTitle("----------Ваш профиль----------\nНик: %s\nSteam Id: %s\nБаланс: %.2f\nГруппа:%s\nПочта: %s\nДата регистрации: %s\nПоследний вход: %s",
        sLogin,sSteam,fShilings,sName,sEmail,sRegDate,sLastActivity);

        menu.AddItem("","Выход");
		menu.Display(iClient, MENU_TIME_FOREVER);
    }
    delete hPack;
}
public int info_(Menu menu, MenuAction action, int iClient, int option)
{
    switch(action)
    {
        case MenuAction_End: delete menu;
    }
}
