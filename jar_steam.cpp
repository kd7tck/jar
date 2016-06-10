/*
jar_steam.h - v0.01 - public domain - Joshua Reisenauer, JUNE 2016

WHY:
    jar_steam acts as a C wrapper for the steam_api, allowing for easy use of steam functions from within C.

USAGE:
    Compile jar.steam.cpp by itself in g++ as a static library, make sure to link in "steam_api.lib, stdc++".
    Then use this file as a header file, Make sure to define JAR_STEAM_H before you include this in any source file.
    Use reimp from <http://wyw.dcweb.cn/download.asp?path=&file=reimp_new.zip> to convert (steam_api.lib -> steam_api.a).
    Every time you compile an executable with gcc, link against the following in the order given "steam_api_wrap.lib, steam_api.a, stdc++".
    
INCOMPLETE:
    This library for the most part is really meant to be an example. Completing it was never the intent, please feel free to add in any remaining functions you desire.
    

By: Joshua Adam Reisenauer <kd7tck@gmail.com>
This program is free software. It comes without any warranty, to the
extent permitted by applicable law. You can redistribute it and/or
modify it under the terms of the Do What The Fuck You Want To Public
License, Version 2, as published by Sam Hocevar. See
http://sam.zoy.org/wtfpl/COPYING for more details.
*/
#ifndef JAR_STEAM_CPP
#define JAR_STEAM_CPP



#ifdef JAR_STEAM_H
#ifdef __cplusplus
extern "C" {
#endif
#include <stdint.h>

bool jar_steam_SteamAPI_Init();
void jar_steam_SteamAPI_Shutdown();

bool jar_steam_SteamAPI_RestartAppIfNecessary(uint32_t);
bool jar_steam_SteamAPI_RestartAppIfNecessary_Test();

#ifdef __cplusplus
}
#endif
#endif




#ifndef JAR_STEAM_H
#include <iostream>
#include <steam/steam_api.h>
#include <steam/steam_gameserver.h>
#include <stdint.h>

extern "C" bool jar_steam_SteamAPI_Init()
{
    return SteamAPI_Init();
}

extern "C" void jar_steam_SteamAPI_Shutdown()
{
    SteamAPI_Shutdown();
}

extern "C" bool jar_steam_SteamAPI_RestartAppIfNecessary(uint32_t AppID)
{
    return SteamAPI_RestartAppIfNecessary(AppID);
}

extern "C" bool jar_steam_SteamAPI_RestartAppIfNecessary_Test()
{
    return SteamAPI_RestartAppIfNecessary(k_uAppIdInvalid);
}
#endif
#endif // JAR_STEAM_CPP