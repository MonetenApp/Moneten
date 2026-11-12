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

/// Runs a function of the script in protected mode. Only here does the memory limit hold exactly;
/// while Swift code runs, the state may hold up to 64 MB more, so that Swift never meets a Lua error.
int clua_pcall(lua_State *L, int arguments, int results);

/// A new state whose allocations stop at `limit` bytes, and its end. Lua raises its memory error at the limit.
lua_State *clua_newstate(size_t limit);
void clua_close(lua_State *L);

/// Limits the processor time of the whole process to `seconds`. When it runs out, the process writes
/// `line` to stdout and exits, wherever the script is, also inside `pcall`. Returns 0 on success.
int clua_limitprocessor(unsigned seconds, const char *line);

#endif
