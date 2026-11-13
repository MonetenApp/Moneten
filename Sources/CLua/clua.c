#include "clua.h"

#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

/* The memory of one state. Swift code may not meet a Lua error, because the long jump would skip
   its frames and leak what they hold. So while Swift runs (native > 0: outside a protected call, or
   in a function of Swift), the collector is stopped, so that no finalizer runs Lua code there, and
   the allocator allows HEADROOM bytes over the limit, which holds the largest body of a request.
   Back in Lua, clua_call raises the memory error from C. An allocation that fails while Swift runs
   ends the process, so a Lua error never starts there. Near the ceiling, this also ends the host
   for a failure that Lua would otherwise handle, such as lua_checkstack or a resize of the string
   table while Swift holds the state. */
typedef struct {
	size_t used, limit;
	int native;
	/* The collector was running when Swift took over, so it runs again when Lua does. */
	int stopped;
	/* clua_call collects over the limit, which needs headroom for the finalizers it runs. */
	int collecting;
} clua_Budget;

#define HEADROOM ((size_t)64 << 20)

static char clua_memory_line[1024];
static size_t clua_memory_length;

static void clua_exitformemory(void) {
	(void)write(STDOUT_FILENO, clua_memory_line, clua_memory_length);
	_exit(1);
}

/* The allocator of luaL_newstate with a ceiling. A block that would pass the ceiling fails, and Lua
   raises its memory error. For a new block Lua passes the kind of object in osize, not a size. */
static void *clua_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
	clua_Budget *budget = ud;
	size_t old = ptr ? osize : 0;
	if (nsize == 0) {
		free(ptr);
		budget->used -= old;
		return NULL;
	}
	size_t ceiling = budget->limit + (budget->native > 0 || budget->collecting ? HEADROOM : 0);
	void *block = nsize > old && budget->used - old + nsize > ceiling ? NULL : realloc(ptr, nsize);
	if (!block && budget->native > 0) clua_exitformemory();
	if (block) budget->used = budget->used - old + nsize;
	return block;
}

static clua_Budget *clua_budget(lua_State *L) {
	void *budget;
	lua_getallocf(L, &budget);
	return budget;
}

/* Swift takes over the state. */
static void clua_enter(lua_State *L, clua_Budget *budget) {
	if (budget->native++ == 0 && lua_gc(L, LUA_GCISRUNNING)) {
		lua_gc(L, LUA_GCSTOP);
		budget->stopped = 1;
	}
}

/* Lua takes over the state again. A collector that the script stopped stays stopped. */
static void clua_leave(lua_State *L, clua_Budget *budget) {
	if (--budget->native == 0 && budget->stopped) {
		budget->stopped = 0;
		lua_gc(L, LUA_GCRESTART);
	}
}

/* A full collection with its finalizers. Each finalizer needs a call frame, which a state over its
   limit could not allocate, so the collection may use the headroom. */
static void clua_collect(lua_State *L, clua_Budget *budget) {
	budget->collecting = 1;
	lua_gc(L, LUA_GCCOLLECT);
	budget->collecting = 0;
}

static int clua_call(lua_State *L) {
	clua_Function f = (clua_Function)lua_touserdata(L, lua_upvalueindex(1));
	clua_Budget *budget = clua_budget(L);
	clua_enter(L, budget);
	int results = f(L);
	clua_leave(L, budget);
	/* The restart clears the debt of the collector, so what Swift allocated would never advance it.
	   A step here, with Lua in charge again, keeps up with garbage that only Swift functions make. */
	if (lua_gc(L, LUA_GCISRUNNING)) lua_gc(L, LUA_GCSTEP, 0);
	/* Over the limit, a full collection runs the finalizers of dropped objects first, which give back
	   the memory they hold outside the state. An emergency collection would not run them. When the
	   results of the function still do not fit, they are dropped and collected the same way, so that no
	   charge of an object outlives the memory error, which reports them. */
	if (budget->used > budget->limit && lua_gc(L, LUA_GCISRUNNING)) {
		clua_collect(L, budget);
		if (budget->used > budget->limit && results > 0) {
			lua_pop(L, results);
			clua_collect(L, budget);
			lua_pushliteral(L, "not enough memory");
			return lua_error(L);
		}
	}
	if (budget->used > budget->limit) {
		/* Any new block fails now. Lua collects first, and raises its memory error if the state still
		   holds too much. */
		lua_newuserdatauv(L, 1, 0);
		lua_pop(L, 1);
	}
	if (results >= 0) return results;
	luaL_where(L, 1);
	lua_insert(L, -2);
	lua_concat(L, 2);
	return lua_error(L);
}

int clua_pcall(lua_State *L, int arguments, int results) {
	clua_Budget *budget = clua_budget(L);
	clua_leave(L, budget);
	int status = lua_pcall(L, arguments, results, 0);
	clua_enter(L, budget);
	return status;
}

void clua_charge(lua_State *L, size_t bytes) {
	clua_budget(L)->used += bytes;
}

int clua_room(lua_State *L, size_t bytes) {
	clua_Budget *budget = clua_budget(L);
	return budget->used <= budget->limit && bytes <= budget->limit - budget->used;
}

void clua_uncharge(lua_State *L, size_t bytes) {
	clua_Budget *budget = clua_budget(L);
	budget->used -= bytes < budget->used ? bytes : budget->used;
}

int clua_nativedepth(lua_State *L) {
	return clua_budget(L)->native;
}

void clua_setmemoryline(const char *line) {
	clua_memory_length = strlcpy(clua_memory_line, line, sizeof clua_memory_line);
	if (clua_memory_length >= sizeof clua_memory_line) clua_memory_length = 0;
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

lua_State *clua_newstate(size_t limit) {
	clua_Budget *budget = malloc(sizeof *budget);
	if (!budget) return NULL;
	budget->used = 0;
	budget->limit = limit;
	budget->native = 0;
	budget->stopped = 0;
	budget->collecting = 0;
	lua_State *L = lua_newstate(clua_alloc, budget);
	if (!L) {
		free(budget);
		return NULL;
	}
	clua_enter(L, budget);
	return L;
}

void clua_close(lua_State *L) {
	clua_Budget *budget = clua_budget(L);
	/* lua_close runs the pending finalizers in protected calls of its own, so their errors stay in C. */
	budget->native = 0;
	lua_close(L);
	free(budget);
}

static char clua_cpu_line[1024];
static size_t clua_cpu_length;

static void clua_cpu_exceeded(int signal) {
	(void)signal;
	(void)write(STDOUT_FILENO, clua_cpu_line, clua_cpu_length);
	_exit(1);
}

int clua_limitprocessor(unsigned seconds, const char *line) {
	clua_cpu_length = strlcpy(clua_cpu_line, line, sizeof clua_cpu_line);
	if (clua_cpu_length >= sizeof clua_cpu_line) return -1;
	signal(SIGXCPU, clua_cpu_exceeded);
	struct rlimit limit = {seconds, seconds + 2};
	return setrlimit(RLIMIT_CPU, &limit);
}
