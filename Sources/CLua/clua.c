#include "clua.h"

static int clua_call(lua_State *L) {
	clua_Function f = (clua_Function)lua_touserdata(L, lua_upvalueindex(1));
	int results = f(L);
	if (results >= 0) return results;
	luaL_where(L, 1);
	lua_insert(L, -2);
	lua_concat(L, 2);
	return lua_error(L);
}

void clua_pushfunction(lua_State *L, clua_Function f) {
	lua_pushlightuserdata(L, (void *)f);
	lua_pushcclosure(L, clua_call, 1);
}

void clua_pushglobals(lua_State *L) {
	lua_pushglobaltable(L);
}

void *clua_context(lua_State *L) {
	return *(void **)lua_getextraspace(L);
}

void clua_setcontext(lua_State *L, void *context) {
	*(void **)lua_getextraspace(L) = context;
}
