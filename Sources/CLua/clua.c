#include "clua.h"

#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

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

typedef struct {
	size_t used, limit;
} clua_Budget;

/* The allocator of luaL_newstate with a ceiling. A block that would pass the limit fails, and Lua
   raises its memory error. For a new block Lua passes the kind of object in osize, not a size. */
static void *clua_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
	clua_Budget *budget = ud;
	size_t old = ptr ? osize : 0;
	if (nsize == 0) {
		free(ptr);
		budget->used -= old;
		return NULL;
	}
	if (nsize > old && budget->used - old + nsize > budget->limit) return NULL;
	void *block = realloc(ptr, nsize);
	if (block) budget->used = budget->used - old + nsize;
	return block;
}

lua_State *clua_newstate(size_t limit) {
	clua_Budget *budget = malloc(sizeof *budget);
	if (!budget) return NULL;
	budget->used = 0;
	budget->limit = limit;
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
