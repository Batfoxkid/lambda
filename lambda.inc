#if defined _Lambda_included
	#endinput
#endif
#define _Lambda_included

native void LF_HookSpawn(const char[] classname, LFHook hook, bool post=false);
native void LF_UnhookSpawn(const char[] classname, LFHook hook, bool post=false);

forward Action LF_OnMakeNPC(char[] classname, int &entity);

typeset LFHook
{
	function Action(char[] classname);
	function Action(char classname[64]);
	function void(const char[] classname, int entity);
}

#if !defined REQUIRE_PLUGIN
public void __pl_Lambda_SetNTVOptional()
{
	MarkNativeAsOptional("LF_HookSpawn");
	MarkNativeAsOptional("LF_UnhookSpawn");
}
#endif
