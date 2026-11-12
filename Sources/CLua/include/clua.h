#ifndef CLUA_H
#define CLUA_H

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/// A function that Swift implements. It returns the number of its results, or -1 after it pushed an
/// error message. Swift never raises a Lua error itself, because the long jump would skip Swift frames.
typedef int (*clua_Function)(lua_State *L);

/// Pushes `f` as a Lua function. An error message that `f` returns starts with the position of the
/// calling script line.
void clua_pushfunction(lua_State *L, clua_Function f);

/// Pushes the table of globals, which `lua_pushglobaltable` reaches through a macro that Swift cannot import.
void clua_pushglobals(lua_State *L);

/// The pointer that every thread of the state shares, for the Swift object that owns the state.
void *clua_context(lua_State *L);
void clua_setcontext(lua_State *L, void *context);

#endif
