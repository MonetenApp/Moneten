#include "clua.h"

#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

/* The memory of one state. Swift code may not raise a Lua error, because the long jump would skip
   its frames and leak what they hold. So while Swift runs, outside a protected call or in a function
   of Swift, the allocator allows HEADROOM bytes over the limit, which holds the largest body of a
   request. Back in Lua, clua_call raises the memory error from C. */
typedef struct {
	size_t used, limit;
	int native;
} clua_Budget;

#define HEADROOM ((size_t)64 << 20)

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
	size_t ceiling = budget->limit + (budget->native > 0 ? HEADROOM : 0);
	if (nsize > old && budget->used - old + nsize > ceiling) return NULL;
	void *block = realloc(ptr, nsize);
	if (block) budget->used = budget->used - old + nsize;
	return block;
}

static clua_Budget *clua_budget(lua_State *L) {
	void *budget;
	lua_getallocf(L, &budget);
	return budget;
}

static int clua_call(lua_State *L) {
	clua_Function f = (clua_Function)lua_touserdata(L, lua_upvalueindex(1));
	clua_Budget *budget = clua_budget(L);
	budget->native++;
	int results = f(L);
	budget->native--;
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
	budget->native--;
	int status = lua_pcall(L, arguments, results, 0);
	budget->native++;
	return status;
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
	budget->native = 1;
	lua_State *L = lua_newstate(clua_alloc, budget);
	if (!L) free(budget);
	return L;
}

void clua_close(lua_State *L) {
	void *budget;
	lua_getallocf(L, &budget);
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
