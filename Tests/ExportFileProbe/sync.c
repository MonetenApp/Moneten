#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

static char folder[PATH_MAX];
static void record(const char *event) {
	const char *path = getenv("MONETEN_EXPORT_SYNC_TRACE");
	if (!path) return;
	int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0600);
	if (fd < 0) abort();
	if (write(fd, event, strlen(event)) < 0) abort();
	close(fd);
}
static int export_file(int fd) {
	char path[PATH_MAX];
	return fcntl(fd, F_GETPATH, path) == 0 && strstr(path, "/.moneten-export-") != NULL;
}
static int probe_fcntl(int fd, int command, ...) {
	if (command == F_FULLFSYNC) {
		if (export_file(fd)) {
			record("file\n");
			if (getenv("MONETEN_EXPORT_SYNC_DELAY")) usleep(2000000);
			if (getenv("MONETEN_EXPORT_SYNC_FALLBACK")) { errno = ENOTSUP; return -1; }
		}
		return fcntl(fd, command);
	}
	if (command == F_GETFD || command == F_GETFL || command == F_GETOWN || command == F_GETNOSIGPIPE) return fcntl(fd, command);
	va_list args;
	va_start(args, command);
	int result;
	if (command == F_DUPFD || command == F_DUPFD_CLOEXEC || command == F_SETFD || command == F_SETFL || command == F_SETOWN || command == F_SETNOSIGPIPE || command == F_NOCACHE || command == F_RDAHEAD) {
		result = fcntl(fd, command, va_arg(args, int));
	} else {
		result = fcntl(fd, command, va_arg(args, void *));
	}
	va_end(args);
	return result;
}
static int probe_sync(int fd) {
	char path[PATH_MAX];
	if (export_file(fd)) record("fallback\n");
	else if (fcntl(fd, F_GETPATH, path) == 0 && folder[0] && strcmp(path, folder) == 0) record("directory\n");
	return fsync(fd);
}
static int probe_rename(const char *from, const char *to) {
	int result = rename(from, to);
	if (result == 0 && strstr(from, "/.moneten-export-")) {
		char path[PATH_MAX];
		strlcpy(path, to, sizeof(path));
		char *slash = strrchr(path, '/');
		if (slash) *slash = '\0';
		if (!realpath(path, folder)) abort();
		record("rename\n");
	}
	return result;
}
__attribute__((used)) static struct { const void *replacement, *original; } hooks[]
__attribute__((section("__DATA,__interpose"))) = {
	{ (const void *)probe_fcntl, (const void *)fcntl },
	{ (const void *)probe_sync, (const void *)fsync },
	{ (const void *)probe_rename, (const void *)rename }
};
