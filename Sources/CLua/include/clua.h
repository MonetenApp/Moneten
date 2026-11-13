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

/// Runs a function of the script in protected mode. Only here does the memory limit hold exactly and
/// the collector run. While Swift code runs, the state may hold up to 64 MB more and no finalizer
/// runs, so that Swift never meets a Lua error.
int clua_pcall(lua_State *L, int arguments, int results);

/// Memory outside the state that an object of the state holds, such as the tree of an HTML document.
/// It counts against the limit like a block of the state: back in Lua, a state over the limit collects,
/// and raises its memory error when it still holds too much. The finalizer of the object gives it back.
void clua_charge(lua_State *L, size_t bytes);
void clua_uncharge(lua_State *L, size_t bytes);

/// The memory budget of the state of `L`, for an object that outlives the thread it was made on, such
/// as a coroutine's. The budget lasts until clua_close has run every finalizer.
void *clua_memory(lua_State *L);
void clua_memory_charge(void *memory, size_t bytes);
void clua_memory_uncharge(void *memory, size_t bytes);
/// Whether `bytes` more fit under the limit now, for a change that Swift makes outside the state.
int clua_memory_room(void *memory, size_t bytes);

/// How many levels of Swift code hold the state: 1 between calls, 0 while Lua runs.
int clua_nativedepth(lua_State *L);

/// The line that the process writes to stdout before it exits when an allocation fails while Swift
/// code runs.
void clua_setmemoryline(const char *line);

/// A new state whose allocations stop at `limit` bytes, and its end. Lua raises its memory error at the limit.
lua_State *clua_newstate(size_t limit);
void clua_close(lua_State *L);

/// Limits the processor time of the whole process to `seconds`. When it runs out, the process writes
/// `line` to stdout and exits, wherever the script is, also inside `pcall`. Returns 0 on success.
int clua_limitprocessor(unsigned seconds, const char *line);

#endif
